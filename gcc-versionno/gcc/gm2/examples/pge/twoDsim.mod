(* Copyright (C) 2008, 2009, 2010, 2011, 2012
                 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. *)

IMPLEMENTATION MODULE twoDsim ;

FROM SYSTEM IMPORT ADR ;
FROM Storage IMPORT ALLOCATE, DEALLOCATE ;
FROM Indexing IMPORT Index, InitIndex, PutIndice, GetIndice, HighIndice ;
FROM libc IMPORT printf, exit ;
FROM deviceIf IMPORT flipBuffer, glyphCircle, glyphPolygon, blue, red, black, yellow, purple ;
FROM libm IMPORT sqrt, asin, sin, cos ;
FROM roots IMPORT findQuartic, findQuadratic, findAllRootsQuartic, nearZero ;
FROM Fractions IMPORT Fract, zero, one, putReal, initFract ;
FROM Points IMPORT Point, initPoint ;
FROM GC IMPORT collectAll ;
FROM coord IMPORT Coord, initCoord, normaliseCoord, perpendiculars, scaleCoord,
                  subCoord, addCoord, lengthCoord, rotateCoord, dotProd ;
FROM polar IMPORT Polar, initPolar, polarToCoord, coordToPolar ;
FROM history IMPORT isDuplicate, removeOlderHistory, forgetHistory, purge, occurred ;
FROM delay IMPORT getActualFPS ;
FROM MathLib0 IMPORT pi ;


CONST
   MaxPolygonPoints       =     6 ;
   DefaultFramesPerSecond =    24.0 ;
   Debugging              = FALSE ;
   BufferedTime           =     0.1 ;
   InactiveTime           =     1.0 ;  (* the time we keep simulating after all colision events have expired *)

TYPE
   ObjectType = (polygonOb, circleOb, pivotOb, rpolygonOb) ;

   eventType = (frameEvent, circlesEvent, circlePolygonEvent, polygonPolygonEvent) ;

   descP = PROCEDURE (eventDesc, CARDINAL, CARDINAL, CARDINAL, CARDINAL, Coord) : eventDesc ;

   cDesc = RECORD
              cPoint    : Coord ;      (* where in the 2D world does this collision happen *)
              cid1, cid2: CARDINAL ;   (* id of the two circles which will collide *)
           END ;

   cpDesc = RECORD
               cPoint  : Coord ;       (* where in the 2D world does this collision happen *)
               pid, cid: CARDINAL ;    (* id of the circle and polygon which will collide *)
               kind    : whereHit ;    (* does the circle hit the corner or edge?   *)
               lineNo  : CARDINAL ;    (* if the edge is hit then this value will be 1..nPoints *)
                                       (* indicating that p[lineNo-1] p[lineNo] is the line which is hit *)
               pointNo : CARDINAL ;    (* if the corner is hit then this value will be 1..nPoints *)
                                       (* indicating that p[pointNo-1] is the corner which is hit *)
            END ;

   ppDesc = RECORD
               cPoint  : Coord ;       (* where in the 2D world does this collision happen *)
               pid1,                   (* one of pid1 corners will hit pid2.  *)
               pid2    : CARDINAL ;
               kind    : whereHit ;    (* does pid1 hit the corner or edge of pid2? *)
               pointNo,                (* pointNo is the point of pid1 which collides with pid2. *)
               lineCorner: CARDINAL ;  (* If the edge is hit then this value will be 1..nPoints *)
                                       (* indicating that p[lineCorner-1] p[lineCorner] is the line which is hit *)
                                       (* if the corner is hit then this value will be 1..nPoints *)
                                       (* indicating that p[lineCorner-1] is the corner which is hit *)
            END ;

   eventDesc = POINTER TO RECORD
                              CASE etype: eventType OF

                              frameEvent         :  |
                              circlesEvent       :  cc: cDesc |
                              circlePolygonEvent :  cp: cpDesc |
                              polygonPolygonEvent:  pp: ppDesc |

                              END ;
                              next: eventDesc ;
                           END ;

   Object = POINTER TO RECORD
                          id             : CARDINAL ;
                          fixed,
                          stationary     : BOOLEAN ;
                          vx, vy, ax, ay : REAL ;
                          angularVelocity: REAL ;

                          CASE object: ObjectType OF

                          polygonOb :  p: Polygon |
                          circleOb  :  c: Circle |
                          pivotOb   :  v: Pivot |
                          rpolygonOb:  r: RotatingPolygon

                          END
                       END ;

   Pivot = RECORD
              pos: Coord ;
              id1,
              id2: CARDINAL ;
           END ;

   Circle = RECORD
               pos : Coord ;
               r   : REAL ;
               mass: REAL ;
               col : Colour ;
            END ;

   Polygon = RECORD
                nPoints: CARDINAL ;
                points : ARRAY [0..MaxPolygonPoints] OF Coord ;
                mass   : REAL ;
                col    : Colour ;
             END ;

   RotatingPolygon = RECORD
                        nPoints: CARDINAL ;
                        points : ARRAY [0..MaxPolygonPoints] OF Polar ;
                        mass   : REAL ;
                        col    : Colour ;
                        cOfG   : Coord ;
                     END ;

   eventProc = PROCEDURE (eventQueue) ;

   eventQueue = POINTER TO RECORD
                              time: REAL ;
                              p   : eventProc ;
                              ePtr: eventDesc ;
                              next: eventQueue ;
                           END ;


VAR
   objects           : Index ;
   maxId             : CARDINAL ;
   lastCollisionTime,
   collisionTime,
   currentTime,
   replayPerSecond,
   framesPerSecond   : REAL ;
   simulatedGravity  : REAL ;
   eventQ,
   freeEvents        : eventQueue ;
   freeDesc          : eventDesc ;
   drawCollisionFrame: BOOLEAN ;


(*
   Assert - 
*)

PROCEDURE Assert (b: BOOLEAN) ;
BEGIN
   IF NOT b
   THEN
      printf("error assert failed\n") ;
      HALT
   END
END Assert ;


(*
   AssertR - 
*)

PROCEDURE AssertR (a, b: REAL) ;
BEGIN
   IF NOT nearZero(a-b)
   THEN
      printf("error assert failed: %g should equal %g difference is %g\n", a, b, a-b)
   END
END AssertR ;


(*
   AssertRDebug - 
*)

PROCEDURE AssertRDebug (a, b: REAL; message: ARRAY OF CHAR) ;
BEGIN
   IF nearZero(a-b)
   THEN
      printf("%s passed\n", ADR(message))
   ELSE
      printf("%s failed  %g should equal %g difference is %g\n", ADR(message), a, b, a-b)
   END
END AssertRDebug ;


(*
   dumpCircle - 
*)

PROCEDURE dumpCircle (o: Object) ;
BEGIN
   WITH o^ DO
      printf("circle at (%g, %g) radius %g mass %g colour %d\n", c.pos.x, c.pos.y, c.r, c.mass, c.col)
   END
END dumpCircle ;


(*
   dumpPolygon - 
*)

PROCEDURE dumpPolygon (o: Object) ;
VAR
   i: CARDINAL ;
BEGIN
   WITH o^ DO
      i := 0 ;
      printf("polygon mass %g colour %d\n", p.mass, p.col) ;
      WHILE i<p.nPoints DO
         printf("  line (%g,%g)\n", p.points[i].x, p.points[i].y) ;
         INC(i)
      END
   END
END dumpPolygon ;


(*
   dumpRotating - 
*)

PROCEDURE dumpRotating (o: Object) ;
VAR
   i : CARDINAL ;
   c0: Coord ;
BEGIN
   WITH o^ DO
      i := 0 ;
      printf("rotating polygon mass %g colour %d\n", r.mass, r.col) ;
      printf("  c of g  (%g,%g)\n", r.cOfG.x, r.cOfG.y) ;
      WHILE i<p.nPoints DO
         c0 := addCoord(r.cOfG, polarToCoord(r.points[i])) ;
         printf("  point at (%g,%g)\n", c0.x, c0.y) ;
         INC(i)
      END
   END
END dumpRotating ;


(*
   DumpObject - 
*)

PROCEDURE DumpObject (o: Object) ;
BEGIN
   WITH o^ DO
      printf("object %d ", id) ;
      IF fixed
      THEN
         printf("is fixed ")
      ELSE
         printf("is movable ") ;
         IF stationary
         THEN
            printf("but is now stationary ")
         ELSIF NOT nearZero(angularVelocity)
         THEN
            printf(" and has a rotating velocity of %g\n", angularVelocity)
         END
      END ;
      CASE object OF

      circleOb  :  dumpCircle(o) |
      polygonOb :  dumpPolygon(o) |
      pivotOb   :  printf("pivot\n") |
      rpolygonOb:  dumpRotating(o)

      ELSE
      END ;
      IF (NOT fixed) AND (NOT stationary)
      THEN
         printf("    velocity (%g, %g) acceleration (%g, %g)\n", vx, vy, ax, ay)
      END
   END
END DumpObject ;


(*
   c2p - returns a Point given a Coord.
*)

PROCEDURE c2p (c: Coord) : Point ;
BEGIN
   RETURN initPoint(putReal(c.x), putReal(c.y))
END c2p ;


(*
   gravity - turn on gravity at: g m^2
*)

PROCEDURE gravity (g: REAL) ;
BEGIN
   simulatedGravity := g
END gravity ;


(*
   newObject - creates an object of, type, and returns its, id.
*)

PROCEDURE newObject (type: ObjectType) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   INC(maxId) ;
   NEW(optr) ;
   WITH optr^ DO
      id              := maxId ;
      fixed           := FALSE ;
      stationary      := FALSE ;
      object          := type ;
      vx              := 0.0 ;
      vy              := 0.0 ;
      ax              := 0.0 ;
      ay              := 0.0 ;
      angularVelocity := 0.0
   END ;
   PutIndice(objects, maxId, optr) ;
   RETURN( maxId )
END newObject ;


(*
   box - place a box in the world at (x0,y0),(x0+i,y0+j)
*)

PROCEDURE box (x0, y0, i, j: REAL; colour: Colour) : CARDINAL ;
VAR
   id: CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(polygonOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      p.nPoints := 4 ;
      p.points[0].x := i ;
      p.points[0].y := 0.0 ;
      p.points[1].x := 0.0 ;
      p.points[1].y := j ;
      p.points[2].x := -i ;
      p.points[2].y := 0.0 ;
      p.points[3].x := 0.0 ;
      p.points[3].y := -j ;
      p.col := colour ;
   END ;
   RETURN id
END box ;


(*
   poly3 - place a triangle in the world at:
           (x0,y0),(x1,y1),(x2,y2)
*)

PROCEDURE poly3 (x0, y0, x1, y1, x2, y2: REAL; colour: Colour) : CARDINAL ;
VAR
   id: CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(polygonOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      p.nPoints := 3 ;
      p.points[0].x := x0 ;
      p.points[0].y := y0 ;
      p.points[1].x := x1 ;
      p.points[1].y := y1 ;
      p.points[2].x := x2 ;
      p.points[2].y := y2 ;
      p.col := colour
   END ;
   RETURN id
END poly3 ;


(*
   poly4 - place a triangle in the world at:
           (x0,y0),(x1,y1),(x2,y2),(x3,y3)
*)

PROCEDURE poly4 (x0, y0, x1, y1, x2, y2, x3, y3: REAL; colour: Colour) : CARDINAL ;
VAR
   id: CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(polygonOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      p.nPoints := 4 ;
      p.points[0].x := x0 ;
      p.points[0].y := y0 ;
      p.points[1].x := x1 ;
      p.points[1].y := y1 ;
      p.points[2].x := x2 ;
      p.points[2].y := y2 ;
      p.points[3].x := x3 ;
      p.points[3].y := y3 ;
      p.col := colour
   END ;
   RETURN id
END poly4 ;


(*
   poly5 - place a pentagon in the world at:
           (x0,y0),(x1,y1),(x2,y2),(x3,y3),(x4,y4)
*)

PROCEDURE poly5 (x0, y0, x1, y1, x2, y2, x3, y3, x4, y4: REAL; colour: Colour) : CARDINAL ;
VAR
   id  : CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(polygonOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      p.nPoints := 5 ;
      p.points[0].x := x0 ;
      p.points[0].y := y0 ;
      p.points[1].x := x1 ;
      p.points[1].y := y1 ;
      p.points[2].x := x2 ;
      p.points[2].y := y2 ;
      p.points[3].x := x2 ;
      p.points[3].y := y2 ;
      p.points[4].x := x2 ;
      p.points[4].y := y2 ;
      p.col := colour
   END ;
   RETURN id
END poly5 ;


(*
   poly6 - place a hexagon in the world at:
           (x0,y0),(x1,y1),(x2,y2),(x3,y3),(x4,y4),(x5,y5)
*)

PROCEDURE poly6 (x0, y0, x1, y1, x2, y2, x3, y3, x4, y4, x5, y5: REAL; colour: Colour) : CARDINAL ;
VAR
   id  : CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(pivotOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      p.nPoints := 6 ;
      p.points[0].x := x0 ;
      p.points[0].y := y0 ;
      p.points[1].x := x1 ;
      p.points[1].y := y1 ;
      p.points[2].x := x2 ;
      p.points[2].y := y2 ;
      p.points[3].x := x2 ;
      p.points[3].y := y2 ;
      p.points[4].x := x2 ;
      p.points[4].y := y2 ;
      p.points[5].x := x2 ;
      p.points[5].y := y2 ;
      p.col := colour
   END ;
   RETURN id
END poly6 ;


(*
   mass - specify the mass of an object and return the, id.
          Only polygon (and box) and circle objects may have
          a mass.
*)

PROCEDURE mass (id: CARDINAL; m: REAL) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      CASE object OF

      polygonOb :  p.mass := m |
      circleOb  :  c.mass := m |
      rpolygonOb:  r.mass := m

      ELSE
      END
   END ;
   RETURN id
END mass ;


(*
   fix - fix the object to the world.
*)

PROCEDURE fix (id: CARDINAL) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      fixed := TRUE
   END ;
   RETURN id
END fix ;


(*
   circle - adds a circle to the world.  Center
            defined by: x0, y0 radius, r.
*)

PROCEDURE circle (x0, y0, radius: REAL; colour: Colour) : CARDINAL ;
VAR
   id  : CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(circleOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      c.pos.x := x0 ;
      c.pos.y := y0 ;
      c.r     := radius ;
      c.mass  := 0.0 ;
      c.col   := colour
   END ;
   RETURN id
END circle ;


(*
   pivot - pivot an object to position, (x0, y0).
*)

PROCEDURE pivot (x0, y0: REAL; id1: CARDINAL) : CARDINAL ;
VAR
   id  : CARDINAL ;
   optr: Object ;
BEGIN
   id := newObject(pivotOb) ;
   optr := GetIndice(objects, id) ;
   WITH optr^ DO
      v.pos.x := x0 ;
      v.pos.y := y0 ;
      v.id1 := id1
   END ;
   RETURN id
END pivot ;


(*
   velocity - give an object, id, a velocity, vx, vy.
*)

PROCEDURE velocity (id: CARDINAL; vx, vy: REAL) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   optr := GetIndice(objects, id) ;
   IF optr^.fixed
   THEN
      printf("object %d is fixed and therefore cannot be given a velocity\n",
             id)
   ELSE
      optr^.vx := vx ;
      optr^.vy := vy
   END ;
   RETURN id
END velocity ;


(*
   accel - give an object, id, an acceleration, ax, ay.
*)

PROCEDURE accel (id: CARDINAL; ax, ay: REAL) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   optr := GetIndice(objects, id) ;
   IF optr^.fixed
   THEN
      printf("object %d is fixed and therefore cannot be given an acceleration\n",
             id)
   ELSE
      optr^.ax := ax ;
      optr^.ay := ay
   END ;
   RETURN id
END accel ;


(*
   calculateCofG - 
*)

PROCEDURE calculateCofG (n: CARDINAL; p: ARRAY OF Coord) : Coord ;
VAR
   x, y: REAL ;
   r   : REAL ;
   i   : CARDINAL ;
BEGIN
   x := p[0].x ;
   y := p[0].y ;
   i := 1 ;
   WHILE i<n DO
      x := x + p[i].x ;
      y := y + p[i].y ;
      INC(i)
   END ;
   r := VAL(REAL, n) ;
   RETURN initCoord(x/r, y/r)
END calculateCofG ;


(*
   toRPolygon - convert polygon, id, into a rotating polygon.
*)

PROCEDURE toRPolygon (id: CARDINAL) ;
VAR
   nptr,
   optr: Object ;
   i   : CARDINAL ;
BEGIN
   optr := GetIndice(objects, id) ;
   IF optr^.object=polygonOb
   THEN
      NEW(nptr) ;
      nptr^ := optr^ ;
      WITH nptr^ DO
         object := rpolygonOb ;
         r.nPoints := optr^.p.nPoints ;
         r.cOfG := calculateCofG(r.nPoints, optr^.p.points) ;
         i := 0 ;
         WHILE i<r.nPoints DO
            r.points[i] := coordToPolar(subCoord(optr^.p.points[i], r.cOfG)) ;
            INC(i)
         END
      END ;
      optr^ := nptr^ ;
      DISPOSE(nptr)
   END
END toRPolygon ;


(*
   rotate - rotates object with a angular velocity, angle.
*)

PROCEDURE rotate (id: CARDINAL; angle: REAL) : CARDINAL ;
VAR
   optr: Object ;
BEGIN
   IF NOT nearZero(angle)
   THEN
      optr := GetIndice(objects, id) ;
      IF optr^.fixed
      THEN
         printf("object %d is fixed and therefore cannot be given an angular velocity\n",
                id)
      ELSE
         toRPolygon(id) ;
         optr^.angularVelocity := angle
      END
   END ;
   RETURN id
END rotate ;


(*
   fps - set frames per second.
*)

PROCEDURE fps (f: REAL) ;
BEGIN
   framesPerSecond := f
END fps ;


(*
   debugCircle - displays a circle at position, p, with radius, r, in colour, c.
*)

PROCEDURE debugCircle (p: Coord; r: REAL; c: Colour) ;
BEGIN
   glyphCircle(c2p(p), TRUE, zero(), putReal(r), c)
END debugCircle ;


(*
   debugLine - displays a line from, p1, to, p2, in the debugging colour.
*)

PROCEDURE debugLine (p1, p2: Coord) ;
VAR
   p: ARRAY [0..1] OF Point ;
BEGIN
   p[0] := c2p(p1) ;
   p[1] := c2p(p2) ;
   glyphPolygon(2, p, FALSE, initFract(0, 1, 16), yellow())
END debugLine ;


(*
   replayRate - set frames per second during replay.
*)

PROCEDURE replayRate (f: REAL) ;
BEGIN
   replayPerSecond := f
END replayRate ;


(*
   doCircle - pass parameters to the groffDevice.
*)

PROCEDURE doCircle (p: Coord; r: REAL; c: Colour) ;
BEGIN
   glyphCircle(c2p(p), TRUE, zero(), putReal(r), c)
END doCircle ;


(*
   doPolygon - 
*)

PROCEDURE doPolygon (n: CARDINAL; p: ARRAY OF Coord; c: Colour) ;
VAR
   points: ARRAY [0..MaxPolygonPoints] OF Point ;
   i     : CARDINAL ;
BEGIN
   FOR i := 0 TO n-1 DO
      points[i] := c2p(p[i])
   END ;
   glyphPolygon(n, points, TRUE, zero(), c)
END doPolygon ;


(*
   drawBoarder - 
*)

PROCEDURE drawBoarder (c: Colour) ;
VAR
   p: ARRAY [0..3] OF Point ;
BEGIN
   p[0] := initPoint(zero(), zero()) ;
   p[1] := initPoint(one(), zero()) ;
   p[2] := initPoint(one(), one()) ;
   p[3] := initPoint(zero(), one()) ;
   glyphPolygon(4, p, FALSE, initFract(0, 1, 100), c)
END drawBoarder ;


(*
   drawBackground - 
*)

PROCEDURE drawBackground (c: Colour) ;
VAR
   p: ARRAY [0..3] OF Point ;
BEGIN
   p[0] := initPoint(zero(), zero()) ;
   p[1] := initPoint(one(), zero()) ;
   p[2] := initPoint(one(), one()) ;
   p[3] := initPoint(zero(), one()) ;
   glyphPolygon(4, p, TRUE, zero(), c)
END drawBackground ;


(*
   getVelCoord - returns a velocity coordinate pair for Object, o.
*)

PROCEDURE getVelCoord (o: Object) : Coord ;
BEGIN
   WITH o^ DO
      IF fixed OR stationary
      THEN
         RETURN initCoord(0.0, 0.0)
      ELSE
         RETURN initCoord(vx, vy)
      END
   END
END getVelCoord ;


(*
   getAccelCoord - returns an acceleration coordinate pair for Object, o.
*)

PROCEDURE getAccelCoord (o: Object) : Coord ;
BEGIN
   WITH o^ DO
      IF fixed OR stationary
      THEN
         RETURN initCoord(0.0, 0.0)
      ELSE
         RETURN initCoord(ax, ay+simulatedGravity)
      END
   END
END getAccelCoord ;


(*
   drawFrame - 
*)

PROCEDURE drawFrame (e: eventQueue) ;
VAR
   po  : ARRAY [0..MaxPolygonPoints] OF Coord ;
   i, j,
   n   : CARDINAL ;
   optr: Object ;
   dt  : REAL ;
   vc,
   ac  : Coord ;
BEGIN
   dt := currentTime-lastCollisionTime ;
   drawBoarder(black()) ;
   n := HighIndice(objects) ;
   i := 1 ;
   WHILE i<=n DO
      optr := GetIndice(objects, i) ;
      vc := getVelCoord(optr) ;
      ac := getAccelCoord(optr) ;
      WITH optr^ DO
         CASE object OF

         circleOb  :  doCircle(newPositionCoord(c.pos, vc, ac, dt),
                               c.r, c.col) |
         polygonOb :  j := 0 ;
                      WHILE j<p.nPoints DO
                         po[j] := newPositionCoord(p.points[j], vc, ac, dt) ;
                         INC(j)
                      END ;
                      doPolygon(p.nPoints, po, p.col) |
         pivotOb   :  |
         rpolygonOb:  j := 0 ;
                      WHILE j<r.nPoints DO
                         po[j] := newPositionRotationCoord(r.cOfG, vc, ac, dt, angularVelocity, r.points[j]) ;
                         INC(j)
                      END ;
                      doPolygon(r.nPoints, po, r.col)

         END
      END ;
      INC(i)
   END
END drawFrame ;


(*
   drawFrameEvent - 
*)

PROCEDURE drawFrameEvent (e: eventQueue) ;
BEGIN
   drawFrame(e) ;
   addEvent(1.0/framesPerSecond, drawFrameEvent) ;
   flipBuffer ;
   collectAll
END drawFrameEvent ;


(*
   updateRPolygon - 
*)

PROCEDURE updateRPolygon (optr: Object; dt: REAL) ;
BEGIN
   WITH optr^ DO
      r.cOfG.x := newPositionScalar(r.cOfG.x, vx, ax, dt) ;
      r.cOfG.y := newPositionScalar(r.cOfG.y, vy, ay+simulatedGravity, dt) ;
      vx := vx + ax*dt ;
      vy := vy + (ay+simulatedGravity)*dt
   END
END updateRPolygon ;


(*
   updatePolygon - 
*)

PROCEDURE updatePolygon (optr: Object; dt: REAL) ;
VAR
   nvx,
   nvy: REAL ;
   i  : CARDINAL ;
BEGIN
   WITH optr^ DO
      i := 0 ;
(* new
      WHILE i<p.nPoints DO
         (* polygon points.[i].x *)
         p.points[i].x := newPositionScalar(p.points[i].x, vx, ax, dt) ;

         (* and points[i].y *)
         p.points[i].y := newPositionScalar(p.points[i].y, vy, ay+simulatedGravity, dt) ;
         INC(i)
      END ;
      vx := vx + ax*dt ;
      vy := vy + (ay+simulatedGravity)*dt ;
*)

(* old *)
      nvx := vx + ax*dt ;
      nvy := vy + (ay+simulatedGravity)*dt ;
      WHILE i<p.nPoints DO
         (* polygon points.[i].x *)
         p.points[i].x := p.points[i].x+dt*(vx+nvx)/2.0 ;

         (* and points[i].y *)
         p.points[i].y := p.points[i].y+dt*(vy+nvy)/2.0 ;
         INC(i)
      END ;
      vx := nvx ;
      vy := nvy
(* *)
   END
END updatePolygon ;


(*
   updateCircle - 
*)

PROCEDURE updateCircle (optr: Object; dt: REAL) ;
VAR
   vn: REAL ;
BEGIN
   WITH optr^ DO
(*
      checkZero(dt) ;
      checkZero(vx) ;
      checkZero(vy) ;
*)
      (* update vx and pos.x *)

      c.pos.x := newPositionScalar(c.pos.x, vx, ax, dt) ;
      vx := vx + ax*dt ;
(*
      vn := vx + ax*dt ;
      c.pos.x := c.pos.x+dt*(vx+vn)/2.0 ;
      vx := vn ;
*)
      (* update vy and pos.y *)
      c.pos.y := newPositionScalar(c.pos.y, vy, ay+simulatedGravity, dt) ;
      vy := vy + (ay+simulatedGravity)*dt ;
(*
      vn := vy + (ay+simulatedGravity)*dt ;
      c.pos.y := c.pos.y+dt*(vy+vn)/2.0 ;
      vy := vn
*)
   END
END updateCircle ;


(*
   updateOb - 
*)

PROCEDURE updateOb (optr: Object; dt: REAL) ;
BEGIN
   WITH optr^ DO
      IF (NOT fixed) AND (NOT stationary)
      THEN
         CASE object OF

         polygonOb :  updatePolygon(optr, dt) |
         circleOb  :  updateCircle(optr, dt) |
         pivotOb   :  |
         rpolygonOb:  updateRPolygon(optr, dt)

         END
      END
   END
END updateOb ;


(*
   updatePhysics - updates all positions of objects based on the passing of
                   dt seconds.
*)

PROCEDURE updatePhysics (dt: REAL) ;
VAR
   i, n: CARDINAL ;
   optr: Object ;
BEGIN
   n := HighIndice(objects) ;
   i := 1 ;
   WHILE i<=n DO
      optr := GetIndice(objects, i) ;
      updateOb(optr, dt) ;
      INC(i)
   END
END updatePhysics ;


(*
   displayEvent - 
*)

PROCEDURE displayEvent (e: eventQueue) ;
BEGIN
   WITH e^ DO
      printf("%g %p ", time, p);
      IF p=VAL(eventProc, drawFrameEvent)
      THEN
         printf("drawFrameEvent\n")
      ELSIF p=VAL(eventProc, doCollision)
      THEN
         printf("doCollision ")
      ELSE
         printf("unknown event ")
      END ;
      IF ePtr#NIL
      THEN
         WITH ePtr^ DO
            CASE etype OF
            
            frameEvent         :   printf("display frame event\n") |
            circlesEvent       :   printf("circle %d and circle %d colliding event\n", cc.cid1, cc.cid2) |
            circlePolygonEvent :   printf("circle %d and polygon %d colliding event\n", cp.cid, cp.pid) ;
                                   IF cp.kind=corner
                                   THEN
                                      printf("  hits polygon corner %d\n", cp.pointNo)
                                   ELSE
                                      printf("  hits polygon line %d\n", cp.lineNo)
                                   END |
            polygonPolygonEvent:   printf("polygon %d and polygon %d colliding event\n", pp.pid1, pp.pid2) ;
                                   IF pp.kind=corner
                                   THEN
                                      printf("  corner %d hits polygons corner %d\n", pp.pointNo, pp.lineCorner)
                                   ELSE
                                      printf("  corner %d hits polygons line %d\n", pp.pointNo, pp.lineCorner)
                                   END

            END
         END
      END
   END
END displayEvent ;


(*
   printQueue - prints out the event queue.
*)

PROCEDURE printQueue ;
VAR
   e: eventQueue ;
BEGIN
   printf("The event queue\n");
   printf("===============\n");
   e := eventQ ;
   WHILE e#NIL DO
      displayEvent(e) ;
      e := e^.next
   END
END printQueue ;


(*
   updateStats - 
*)

PROCEDURE updateStats (dt: REAL) ;
VAR
   lastTime: CARDINAL ;
   nextTime: CARDINAL ;
   fps     : CARDINAL ;
BEGIN
   lastTime := TRUNC(currentTime*10.0) ;
   nextTime := TRUNC((currentTime+dt)*10.0) ;
   IF lastTime#nextTime
   THEN
      fps := getActualFPS() ;
      printf("%d.%d seconds simulated, fps: %d\n", nextTime DIV 10, nextTime MOD 10, fps)
   END
END updateStats ;


(*
   doNextEvent - 
*)

PROCEDURE doNextEvent () : REAL ;
VAR
   e : eventQueue ;
   dt: REAL ;
   p : eventProc ;
BEGIN
   IF eventQ=NIL
   THEN
      printf("no more events on the event queue\n") ;
      HALT
   ELSE
      (* printQueue ; *)
      e := eventQ ;
      eventQ := eventQ^.next ;
      dt := e^.time ;
      p  := e^.p ;
      currentTime := currentTime + dt ;
      Assert((p=VAL(eventProc, drawFrameEvent)) OR
             (p=VAL(eventProc, doCollision)) OR
             (p=VAL(eventProc, debugFrame))) ;
      p(e) ;
      disposeDesc(e^.ePtr) ;
      disposeEvent(e) ;
      updateStats(dt) ;
      RETURN( dt )
   END
END doNextEvent ;


(*
   checkObjects - 
*)

PROCEDURE checkObjects ;
VAR
   i, n : CARDINAL ;
   optr : Object ;
   error: BOOLEAN ;
BEGIN
   error := FALSE ;
   n := HighIndice(objects) ;
   i := 1 ;
   WHILE i<=n DO
      optr := GetIndice(objects, i) ;
      WITH optr^ DO
         IF (NOT (optr^.fixed)) AND (optr^.c.mass=0.0)
         THEN
            printf("object %d is not fixed and does not have a mass\n",
                   optr^.id)
         END
      END ;
      INC(i)
   END ;
   IF error
   THEN
      exit(1)
   END
END checkObjects ;


(*
   checkZero - 
*)

PROCEDURE checkZero (VAR v: REAL) ;
BEGIN
   IF ((v>0.0) AND (v<0.01)) OR
      ((v<0.0) AND (v>-0.01))
   THEN
      v := 0.0
   END
END checkZero ;


(*
   checkZeroCoord - 
*)

PROCEDURE checkZeroCoord (c: Coord) : Coord ;
BEGIN
   IF nearZero(c.x)
   THEN
      c.x := 0.0
   END ;
   IF nearZero(c.y)
   THEN
      c.y := 0.0
   END ;
   RETURN c
END checkZeroCoord ;


(*
   inElastic - 
*)

PROCEDURE inElastic (VAR v: REAL) ;
BEGIN
   v := v * 0.98 ;  (* 0.98 *)
   checkZero(v)
END inElastic ;


(*
   checkStationary - checks to see if object, o, should be put into
                     the stationary state.
*)

PROCEDURE checkStationary (o: Object) ;
BEGIN
   WITH o^ DO
      IF NOT fixed
      THEN
         inElastic(vx) ;
         inElastic(vy) ;
         stationary := nearZero(vx) AND nearZero(vy) ;
         IF stationary
         THEN
            DumpObject(o)
         END
      END
   END
END checkStationary ;


(*
   checkStationaryCollision - 
*)

PROCEDURE checkStationaryCollision (a, b: Object) ;
BEGIN
   IF a^.stationary
   THEN
      printf("bumped into a stationary object\n") ;
      a^.vy := 1.0 ;
      IF a^.c.pos.x<b^.c.pos.x
      THEN
         a^.c.pos.x := a^.c.pos.x-0.001
      ELSE
         a^.c.pos.x := a^.c.pos.x+0.001
      END ;
      a^.c.pos.y := a^.c.pos.y+0.001 ;
      a^.stationary := FALSE ;
      DumpObject(a)
   ELSIF b^.stationary
   THEN
      checkStationaryCollision(b, a)
   END
END checkStationaryCollision ;


(*
   collideFixedCircles - works out the new velocity given that the circle
                         movable collides with the fixed circle.
*)

PROCEDURE collideFixedCircles (movable, fixed: Object) ;
BEGIN
   collideAgainstFixedCircle(movable, fixed^.c.pos)
END collideFixedCircles ;


(*
   collideAgainstFixedCircle - the movable object collides against a point, center.
                               center, is the center point of the other fixed circle.
                               This procedure works out the new velocity of the movable
                               circle given these constraints.
*)

PROCEDURE collideAgainstFixedCircle (movable: Object; center: Coord) ;
VAR
   r, j              : REAL ;
   c, normalCollision,
   relativeVelocity  : Coord ;
BEGIN
   (* calculate normal collision value *)
   c.x := movable^.c.pos.x - center.x ;
   c.y := movable^.c.pos.y - center.y ;
   r := sqrt(c.x*c.x+c.y*c.y) ;
   normalCollision.x := c.x/r ;
   normalCollision.y := c.y/r ;
   relativeVelocity.x := movable^.vx ;
   relativeVelocity.y := movable^.vy ;

   j := (-(1.0+1.0) *
         ((relativeVelocity.x * normalCollision.x) +
          (relativeVelocity.y * normalCollision.y)))/
        (((normalCollision.x*normalCollision.x) +
          (normalCollision.y*normalCollision.y)) *
         (1.0/movable^.c.mass)) ;

   movable^.vx := movable^.vx + (j * normalCollision.x) / movable^.c.mass ;
   movable^.vy := movable^.vy + (j * normalCollision.y) / movable^.c.mass ;

   checkStationary(movable)
END collideAgainstFixedCircle ;


(*
   collideMovableCircles - 
*)

PROCEDURE collideMovableCircles (iptr, jptr: Object) ;
VAR
   r, j              : REAL ;
   c, normalCollision,
   relativeVelocity  : Coord ;
BEGIN
   (* calculate normal collision value *)
   c.x := iptr^.c.pos.x - jptr^.c.pos.x ;
   c.y := iptr^.c.pos.y - jptr^.c.pos.y ;
   r := sqrt(c.x*c.x+c.y*c.y) ;
   normalCollision.x := c.x/r ;
   normalCollision.y := c.y/r ;
   relativeVelocity.x := iptr^.vx - jptr^.vx ;
   relativeVelocity.y := iptr^.vy - jptr^.vy ;
   j := (-(1.0+1.0) *
         ((relativeVelocity.x * normalCollision.x) +
          (relativeVelocity.y * normalCollision.y)))/
        (((normalCollision.x*normalCollision.x) +
          (normalCollision.y*normalCollision.y)) *
         (1.0/iptr^.c.mass + 1.0/jptr^.c.mass)) ;

   iptr^.vx := iptr^.vx + (j * normalCollision.x) / iptr^.c.mass ;
   iptr^.vy := iptr^.vy + (j * normalCollision.y) / iptr^.c.mass ;

   jptr^.vx := jptr^.vx - (j * normalCollision.x) / jptr^.c.mass ;
   jptr^.vy := jptr^.vy - (j * normalCollision.y) / jptr^.c.mass ;

   checkStationaryCollision(iptr, jptr) ;

   checkStationary(iptr) ;
   checkStationary(jptr)

END collideMovableCircles ;


(*
   circleCollision - 
*)

PROCEDURE circleCollision (iptr, jptr: Object) ;
BEGIN
   IF iptr^.fixed
   THEN
      collideFixedCircles(jptr, iptr)
   ELSIF jptr^.fixed
   THEN
      collideFixedCircles(iptr, jptr)
   ELSE
      collideMovableCircles(iptr, jptr)
   END
END circleCollision ;


(*
   collideCircleAgainstFixedEdge - modifies the circle velocity based upon the edge it hits.
                                   We use the formula:

                                   V = 2 * (-I . N ) * N + I

                                   where:

                                   I is the initial velocity vector
                                   V is the final velocity vector
                                   N is the normal to the line
*)

PROCEDURE collideCircleAgainstFixedEdge (cPtr: Object; p1, p2: Coord) ;
VAR
   n1, n2, v1, vel: Coord ;
BEGIN
   (* firstly we need to find the normal to the line *)
   sortLine(p1, p2) ;    (* p1 and p2 are the start end positions of the line *)

   v1 := subCoord(p2, p1) ;     (* v1 is the vector p1 -> p2 *)

   perpendiculars(v1, n1, n2) ;  (* n1 and n2 are normal vectors to the vector v1 *)

   (* use n1 *)
   n1 := normaliseCoord(n1) ;
   vel := initCoord(cPtr^.vx, cPtr^.vy) ;   (* vel is the initial velocity *)

   vel := addCoord(scaleCoord(n1, -2.0 * dotProd(vel, n1)), vel) ;  (* now it is the final velocity *)

   cPtr^.vx := vel.x ;   (* update velocity of object, cPtr *)
   cPtr^.vy := vel.y ;

   checkStationary(cPtr)

END collideCircleAgainstFixedEdge ;


(*
   circlePolygonCollision - 
*)

PROCEDURE circlePolygonCollision (e: eventQueue; cPtr, pPtr: Object) ;
VAR
   ln    : CARDINAL ;
   p1, p2: Coord ;
BEGIN
   WITH e^.ePtr^ DO
      IF etype=circlePolygonEvent
      THEN
         CASE cp.kind OF

         corner:  IF cPtr^.fixed
                  THEN
                     (* fixed circle against moving polygon *)
                     (* --fixme--   to do later *)
                  ELSIF pPtr^.fixed
                  THEN
                     (* moving circle hits fixed polygon corner *)
                     collideAgainstFixedCircle(cPtr, e^.ePtr^.cp.cPoint)
                  ELSE
                     (* both moving, to do later --fixme-- *)
                  END |
         edge  :  IF cPtr^.fixed
                  THEN
                     (* fixed circle against moving polygon *)
                     (* --fixme--   to do later *)
                  ELSIF pPtr^.fixed
                  THEN
                     (* moving circle hits fixed polygon, on the edge *)
                     ln := e^.ePtr^.cp.lineNo ;
                     getPolygonLine(ln, pPtr, p1, p2) ;
                     collideCircleAgainstFixedEdge(cPtr, p1, p2)
                  ELSE
                     (* both moving, to do later --fixme-- *)
                  END
        END
     ELSE
        HALT  (* should be circlePolygonEvent *)
     END
   END
END circlePolygonCollision ;


(*
   collidePolygonAgainstFixedCircle - 
*)

PROCEDURE collidePolygonAgainstFixedCircle (o: Object; collision: Coord) ;
BEGIN
   collideAgainstFixedCircle(o, collision) ;
   DumpObject(o)
END collidePolygonAgainstFixedCircle ;


(*
   collidePolygonAgainstFixedEdge - 
*)

PROCEDURE collidePolygonAgainstFixedEdge (o: Object; p1, p2: Coord) ;
BEGIN
   collideCircleAgainstFixedEdge(o, p1, p2) ;
   DumpObject(o)
END collidePolygonAgainstFixedEdge ;


(*
   polygonPolygonCollision - 
*)

PROCEDURE polygonPolygonCollision (e: eventQueue; id1, id2: Object) ;
VAR
   ln    : CARDINAL ;
   p1, p2: Coord ;
BEGIN
   displayEvent(e) ;
   DumpObject(id1) ;
   DumpObject(id2) ;
   WITH e^.ePtr^ DO
      IF etype=polygonPolygonEvent
      THEN
         CASE pp.kind OF

         corner:  IF id1^.fixed
                  THEN
                     (* id2 is moving and hit a fixed polygon, id1, on the corner *)
                     collidePolygonAgainstFixedCircle(id2, e^.ePtr^.pp.cPoint)
                  ELSIF id2^.fixed
                  THEN
                     (* id1 is moving and hit a fixed polygon, id2, on the corner *)
                     collidePolygonAgainstFixedCircle(id1, e^.ePtr^.pp.cPoint)
                  ELSE
                     (* both moving, to do later --fixme-- *)
                  END |
         edge  :  IF id1^.fixed
                  THEN
                     (* id2 is moving and hits a fixed polygon, id1, on the edge *)
                     ln := e^.ePtr^.pp.lineCorner ;
                     getPolygonLine(ln, id1, p1, p2) ;
                     collidePolygonAgainstFixedEdge(id2, p1, p2)
                  ELSIF id2^.fixed
                  THEN
                     (* id1 is moving and hits a fixed polygon, id2, on the edge *)
                     ln := e^.ePtr^.pp.lineCorner ;
                     getPolygonLine(ln, id2, p1, p2) ;
                     collidePolygonAgainstFixedEdge(id1, p1, p2)
                  ELSE
                     (* both moving, to do later --fixme-- *)
                  END
        END
     ELSE
        HALT  (* should be circlePolygonEvent *)
     END
   END
END polygonPolygonCollision ;


(*
   physicsCollision - handle the physics of a collision between
                      the two objects defined in, e.
*)

PROCEDURE physicsCollision (e: eventQueue) ;
VAR
   id1, id2    : Object ;
BEGIN
   collisionTime := currentTime ;

   WITH e^.ePtr^ DO
      CASE etype OF

      circlesEvent:  id1 := GetIndice(objects, cc.cid1) ;
                     id2 := GetIndice(objects, cc.cid2) ;
                     circleCollision(id1, id2) |

      circlePolygonEvent:
                     id1 := GetIndice(objects, cp.cid) ;
                     id2 := GetIndice(objects, cp.pid) ;
                     circlePolygonCollision(e, id1, id2) |

      polygonPolygonEvent:
                     id1 := GetIndice(objects, pp.pid1) ;
                     id2 := GetIndice(objects, pp.pid2) ;
                     polygonPolygonCollision(e, id1, id2)

      END
   END
END physicsCollision ;


(*
   doCollision - 
*)

PROCEDURE doCollision (e: eventQueue) ;
BEGIN
   updatePhysics(currentTime-lastCollisionTime) ;
   lastCollisionTime := currentTime ;
   IF drawCollisionFrame
   THEN
      drawFrame(e)
   END ;
   flipBuffer ;
   collectAll ;
   physicsCollision(e) ;
   addNextCollisionEvent(lastCollisionTime-BufferedTime)
END doCollision ;


(*
   sqr - 
*)

PROCEDURE sqr (v: REAL) : REAL ;
BEGIN
   RETURN v*v
END sqr ;


(*
   cub - 
*)

PROCEDURE cub (v: REAL) : REAL ;
BEGIN
   RETURN v*v*v
END cub ;


(*
   quad - 
*)

PROCEDURE quad (v: REAL) : REAL ;
BEGIN
   RETURN v*v*v*v
END quad ;


(*
   getCircleValues - assumes, o, is a circle and retrieves:
                     center    (x, y)
                     radius    radius
                     velocity  (vx, vy)
                     accel     (ax, ay)
*)

PROCEDURE getCircleValues (o: Object; VAR x, y, radius, vx, vy, ax, ay: REAL) ;
BEGIN
   WITH o^ DO
      x      := c.pos.x ;
      y      := c.pos.y ;
      radius := c.r
   END ;
   getObjectValues(o, vx, vy, ax, ay)
END getCircleValues ;


(*
   getObjectValues - fills in velocity and acceleration x, y, values.
*)

PROCEDURE getObjectValues (o: Object; VAR vx, vy, ax, ay: REAL) ;
BEGIN
   IF o^.fixed OR o^.stationary
   THEN
      vx := 0.0 ;
      vy := 0.0 ;
      ax := 0.0 ;
      ay := 0.0
   ELSE
      vx := o^.vx ;
      vy := o^.vy ;
      ax := o^.ax ;
      ay := o^.ay + simulatedGravity
   END
END getObjectValues ;


(*
   maximaCircleCollision - 
*)

PROCEDURE maximaCircleCollision (VAR array: ARRAY OF REAL;
                                 a, b, c, d, e, f, g, h, i, j, k, l, m, n: REAL) ;
BEGIN
#  include "circles.m"
END maximaCircleCollision ;


(*
   earlierCircleCollision - let the following abreviations be assigned.
                            Note i is one circle, j is another circle.
                                 v is velocity, a, acceleration, x, y axis.
                                 r is radius.

                            Single letter variables are used since wxmaxima
                            only operates with these.  Thus the output from wxmaxima
                            can be cut and pasted into the program.

                            a = xi
                            b = xj
                            c = vxi
                            d = vxj
                            e = aix
                            f = ajx
                            g = yi
                            h = yj
                            k = vyi
                            l = vyj
                            m = aiy
                            n = ajy
                            o = ri
                            p = rj

                            t          is the time of this collision (if any)
                            tc         is the time of the next collision.
*)

PROCEDURE earlierCircleCollision (VAR t, tc: REAL;
                                  a, b, c, d, e, f, g, h, k, l, m, n, o, p: REAL) : BOOLEAN ;
VAR
   A, B, C, D, E, T: REAL ;
   array           : ARRAY [0..4] OF REAL ;
BEGIN
   (* thanks to wxmaxima  (expand ; factor ; ratsimp) *)

   A := sqr(n)-2.0*m*n+sqr(m)+sqr(f)-2.0*e*f+sqr(e) ;
   B := (4.0*l-4.0*k)*n+(4.0*k-4.0*l)*m+(4.0*d-4.0*c)*f+(4.0*c-4.0*d)*e ;
   C := (4.0*h-4.0*g)*n+(4.0*g-4.0*h)*m+4.0*sqr(l)-8.0*k*l+4.0*sqr(k)+(4.0*b-4.0*a)*f+(4.0*a-4.0*b)*e+4.0*sqr(d)-8.0*c*d+4.0*sqr(c) ;
   D := (8.0*h-8.0*g)*l+(8.0*g-8.0*h)*k+(8.0*b-8.0*a)*d+(8.0*a-8.0*b)*c ;
   E := 4.0*sqr(h)-8.0*g*h+4.0*sqr(g)+4.0*sqr(b)-8.0*a*b+4.0*sqr(a)-sqr(2.0*(p+o)) ;

(*
   maximaCircleCollision (array,
                          a, c, e, g, k, m,
                          b, d, f, h, l, n,
                          o, p) ;

   AssertRDebug(array[4], A, "A") ;
   AssertRDebug(array[3], B, "B") ;
   AssertRDebug(array[2], C, "C") ;
   AssertRDebug(array[1], D, "D") ;
   AssertRDebug(array[0], E, "E") ;
*)
   (* now solve for values of t which satisfy   At^4 + Bt^3 + Ct^2 + Dt^1 + Et^0 = 0 *)
   IF findQuartic(A, B, C, D, E, t)
   THEN
      T := A*(sqr(t)*sqr(t))+B*(sqr(t)*t)+C*sqr(t)+D*t+E ;
      IF Debugging
      THEN
         printf("%gt^4 + %gt^3 +%gt^2 + %gt + %g = %g    (t=%g)\n",
                A, B, C, D, E, T, t)
      END ;
      (* remember tc is -1.0 initially, to force it to be set once *)
      IF ((tc<0.0) OR (t<tc)) AND (NOT nearZero(t))
      THEN
         RETURN TRUE
      END
   END ;
   RETURN FALSE
END earlierCircleCollision ;


(*
   findCollisionCircles - 

   using:

   S = UT + (AT^2)/2
   compute xin and yin which are the new (x,y) positions of object i at time, t.
   compute xjn and yjn which are the new (x,y) positions of object j at time, t.
   now compute difference between objects and if they are ri+rj  (radius of circle, i, and, j)
   apart then we have a collision at time, t.

   xin = xi + vxi * t + (aix * t^2) / 2.0
   yin = yi + vyi * t + (aiy * t^2) / 2.0

   xjn = xj + vxj * t + (ajx * t^2) / 2.0
   yjn = yj + vyj * t + (ajy * t^2) / 2.0

   ri + rj == sqrt(abs(xin-xjn)^2 + abs(yin-yjn)^2)     for values of t

   ri + rj == sqrt(((xi + vxi * t + aix * t^2 / 2.0) - (xj + vxj * t + ajx * t^2 / 2.0))^2 +
                   ((yi + vyi * t + aiy * t^2 / 2.0) - (yj + vyj * t + ajy * t^2 / 2.0))^2)

   let:

   a = xi
   b = xj
   c = vxi
   d = vxj
   e = aix
   f = ajx
   g = yi
   h = yj
   k = vyi
   l = vyj
   m = aiy
   n = ajy
   o = ri
   p = rj
   t = t

   o  + p  == sqrt(((a  + c   * t + e   * t^2 / 2.0) - (b  + d   * t +   f * t^2 / 2.0))^2 +
                   ((g  + k   * t + m   * t^2 / 2.0) - (h  + l   * t +   n * t^2 / 2.0))^2)

   o  + p  == sqrt(((a  + c   * t + e   * t^2 / 2.0) - (b  + d   * t +   f * t^2 / 2.0))^2 +
                   ((g  + k   * t + m   * t^2 / 2.0) - (h  + l   * t +   n * t^2 / 2.0))^2)

   0       == ((a  + c   * t + e   * t^2 / 2.0) - (b  + d   * t +   f * t^2 / 2.0))^2 +
              ((g  + k   * t + m   * t^2 / 2.0) - (h  + l   * t +   n * t^2 / 2.0))^2 -
              (o  + p)^2

   now using wxmaxima
   expand ; factor ; ratsimp

   p+o    ==  (sqrt((n^2-2*m*n+m^2+f^2-2*e*f+e^2)*t^4+
                   ((4*l-4*k)*n+(4*k-4*l)*m+(4*d-4*c)*f+(4*c-4*d)*e)*t^3+
                   ((4*h-4*g)*n+(4*g-4*h)*m+4*l^2-8*k*l+4*k^2+(4*b-4*a)*f+(4*a-4*b)*e+4*d^2-8*c*d+4*c^2)*t^2+
                   ((8*h-8*g)*l+(8*g-8*h)*k+(8*b-8*a)*d+(8*a-8*b)*c)*t+4*h^2-8*g*h+4*g^2+4*b^2-8*a*b+4*a^2))/2

   2*(p+o) ==  (sqrt((n^2-2*m*n+m^2+f^2-2*e*f+e^2)*t^4+
                    ((4*l-4*k)*n+(4*k-4*l)*m+(4*d-4*c)*f+(4*c-4*d)*e)*t^3+
                    ((4*h-4*g)*n+(4*g-4*h)*m+4*l^2-8*k*l+4*k^2+(4*b-4*a)*f+(4*a-4*b)*e+4*d^2-8*c*d+4*c^2)*t^2+
                    ((8*h-8*g)*l+(8*g-8*h)*k+(8*b-8*a)*d+(8*a-8*b)*c)*t+4*h^2-8*g*h+4*g^2+4*b^2-8*a*b+4*a^2))

   (2*(p+o))^2 == ((n^2-2*m*n+m^2+f^2-2*e*f+e^2)*t^4+
                   ((4*l-4*k)*n+(4*k-4*l)*m+(4*d-4*c)*f+(4*c-4*d)*e)*t^3+
                   ((4*h-4*g)*n+(4*g-4*h)*m+4*l^2-8*k*l+4*k^2+(4*b-4*a)*f+(4*a-4*b)*e+4*d^2-8*c*d+4*c^2)*t^2+
                   ((8*h-8*g)*l+(8*g-8*h)*k+(8*b-8*a)*d+(8*a-8*b)*c)*t+4*h^2-8*g*h+4*g^2+4*b^2-8*a*b+4*a^2))

   0           ==  (n^2-2*m*n+m^2+f^2-2*e*f+e^2)*t^4+
                   ((4*l-4*k)*n+(4*k-4*l)*m+(4*d-4*c)*f+(4*c-4*d)*e)*t^3+
                   ((4*h-4*g)*n+(4*g-4*h)*m+4*l^2-8*k*l+4*k^2+(4*b-4*a)*f+(4*a-4*b)*e+4*d^2-8*c*d+4*c^2)*t^2+
                   ((8*h-8*g)*l+(8*g-8*h)*k+(8*b-8*a)*d+(8*a-8*b)*c)*t+
                   4*h^2-8*g*h+4*g^2+4*b^2-8*a*b+4*a^2)-
                   ((2*(p+o))^2)

   solve polynomial:

   A := sqr(n)-2.0*m*n+sqr(m)+sqr(f)-2.0*e*f+sqr(e) ;
   B := (4.0*l-4.0*k)*n+(4.0*k-4.0*l)*m+(4.0*d-4.0*c)*f+(4.0*c-4.0*d)*e ;
   C := (4.0*h-4.0*g)*n+(4.0*g-4.0*h)*m+4.0*sqr(l)-8.0*k*l+4.0*sqr(k)+(4.0*b-4.0*a)*f+(4.0*a-4.0*b)*e+4.0*sqr(d)-8.0*c*d+4.0*sqr(c) ;
   D := (8.0*h-8.0*g)*l+(8.0*g-8.0*h)*k+(8.0*b-8.0*a)*d+(8.0*a-8.0*b)*c ;
   E := 4.0*sqr(h)-8.0*g*h+4.0*sqr(g)+4.0*sqr(b)-8.0*a*b+4.0*sqr(a)-sqr(2.0*(p+o)) ;
*)

PROCEDURE findCollisionCircles (iptr, jptr: Object; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   a, b, c, d, e,
   f, g, h, k, l,
   m, n, o, p, t: REAL ;
   i, j         : CARDINAL ;
   T            : REAL ;
BEGIN
(*
   DumpObject(iptr) ;
   DumpObject(jptr) ;
*)
   (*
        a        xi
        g        yi
        o        ri
        c        vxi
        k        vyi
        e        axi
        m        ayi
    *)
   getCircleValues(iptr, a, g, o, c, k, e, m) ;

   (*
        b         xj
        h         yj
        d         vxj
        l         vyj
        f         ajx
        n         ajy
   *)

   getCircleValues(jptr, b, h, p, d, l, f, n) ;
   IF earlierCircleCollision(t, tc,
                             a, b, c, d, e, f, g, h, k, l, m, n, o, p)
   THEN
      tc := t ;
      edesc := makeCirclesDesc(edesc, iptr^.id, jptr^.id)
   END
END findCollisionCircles ;


(*
   stop - 
*)

PROCEDURE stop ;
BEGIN
END stop ;


(*
   makeCirclesPolygonDesc - returns an eventDesc describing the collision between a circle and a polygon.
*)

PROCEDURE makeCirclesPolygonDesc (edesc: eventDesc; cid, pid: CARDINAL;
                                  lineNo, pointNo: CARDINAL; collisionPoint: Coord) : eventDesc ;
BEGIN
   IF edesc=NIL
   THEN
      edesc := newDesc()
   END ;
   WITH edesc^ DO
      edesc^.etype := circlePolygonEvent ;
      edesc^.cp.pid := pid ;
      edesc^.cp.cid := cid ;
      edesc^.cp.cPoint := collisionPoint ;
      IF lineNo=0
      THEN
         edesc^.cp.kind := corner
      ELSE
         edesc^.cp.kind := edge
      END ;
      edesc^.cp.lineNo := lineNo ;
      edesc^.cp.pointNo := pointNo
   END ;
   RETURN edesc
END makeCirclesPolygonDesc ;


(*
   checkIfPointHits - return TRUE if t0 is either the first hit found or
                      is sooner than, tc.  It determines a hit by working out
                      the final position of partical:
                      x = s + ut + 1/2a t^2

                      if x>=0.0 and x <= length then it hits.
*)

PROCEDURE checkIfPointHits (timeOfPrevCollision: REAL; t, length: REAL; s, u, a: REAL) : BOOLEAN ;
VAR
   x: REAL ;
BEGIN
   (* if t is later than tc, then we don't care as we already have found an earlier hit *)
   IF ((timeOfPrevCollision=-1) OR (t<timeOfPrevCollision)) AND (NOT nearZero(timeOfPrevCollision))
   THEN
      (* at time, t, what is the value of x ? *)
      x := newPositionScalar(s, u, a, t) ;

      (* if x lies between 0 .. length then it hits! *)
      IF (x>=0.0) AND (x<=length)
      THEN
         (* new earlier collision time found *)
         RETURN TRUE
      END
   END ;
   RETURN FALSE
END checkIfPointHits ;


(*
   newPositionScalar - calculates the new position of a scalar in the future.
*)

PROCEDURE newPositionScalar (s, u, a, t: REAL) : REAL ;
BEGIN
   RETURN s + u*t + a * (t*t) / 2.0
END newPositionScalar ;


(*
   newPositionRotationSinScalar - works out the new Y position for a point whose:

                                  current cofg Y position is:   c
                                  initial Y velocity is     :   u
                                  Y acceleration is         :   a
                                  angular velocity          :   w
                                  polar coord position rel
                                  to cofg is                :   p
*)

PROCEDURE newPositionRotationSinScalar (c, u, a, t, w: REAL; p: Polar) : REAL ;
VAR
   O: REAL ;
BEGIN
   O := newPositionScalar(c, u, a, t) ;
   RETURN O + p.r * sin(w*t + p.w)
END newPositionRotationSinScalar ;


(*
   newPositionRotationCosScalar - works out the new X position for a point whose:

                                  current cofg X position is:   c
                                  initial X velocity is     :   u
                                  X acceleration is         :   a
                                  angular velocity          :   w
                                  polar coord position rel
                                  to cofg is                :   p
*)

PROCEDURE newPositionRotationCosScalar (c, u, a, t, w: REAL; p: Polar) : REAL ;
VAR
   O: REAL ;
BEGIN
   O := newPositionScalar(c, u, a, t) ;
   RETURN O + p.r * cos(w*t + p.w)
END newPositionRotationCosScalar ;


(*
   newPositionCoord - calculates the new position of point in the future.
*)

PROCEDURE newPositionCoord (c, u, a: Coord; t: REAL) : Coord ;
BEGIN
   RETURN initCoord(newPositionScalar(c.x, u.x, a.x, t),
                    newPositionScalar(c.y, u.y, a.y, t))
END newPositionCoord ;


(*
   newPositionRotationCoord - calculates the new position of point, c+v, in the future.
                              Given angular velocity         : w
                                    time                     : t
                                    initial vel              : u
                                    accel                    : a
                                    c of g                   : c
                                    polar coord of the point : p
*)

PROCEDURE newPositionRotationCoord (c, u, a: Coord; t, w: REAL; p: Polar) : Coord ;
BEGIN
   RETURN initCoord(newPositionRotationSinScalar(c.x, u.x, a.x, t, w, p),
                    newPositionRotationCosScalar(c.y, u.y, a.y, t, w, p))
END newPositionRotationCoord ;


(*
   hLine - debugging procedure to display a line on a half scale axis.
*)

PROCEDURE hLine (p1, p2: Coord; c: Colour) ;
VAR
   p: ARRAY [0..1] OF Point ;
BEGIN
   p1 := scaleCoord(p1, 0.5) ;
   p2 := scaleCoord(p2, 0.5) ;
   p1 := addCoord(p1, initCoord(0.5, 0.5)) ;
   p2 := addCoord(p2, initCoord(0.5, 0.5)) ;
   p[0] := c2p(p1) ;
   p[1] := c2p(p2) ;
   glyphPolygon(2, p, FALSE, initFract(0, 1, 16), c)
END hLine ;


(*
   hPoint - debugging procedure to display a line on a half scale axis.
*)

PROCEDURE hPoint (p: Coord; c: Colour) ;
BEGIN
   p := scaleCoord(p, 0.5) ;
   p := addCoord(p, initCoord(0.5, 0.5)) ;
   glyphCircle(c2p(p), TRUE, zero(), putReal(0.05), c)
END hPoint ;


(*
   hCircle - debugging procedure to display a circle on a half scale axis.
*)

PROCEDURE hCircle (p: Coord; r: REAL; c: Colour) ;
BEGIN
   p := scaleCoord(p, 0.5) ;
   p := addCoord(p, initCoord(0.5, 0.5)) ;
   glyphCircle(c2p(p), TRUE, zero(), putReal(r), c)
END hCircle ;


(*
   hVec - display a normalised vector on a half scale axis
*)

PROCEDURE hVec (p: Coord; c: Colour) ;
BEGIN
   p := normaliseCoord(p) ;
   hLine(initCoord(0.0, 0.0), initCoord(p.x, 0.0), c) ;
   hLine(initCoord(0.0, 0.0), initCoord(0.0, p.y), c)
END hVec ;


(*
   hFlush - flip the debugging buffer.
*)

PROCEDURE hFlush ;
BEGIN
   drawBoarder(black()) ;
   flipBuffer ;
   collectAll
END hFlush ;


(*
   checkPointCollision - 
*)

PROCEDURE checkPointCollision (VAR timeOfPrevCollision: REAL; t, length, cx, rvx, rax: REAL;
                               c, cvel, caccel: Coord; VAR collisionPoint: Coord;
                               id1, id2: CARDINAL) : BOOLEAN ;
BEGIN
   IF checkIfPointHits(timeOfPrevCollision, t, length, cx, rvx, rax)
   THEN
      (* a hit, find where *)
      collisionPoint := newPositionCoord(c, cvel, caccel, t) ;
      
      (* return TRUE providing that we do not already know about it *)
      IF isDuplicate(currentTime, t, id1, id2, edge, edge)
      THEN
         RETURN FALSE
      ELSE
         timeOfPrevCollision := t ;
         RETURN TRUE
      END
   END ;
   RETURN FALSE
END checkPointCollision ;


(*
   earlierPointLineCollision - returns TRUE if we can find a collision between a point, c,
                               travelling at cvel with acceleration, caccel and a line
                               p1, p2, travelling at velocity, lvel, and acceleration laccel.
                               If a collision is found then the collisionPoint is also
                               calculated.
*)

PROCEDURE earlierPointLineCollision (VAR timeOfCollision: REAL;
                                     c, cvel, caccel,
                                     p1, p2, lvel, laccel: Coord;
                                     VAR collisionPoint: Coord;
                                     id1, id2: CARDINAL) : BOOLEAN ;
VAR
   p3, c0, c1,
   rvel, raccel: Coord ;
   x,
   t0, t1,
   hypot, theta: REAL ;
BEGIN
   (* we pretend that the line is stationary, by computing the relative velocity and acceleration *)
   rvel := subCoord(cvel, lvel) ;
   raccel := subCoord(caccel, laccel) ;
   IF Debugging
   THEN
      printf("relative vel  (%g, %g),  accel (%g, %g)\n", rvel.x, rvel.y, raccel.x, raccel.y)
   END ;

   (* now translate p1 onto the origin *)
   p3 := subCoord(p2, p1) ;
   hypot := lengthCoord(p3) ;
   (* we have a line from 0, 0 to hypot, 0 *)

   (* now find theta the angle of the vector, p3 *)
   theta := asin(p3.y / hypot) ;
   IF Debugging
   THEN
      printf("rotating line by %g degrees  (length of line is %g)\n", 180.0*theta/3.14159, hypot)
   END ;

   c0 := subCoord(c, p1) ;             (* translate c by the same as the line *)
   c1 := rotateCoord(c0, -theta) ;     (* and rotate point, c0. *)
   rvel := rotateCoord(rvel, -theta) ; (* and relative velocity *)
   raccel := rotateCoord(raccel, -theta) ; (* and relative acceleration *)

   raccel := checkZeroCoord(raccel) ;
   rvel := checkZeroCoord(rvel) ;
   IF Debugging
   THEN
      printf("after rotation we have relative vel  (%g, %g),  accel (%g, %g)\n", rvel.x, rvel.y, raccel.x, raccel.y)
   END ;

   IF FALSE
   THEN
      hLine(initCoord(0.0, 0.0), initCoord(hypot, 0.0), purple()) ;
      hPoint(c1, purple()) ;
      hFlush()
   END ;

   (*
      now solve for, t, when y=0, use S = UT + 1/2 AT^2
      at y = 0 we have:

      0 = rvel.y * t + 1/2 * raccel.y * t^2

      Using quadratic:

      at^2 + bt + c = 0
   *)
   IF findQuadratic(raccel.y / 2.0, rvel.y, c1.y, t0, t1)
   THEN
      IF (t0<0.0) AND (t1<0.0)
      THEN
         (* get out of here quick - no point of predicting collisions in the past :-) *)
         RETURN FALSE
      ELSE
         IF t0=t1
         THEN
            (* only one root *)
            IF checkPointCollision(timeOfCollision, t0, hypot, c1.x, rvel.x, raccel.x,
                                   c, cvel, caccel, collisionPoint, id1, id2)
            THEN
               RETURN TRUE
            END
         ELSE
            (* two roots, ignore a negative root *)
            IF t0<0.0
            THEN
               (* test only positive root, t1 *)
               IF checkPointCollision(timeOfCollision, t1, hypot, c1.x, rvel.x, raccel.x,
                                      c, cvel, caccel, collisionPoint, id1, id2)
               THEN
                  RETURN TRUE
               END
            ELSIF t1<0.0
            THEN
               (* test only positive root, t0 *)
               IF checkPointCollision(timeOfCollision, t0, hypot, c1.x, rvel.x, raccel.x,
                                      c, cvel, caccel, collisionPoint, id1, id2)
               THEN
                  RETURN TRUE
               END
            ELSE
               (* ok two positive roots, test smallest (earlist first and then bail out if it hits) *)
               IF t0<t1
               THEN
                  IF checkPointCollision(timeOfCollision, t0, hypot, c1.x, rvel.x, raccel.x,
                                         c, cvel, caccel, collisionPoint, id1, id2)
                  THEN
                     RETURN TRUE
                  END ;
                  IF checkPointCollision(timeOfCollision, t1, hypot, c1.x, rvel.x, raccel.x,
                                         c, cvel, caccel, collisionPoint, id1, id2)
                  THEN
                     RETURN TRUE
                  END
               ELSE
                  IF checkPointCollision(timeOfCollision, t1, hypot, c1.x, rvel.x, raccel.x,
                                         c, cvel, caccel, collisionPoint, id1, id2)
                  THEN
                     RETURN TRUE
                  END ;
                  IF checkPointCollision(timeOfCollision, t0, hypot, c1.x, rvel.x, raccel.x,
                                         c, cvel, caccel, collisionPoint, id1, id2)
                  THEN
                     RETURN TRUE
                  END
               END
            END
         END
      END
   END ;

   RETURN FALSE
END earlierPointLineCollision ;


(*
   sortLine - orders points, p1 and, p2, according to their x value.
*)

PROCEDURE sortLine (VAR p1, p2: Coord) ;
VAR
   t: Coord ;
BEGIN
   IF p1.x>p2.x
   THEN
      t := p1 ;
      p1 := p2 ;
      p2 := t
   ELSIF (p1.x=p2.x) AND (p1.y>p2.y)
   THEN
      t := p1 ;
      p1 := p2 ;
      p2 := t
   END
END sortLine ;


(*
   earlierCircleEdgeCollision - return TRUE if an earlier time, t, is found than tc for when circle
                                hits a line.  The circle is defined by a, center, radius and has
                                acceleration, accelCircle, and velocity, velCircle.
                                The line is between p1 and p2 and has velocity, velLine, and
                                acceleration, accelLine.
*)

PROCEDURE findEarlierCircleEdgeCollision (VAR timeOfCollision: REAL;
                                          cid, pid: CARDINAL;
                                          line: CARDINAL;
                                          VAR edesc: eventDesc;
                                          center: Coord; radius: REAL;
                                          velCircle, accelCircle: Coord;
                                          p1, p2, velLine, accelLine: Coord;
                                          createDesc: descP) ;
VAR
   v1, n1, d1, d2,
   p3, p4, p5, p6: Coord ;
   collisonPoint : Coord ;
BEGIN
   sortLine(p1, p2) ;
   (* create the vector p1 -> p2 *)
   v1 := subCoord(p2, p1) ;

   (* compute the normal for v1, normalise it, and multiply by radius *)
   perpendiculars(v1, d1, d2) ;
   d1 := scaleCoord(normaliseCoord(d1), radius) ;
   d2 := scaleCoord(normaliseCoord(d2), radius) ;

   (* now add d1, d2 to p1 to obtain p3, p4 *)
   p3 := addCoord(p1, d1) ;
   p4 := addCoord(p1, d2) ;

   (* now add d1 and d2 to p2 to get p5 and p6 *)
   p5 := addCoord(p2, d1) ;
   p6 := addCoord(p2, d2) ;
   
   (* we now have two lines p3 -> p5   and  p4 -> p6 *)

   (* ok, now we only need to find when line between p3, p5 hits the centre of the circle *)
   IF earlierPointLineCollision(timeOfCollision, center, velCircle, accelCircle,
                                p3, p5, velLine, accelLine, collisonPoint, cid, pid)
   THEN
      (* circle hits line, p1, in tc seconds *)
      IF Debugging
      THEN
         printf("circle hits line (%g, %g) (%g, %g) in %g\n", p1.x, p1.y, p2.x, p2.y, timeOfCollision)
      END ;
      edesc := createDesc(edesc, cid, pid, line, 0, collisonPoint) ;
      IF Debugging AND drawCollisionFrame
      THEN
         drawFrame(NIL) ;
         debugCircle(center, radius, purple()) ;
         debugLine(p3, p5) ;
         debugCircle(collisonPoint, 0.02, purple()) ;
         flipBuffer ;
         collectAll
      END
   END ;

   (* ok, now we only need to find when line between p4, p6 hits the centre of the circle *)
   IF earlierPointLineCollision(timeOfCollision, center, velCircle, accelCircle,
                                p4, p6, velLine, accelLine, collisonPoint, cid, pid)
   THEN
      (* circle hits line, p1, in tc seconds *)
      IF Debugging
      THEN
         printf("circle hits line (%g, %g) (%g, %g) in %g\n", p1.x, p1.y, p2.x, p2.y, timeOfCollision)
      END ;
      edesc := createDesc(edesc, cid, pid, line, 0, collisonPoint) ;
      IF Debugging AND drawCollisionFrame
      THEN
         drawFrame(NIL) ;
         debugCircle(center, radius, purple()) ;
         debugLine(p4, p6) ;
         debugCircle(collisonPoint, 0.02, purple()) ;
         flipBuffer ;
         collectAll
      END
   END
   
END findEarlierCircleEdgeCollision ;


(*
   getPolygonLine - assigns, p1, p2, with the, line, coordinates of polygon, pPtr.
*)

PROCEDURE getPolygonLine (line: CARDINAL; pPtr: Object; VAR p1, p2: Coord) ;
BEGIN
   WITH pPtr^ DO
      IF line=pPtr^.p.nPoints
      THEN
         p1 := pPtr^.p.points[line-1] ;
         p2 := pPtr^.p.points[0]
      ELSE
         p1 := pPtr^.p.points[line-1] ;
         p2 := pPtr^.p.points[line]
      END
   END
END getPolygonLine ;

   
(*
   findCollisionCircleLine - find the time (if any) between line number, l, in polygon, pPtr,
                             and the circle, cPtr.
*)

PROCEDURE findCollisionCircleLine (cPtr, pPtr: Object;
                                   l: CARDINAL; center: Coord; radius: REAL;
                                   VAR edesc: eventDesc; VAR timeOfCollision: REAL; createDesc: descP) ;
VAR
   velCircle, accelCircle,
   velLine, accelLine,
   p1, p2                       : Coord ;
   cx, cy, r, cvx, cvy, cax, cay,
   pvx, pvy, pax, pay, t        : REAL ;
   cid, pid                     : CARDINAL ;
BEGIN
   cid := cPtr^.id ;
   pid := pPtr^.id ;

   getPolygonLine(l, pPtr, p1, p2) ;

   (* we perform 4 checks.

         (i) and (ii)     pretend the circle has radius 0.0 and see if it hits two new circles at
                          point, p1, and, p2 with the original radius.
         (iii) and (iv)   now draw two lines between the edge of the two new circles and see if the
                          center of the original circle intersects with either line.

         the smallest positive time is the time of the next collision.
    *)

   getObjectValues(cPtr, cvx, cvy, cax, cay) ;
   getObjectValues(pPtr, pvx, pvy, pax, pay) ;

   (* i *)
   IF earlierCircleCollision(t, timeOfCollision,
                             p1.x, center.x, pvx, cvx, pax, cax,
                             p1.y, center.y, pvy, cvy, pay, cay, radius, 0.0)
   THEN
      (* circle hits corner of the line, p1, in tc seconds *)
      IF Debugging
      THEN
         printf("circle hits corner at %g, %g  in %g\n", p1.x, p1.y, t)
      END ;
      timeOfCollision := t ;
      edesc := createDesc(edesc, cid, pid, 0, l, p1) ;  (* point no, l *)
      IF Debugging AND drawCollisionFrame
      THEN
         drawFrame(NIL) ;
         debugCircle(center, r, yellow()) ;
         debugCircle(p1, 0.03, yellow()) ;
         flipBuffer ;
         collectAll
      END
   END ;

   (* ii *)
   IF earlierCircleCollision(t, timeOfCollision,
                             p2.x, center.x, pvx, cvx, pax, cax,
                             p2.y, center.y, pvy, cvy, pay, cay, radius, 0.0)
   THEN
      (* circle hits corner of the line, p2, in tc seconds *)
      IF Debugging
      THEN
         printf("circle hits corner at %g, %g  in %g\n", p2.x, p2.y, t)
      END ;
      timeOfCollision := t ;
      edesc := createDesc(edesc, cid, pid, 0, l+1, p2) ;  (* point no, l+1 *)
      IF Debugging AND drawCollisionFrame
      THEN
         drawFrame(NIL) ;
         debugCircle(cPtr^.c.pos, r, yellow()) ;
         debugCircle(p2, 0.03, yellow()) ;
         flipBuffer ;
         collectAll
      END
   END ;

   velCircle   := initCoord(cvx, cvy) ;
   accelCircle := initCoord(cax, cay) ;
   velLine     := initCoord(pvx, pvy) ;
   accelLine   := initCoord(pax, pay) ;

   (* iii and iv *)
   findEarlierCircleEdgeCollision(timeOfCollision,
                                  cid, pid,
                                  l, edesc,
                                  center, radius, velCircle, accelCircle,
                                  p1, p2, velLine, accelLine, createDesc)
                             
END findCollisionCircleLine ;


(*
   findCollisionCirclePolygon - find the smallest positive time (if any) between the polygon and circle.
                                If a collision if found then, tc, is assigned to the time and cid, pid
                                are set to the circle id and polygon id respectively.
*)

PROCEDURE findCollisionCirclePolygon (cPtr, pPtr: Object; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   i: CARDINAL ;
BEGIN
   Assert(cPtr^.object=circleOb) ;
   WITH pPtr^ DO
      i := 1 ;
      WHILE i<=p.nPoints DO
         findCollisionCircleLine(cPtr, pPtr, i, cPtr^.c.pos, cPtr^.c.r, edesc, tc, makeCirclesPolygonDesc) ;
         INC(i)
      END
   END
END findCollisionCirclePolygon ;


(*
   makePolygonPolygonDesc - return a new eventDesc indicating that we have a polygon/polygon collision
                            event.
*)

PROCEDURE makePolygonPolygon (edesc: eventDesc; id1, id2: CARDINAL;
                              lineNo, pointNo: CARDINAL; collisionPoint: Coord) : eventDesc ;
BEGIN
   IF edesc=NIL
   THEN
      edesc := newDesc()
   END ;
   edesc^.etype := polygonPolygonEvent ;
   edesc^.pp.cPoint := collisionPoint ;
   edesc^.pp.pid1 := id1 ;
   edesc^.pp.pid2 := id2 ;
   IF lineNo=0
   THEN
      edesc^.pp.kind := corner
   ELSE
      edesc^.pp.kind := edge
   END ;
   edesc^.pp.lineCorner := lineNo ;
   edesc^.pp.pointNo := pointNo ;
   RETURN edesc
END makePolygonPolygon ;


(*
   findCollisionLineLine - 
*)

PROCEDURE findCollisionLineLine (iPtr, jPtr: Object; i, j: CARDINAL; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   i0, i1,
   j0, j1: Coord ;
BEGIN
   getPolygonLine(i, iPtr, i0, i1) ;
   getPolygonLine(j, jPtr, j0, j1) ;

   (* test i0 crossing line j *)
   findCollisionCircleLine(iPtr, jPtr, j, i0, 0.0, edesc, tc, makePolygonPolygon) ;

   (* test i1 crossing line j *)
   findCollisionCircleLine(iPtr, jPtr, j, i1, 0.0, edesc, tc, makePolygonPolygon) ;
   
   (* test j0 crossing line i *)
   findCollisionCircleLine(jPtr, iPtr, i, j0, 0.0, edesc, tc, makePolygonPolygon) ;

   (* test j1 crossing line i *)
   findCollisionCircleLine(jPtr, iPtr, i, j1, 0.0, edesc, tc, makePolygonPolygon)

END findCollisionLineLine ;


(*
   getPolygonRPoint - 
*)

PROCEDURE getPolygonRPoint (i: CARDINAL; o: Object; VAR cofg, u, a: Coord; VAR w: REAL; VAR pol: Polar) ;
BEGIN
   WITH o^ DO
      w := angularVelocity ;
      u := initCoord(vx, vy) ;
      a := initCoord(ax, ay) ;

      CASE object OF

      polygonOb :  cofg := calculateCofG(p.nPoints, p.points) ;
                   pol := coordToPolar(subCoord(p.points[i-1], cofg)) |
      circleOb  :  HALT |
      pivotOb   :  HALT |
      rpolygonOb:  pol := r.points[i-1] ;
                   cofg := r.cOfG

      ELSE
         HALT
      END
   END
END getPolygonRPoint ;


(*
   Abs - return the absolute value of, r.
*)

PROCEDURE Abs (r: REAL) : REAL ;
BEGIN
   IF r<0.0
   THEN
      RETURN -r
   ELSE
      RETURN r
   END
END Abs ;


(*
   findAllTimesOfCollisionRLineRPoint - 
                                                       4         4   4
                                             - ((16 j k  - 16 d e ) t

                                                       3               3         3               3   3
                                              + (64 j k  l - 32 %pi j k  - 64 d e  f + 32 %pi d e ) t

                                                       2  2             2            2          2                2  2
                                              + (96 j k  l  - 96 %pi j k  l + (24 %pi  - 32) j k  + 32 i - 96 d e  f

                                                          2                 2     2          2
                                              + 96 %pi d e  f + (32 - 24 %pi ) d e  - 32 c) t

                                                         3               2          2                              3
                                              + (64 j k l  - 96 %pi j k l  + (48 %pi  - 64) j k l + (32 %pi - 8 %pi ) j k

                                                               3               2               2
                                              + 64 h - 64 d e f  + 96 %pi d e f  + (64 - 48 %pi ) d e f

                                                      3                                 4             3
                                              + (8 %pi  - 32 %pi) d e - 64 b) t + 16 j l  - 32 %pi j l

                                                       2          2                  3            4        2
                                              + (24 %pi  - 32) j l  + (32 %pi - 8 %pi ) j l + (%pi  - 8 %pi  + 64) j + 64 g

                                                      4             3               2     2         3
                                              - 16 d f  + 32 %pi d f  + (32 - 24 %pi ) d f  + (8 %pi  - 32 %pi) d f

                                                      4        2
                                              + (- %pi  + 8 %pi  - 64) d - 64 a)/64 = 0         
*)

PROCEDURE findAllTimesOfCollisionRLineRPoint (a, b, c, d, e, f,
                                              g, h, i, j, k, l: REAL;
                                              VAR t: ARRAY OF REAL) : CARDINAL ;
VAR
   A, B, C, D, E: REAL ;
BEGIN
   A := 16.0 * j * quad(k) - 16.0 * d * quad(e);
   B := 64.0 * j * cub(k) * l - 32.0 * pi * j * cub(k)  - 64.0 * d * cub(e) * f + 32.0 * pi * d * cub(e) ;
   C := 96.0 * j * sqr(k) * sqr(l) - 96.0 * pi * j * sqr(k) * l + (24.0 * sqr(pi) - 32.0) * j * sqr(k)  + 32.0 * i - 96.0 * d * sqr(e) * sqr(f)
        + 96.0 * pi * d * sqr(e) * f + (32.0 - 24.0 * sqr(pi) ) * d * sqr(e)  - 32.0 * c ;
   D := (64.0 * j * k * cub(l)  - 96.0 * pi * j * k * sqr(l)  + (48.0 * sqr(pi)  - 64.0) * j * k * l + (32.0 * pi - 8.0 * sqr(pi) ) * j * k
        + 64.0 * h - 64.0 * d * e * cub(f)  + 96.0 * pi * d * e * sqr(f)  + (64.0 - 48.0 * sqr(pi) ) * d * e * f
        + (8.0 * cub(pi) - 32.0 * pi) * d * e - 64.0 * b) ;
   E := 16.0 * j * quad(l)  - 32.0 * pi * j * cub(l)
        + (24.0 * sqr(pi)  - 32.0) * j * sqr(l)  + (32.0 * pi - 8.0 * cub(pi) ) * j * l + (cub(pi)  - 8.0 * sqr(pi) + 64.0) * j + 64.0 * g
        - 16.0 * d * quad(f)  + 32.0 * pi * d * cub(f) + (32.0 - 24.0 * sqr(pi) ) * d * sqr(f)  + (8.0 * cub(pi)  - 32.0 * pi) * d * f
        + (- quad(pi)  + 8.0 * sqr(pi)  - 64.0) * d - 64.0 * a ;
   RETURN findAllRootsQuartic(A, B, C, D, E, t)
END findAllTimesOfCollisionRLineRPoint ;


(*
   findEarliestCollisionRLineRPoint - find the earliest time when rotating point, j, collides with rotating line, i.
*)

PROCEDURE findEarliestCollisionRLineRPoint (iPtr, jPtr: Object; i, j: CARDINAL;
                                            VAR edesc: eventDesc; VAR tc: REAL;
                                            si, ui, ai, ri, wi, oi, sj, uj, aj, rj, wj, oj: REAL;
                                            p1, p2: Coord) ;
VAR
   t   : ARRAY [0..3] OF REAL ;    (* possible times of collision *)
   k, n: CARDINAL ;
   l   : REAL ;
BEGIN
(*
   (* when do the Y values of line, i, equal Y values for point, j? *)
   l := Abs(p2.x - p1.x) ;
   AssertR(p1.y, p2.y) ;
   
   n := findAllTimesOfCollisionRLineRPoint(si, ui, ai, ri, wi, oi,
                                           sj, uj, aj, rj, wj, oj,
                                           t) ;
   k := 0 ;
   getPolygonRPoint(j, jPtr, cofg, u, 
   WHILE k<n DO
      (* at time t[k], do the X value of point, j, intersect with line, i *)
      IF t[k]>=0.0
      THEN
         IF 
         x := newPositionRotationCosScalar(getCofG(jPtr), 
      END ;
      INC(k)
   END
*)
END findEarliestCollisionRLineRPoint ;


(*
   findCollisionLineRPoint - 
*)

PROCEDURE findCollisionLineRPoint (iPtr, rPtr: Object; i, j: CARDINAL; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   jp, pol1, pol2: Polar ;
   o, offset,
   jw, iw        : REAL ;
   jpos,
   p1, p2,
   iu, ia,
   ju, ja,
   rcofg         : Coord ;
BEGIN
(*
   getPolygonRLine(i, iPtr, p1, p2, iu, ia, iw, pol1, pol2) ;
   rotateRPointsOntoYaxis(pol1, po2, p1, p2, o, offset) ;

   getPolygonRPoint(j, rPtr, rcofg, ju, ja, jw, jp, jpos) ;
*)
   (* now we ask when/if point jp crosses line p1, p2 *)
   findEarliestCollisionRLineRPoint(iPtr, rPtr, i, j, edesc, tc,
                                    p1.y, iu.y, ia.y, offset, iw, o,
                                    jpos.y, ju.y, ja.y, jp.r, jw, jp.w,
                                    p1, p2)
   
END findCollisionLineRPoint ;


(*
   findCollisionLineRLine - 
*)

PROCEDURE findCollisionLineRLine (iPtr, rPtr: Object; i, j: CARDINAL; VAR edesc: eventDesc; VAR tc: REAL) ;
BEGIN
   (* test point rj-1 crossing line i *)
   findCollisionLineRPoint(iPtr, rPtr, i, j-1, edesc, tc) ;

   (* test point rj crossing line i *)
   findCollisionLineRPoint(iPtr, rPtr, i, j, edesc, tc) ;

   (* test point ii-1 crossing line j *)
   findCollisionLineRPoint(rPtr, iPtr, j, i-1, edesc, tc) ;

   (* test point ii crossing line j *)
   findCollisionLineRPoint(rPtr, iPtr, j, i, edesc, tc)
   
END findCollisionLineRLine ;




(*
   findCollisionPolygonPolygon - find the smallest positive time (if any) between the polygons, iPtr
                                 and jPtr colliding.
                                 If a collision if found then, tc, is assigned to the time and the
                                 event descriptor is filled in.
*)

PROCEDURE findCollisionPolygonPolygon (iPtr, jPtr: Object; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   i, j: CARDINAL ;
BEGIN
   Assert(iPtr#jPtr) ;
   i := 1 ;
   WHILE i<=iPtr^.p.nPoints DO
      j := 1 ;
      WHILE j<=jPtr^.p.nPoints DO
         findCollisionLineLine(iPtr, jPtr, i, j, edesc, tc) ;
         INC(j)
      END ;
      INC(i)
   END
END findCollisionPolygonPolygon ;


(*
   findCollisionPolygonRPolygon - find the smallest positive time (if any) between the polygons, iPtr
                                  and rPtr colliding.  rPtr is a rotating polygon.
                                  If a collision if found then, tc, is assigned to the time and the
                                  event descriptor is filled in.
*)

PROCEDURE findCollisionPolygonRPolygon (iPtr, rPtr: Object; VAR edesc: eventDesc; VAR tc: REAL) ;
VAR
   i, j: CARDINAL ;
BEGIN
   Assert(iPtr#rPtr) ;
   i := 1 ;
   WHILE i<=iPtr^.p.nPoints DO
      j := 1 ;
      WHILE j<=rPtr^.r.nPoints DO
         findCollisionLineRLine(iPtr, rPtr, i, j, edesc, tc) ;
         INC(j)
      END ;
      INC(i)
   END
END findCollisionPolygonRPolygon ;


(*
   findCollision - 
*)

PROCEDURE findCollision (iptr, jptr: Object; VAR edesc: eventDesc; VAR tc: REAL) ;
BEGIN
   IF NOT (iptr^.fixed AND jptr^.fixed)
   THEN
      IF (iptr^.object=circleOb) AND (jptr^.object=circleOb)
      THEN
         findCollisionCircles(iptr, jptr, edesc, tc)
      ELSIF (iptr^.object=circleOb) AND (jptr^.object=polygonOb)
      THEN
         findCollisionCirclePolygon(iptr, jptr, edesc, tc)
      ELSIF (iptr^.object=polygonOb) AND (jptr^.object=circleOb)
      THEN
         findCollisionCirclePolygon(jptr, iptr, edesc, tc)
      ELSIF (iptr^.object=polygonOb) AND (jptr^.object=polygonOb)
      THEN
         findCollisionPolygonPolygon(jptr, iptr, edesc, tc)
      ELSIF (iptr^.object=polygonOb) AND (jptr^.object=rpolygonOb)
      THEN
         findCollisionPolygonRPolygon(iptr, jptr, edesc, tc)
      ELSIF (iptr^.object=rpolygonOb) AND (jptr^.object=polygonOb)
      THEN
         findCollisionPolygonRPolygon(jptr, iptr, edesc, tc)
      END
   END
END findCollision ;


(*
   debugFrame - debug frame at time, e.
*)

PROCEDURE debugFrame (e: eventQueue) ;
BEGIN
   drawBackground(yellow()) ;
   drawFrame(e)
END debugFrame ;


(*
   addDebugging - add a debugging event at time, t.
*)

PROCEDURE addDebugging (t: REAL; edesc: eventDesc) ;
VAR
   e: eventQueue ;
BEGIN
   e := newEvent() ;
   WITH e^ DO
      time := t ;
      p := debugFrame ;
      ePtr := edesc ;
      next := NIL
   END ;
   addRelative(e)
END addDebugging ;


(*
   rememberCollision - 
*)

PROCEDURE rememberCollision (tc: REAL; edesc: eventDesc) ;
BEGIN
   WITH edesc^ DO
      CASE etype OF

      circlesEvent       :  occurred(currentTime+tc, cc.cid1, cc.cid2) |
      circlePolygonEvent :  occurred(currentTime+tc, cp.pid, cp.cid) |
      polygonPolygonEvent:  occurred(currentTime+tc, pp.pid1, pp.pid2)

      END
   END ;
   purge
END rememberCollision ;


(*
   subEvent - remove event, e, from the relative time ordered event queue.
*)

PROCEDURE subEvent (e: eventQueue) ;
VAR
   before, f: eventQueue ;
BEGIN
   f := eventQ ;
   before := NIL ;
   WHILE (f#e) AND (f#NIL) DO
      before := f ;
      f := f^.next
   END ;
   IF f#NIL
   THEN
      Assert(f=e) ;
      IF before=NIL
      THEN
         Assert(eventQ=f) ;
         Assert(eventQ=e) ;
         eventQ := eventQ^.next ;
         IF eventQ#NIL
         THEN
            eventQ^.time := eventQ^.time + e^.time
         END ;
      ELSE
         before^.next := e^.next ;
         IF e^.next#NIL
         THEN
            e^.next^.time := e^.next^.time + e^.time
         END
      END ;
      disposeEvent(e)
   END
END subEvent ;


(*
   removeCollisionEvent - 
*)

PROCEDURE removeCollisionEvent ;
VAR
   e: eventQueue ;
BEGIN
   e := eventQ ;
   WHILE e#NIL DO
      IF e^.p=VAL(eventProc, doCollision)
      THEN
         subEvent(e) ;
         RETURN
      ELSE
         e := e^.next ;
      END
   END
END removeCollisionEvent ;



(*
   addNextCollisionEvent - 
*)

PROCEDURE addNextCollisionEvent (prevCollisionTime: REAL) ;
VAR
   tc        : REAL ;
   ic, jc,
   i, j, n   : CARDINAL ;
   iptr, jptr: Object ;
   edesc     : eventDesc ;
BEGIN
   n := HighIndice(objects) ;
   i := 1 ;
   removeCollisionEvent ;
   edesc := NIL ;
   tc := -1.0 ;
   WHILE i<=n DO
      iptr := GetIndice(objects, i) ;
      j := 1+i ;
      WHILE j<=n DO
         jptr := GetIndice(objects, j) ;
         IF iptr#jptr
         THEN
            findCollision(iptr, jptr, edesc, tc)
         END ;
         INC(j)
      END ;
      INC(i)
   END ;
   IF edesc#NIL
   THEN
      addCollisionEvent(tc, doCollision, edesc) ;
      rememberCollision(tc, edesc)
   ELSE
      printf("no more collisions found\n")
   END
END addNextCollisionEvent ;


(*
   skipFor - skip displaying any frames for, t, simulated seconds.
*)

PROCEDURE skipFor (t: REAL) ;
VAR
   s, dt: REAL ;
BEGIN
   drawCollisionFrame := FALSE ;
   s := 0.0 ;
   (* killQueue ; *)
   checkObjects ;
   addNextCollisionEvent(s) ;
   printQueue ;
   WHILE s<t DO
      dt := doNextEvent() ;
      s := s + dt
   END ;
   updatePhysics(currentTime-lastCollisionTime) ;
   printQueue ;
   lastCollisionTime := currentTime
END skipFor ;


(*
   simulateFor - render for, t, seconds.
*)

PROCEDURE simulateFor (t: REAL) ;
VAR
   s, dt: REAL ;
BEGIN
   drawCollisionFrame := TRUE ;
   s := 0.0 ;
   (* killQueue ; *)
   checkObjects ;
   addEvent(0.0, drawFrameEvent) ;
   addNextCollisionEvent(s) ;
   printQueue ;
   WHILE s<t DO
      dt := doNextEvent() ;
      s := s + dt
   END ;
   updatePhysics(currentTime-lastCollisionTime) ;
   printQueue ;
   lastCollisionTime := currentTime
END simulateFor ;


(*
   disposeEvent - returns the event to the free queue.
*)

PROCEDURE disposeEvent (e: eventQueue) ;
BEGIN
   disposeDesc(e^.ePtr) ;
   e^.next := freeEvents ;
   freeEvents := e
END disposeEvent ;


(*
   disposeDesc - returns the event desc to the free queue.
*)

PROCEDURE disposeDesc (VAR d: eventDesc) ;
BEGIN
   IF d#NIL
   THEN
      d^.next := freeDesc ;
      freeDesc := d ;
      d := NIL
   END
END disposeDesc ;


(*
   newDesc - returns a new eventDesc.
*)

PROCEDURE newDesc () : eventDesc ;
VAR
   e: eventDesc ;
BEGIN
   IF freeDesc=NIL
   THEN
      NEW(e)
   ELSE
      e := freeDesc ;
      freeDesc := freeDesc^.next
   END ;
   RETURN e
END newDesc ;


(*
   newEvent - returns a new eventQueue.
*)

PROCEDURE newEvent () : eventQueue ;
VAR
   e: eventQueue ;
BEGIN
   IF freeEvents=NIL
   THEN
      NEW(e)
   ELSE
      e := freeEvents ;
      freeEvents := freeEvents^.next
   END ;
   e^.ePtr := NIL ;
   RETURN e
END newEvent ;


(*
   makeCirclesDesc - return a eventDesc which describes two circles colliding.
*)

PROCEDURE makeCirclesDesc (VAR edesc: eventDesc; cid1, cid2: CARDINAL) : eventDesc ;
BEGIN
   IF edesc=NIL
   THEN
      edesc := newDesc()
   END ;
   edesc^.etype := circlesEvent ;
   edesc^.cc.cPoint.x := 0.0 ;
   edesc^.cc.cPoint.y := 0.0 ;
   edesc^.cc.cid1 := cid1 ;
   edesc^.cc.cid2 := cid2 ;
   RETURN edesc
END makeCirclesDesc ;


(*
   addRelative - adds event, e, into the relative event queue.
*)

PROCEDURE addRelative (e: eventQueue) ;
VAR
   before, after: eventQueue ;
BEGIN
   IF eventQ=NIL
   THEN
      eventQ := e
   ELSIF e^.time<eventQ^.time
   THEN
      eventQ^.time := eventQ^.time - e^.time ;
      e^.next := eventQ ;
      eventQ := e
   ELSE
      (* printQueue ; *)
      before := eventQ ;
      after := eventQ^.next ;
      WHILE (after#NIL) AND (after^.time<e^.time) DO
         e^.time := e^.time - before^.time ;
         before := after ;
         after := after^.next
      END ;
      IF after#NIL
      THEN
         after^.time := after^.time-e^.time
      END ;
      e^.time := e^.time-before^.time ;
      before^.next := e ;
      e^.next := after ;
      (* printQueue *)
   END
END addRelative ;


(*
   addEvent - adds an event which has no collision associated with it.
              Typically this is a debugging event or display frame event.
*)

PROCEDURE addEvent (t: REAL; dop: eventProc) ;
VAR
   e: eventQueue ;
BEGIN
   e := newEvent() ;
   WITH e^ DO
      time := t ;
      p := dop ;
      ePtr := NIL ;
      next := NIL
   END ;
   addRelative(e)
END addEvent ;


(*
   addCollisionEvent - adds a collision event, the edesc is attached to the,
                       eventQueue, which is placed onto the eventQ.
*)

PROCEDURE addCollisionEvent (t: REAL; dop: eventProc; edesc: eventDesc) ;
VAR
   e: eventQueue ;
BEGIN
   IF Debugging
   THEN
      printf("collision will occur in %g simulated seconds\n", t)
   END ;
   e := newEvent() ;
   WITH e^ DO
      time := t ;
      p := dop ;
      ePtr := edesc ;
      next := NIL
   END ;
   addRelative(e)
END addCollisionEvent ;


(*
   killQueue - destroys the event queue and returns events to the free list.
*)

PROCEDURE killQueue ;
VAR
   e: eventQueue ;
BEGIN
   IF eventQ#NIL
   THEN
      e := eventQ ;
      WHILE e^.next#NIL DO
         e := e^.next
      END ;
      e^.next := freeEvents ;
      freeEvents := eventQ ;
      eventQ := NIL
   END
END killQueue ;


(*
   Init - 
*)

PROCEDURE Init ;
BEGIN
   maxId := 0 ;
   objects := InitIndex(1) ;
   framesPerSecond := DefaultFramesPerSecond ;
   replayPerSecond := 0.0 ;
   simulatedGravity := 0.0 ;
   eventQ := NIL ;
   freeEvents := NIL ;
   freeDesc := NIL ;
   currentTime := 0.0 ;
   collisionTime := -1.0 ;
   lastCollisionTime := 0.0 ;
   drawCollisionFrame := TRUE
END Init ;


BEGIN
   Init
END twoDsim.