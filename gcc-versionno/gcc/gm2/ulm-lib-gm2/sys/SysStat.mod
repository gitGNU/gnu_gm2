(* Copyright (C) 2004, 2005, 2006, 2007, 2008, 2009, 2010
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
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

This file was originally part of the University of Ulm library
*)


(* Ulm's Modula-2 Library
   Copyright (C) 1984, 1985, 1986, 1987, 1988, 1989, 1990, 1991,
   1992, 1993, 1994, 1995, 1996, 1997, 1998, 1999, 2000, 2001,
   2002, 2003, 2004, 2005
   by University of Ulm, SAI, D-89069 Ulm, Germany
*)

IMPLEMENTATION MODULE SysStat; (* MC68020/Unix V.2 *)

   (* implementation depends on storage allocation of C *)
   (* this version doen't assume any form of alignment, i.e. *)
   (* struct stat is packed. *)
   (* This assumption is true for Nixdorf Targon/31 *)

   FROM SystemTypes IMPORT TIME, OFF;
   FROM UnixString IMPORT Copy, Buffer;
   FROM SYSTEM IMPORT UNIXCALL, ADR, ADDRESS, BYTE;
   FROM Sys IMPORT stat, fstat;
   FROM Errno IMPORT errno;

   (* (* from definition module *)
   TYPE
      StatBuf =
         RECORD
            dev: CARDINAL;
            ino: CARDINAL;
            mode: BITSET;
            nlink: CARDINAL;
            uid: CARDINAL;
            gid: CARDINAL;
            rdev: CARDINAL;
            size: OFF;
            atime: TIME;
	    spare1 : CARDINAL;
            mtime: TIME;
	    spare2 : CARDINAL;
            ctime: TIME;
	    spare3 : CARDINAL;
	    blksize : CARDINAL;
	    blocks : CARDINAL;
	    spare4 : ARRAY[0..1] OF CARDINAL;
         END;
   CONST
      (* bit masks for mode; bits 0..15 used *)
      FileType = { 0..3 };
      (* IF mask * FileType = ... *)
      IfDir = { 1 };      (* directory *)
      IfChr = { 2 };      (* character special *)
      IfBlk = { 1..2 };   (* block special *)
      IfReg = { 0 };      (* regular *)
(* on Nixdorf
      IfMpc = { 2..3 };   (* multiplexed char special *)
      IfMpb = { 1..3 };   (* multiplexed block special *)
    *)
(* on SUN *)
      IfLnk = { 0,2 };  	  (* symbolic link *)
      IfSock = { 0..1 };     (* socket *)
      IfFifo = { 3 };      (* fifo *)
(* end SUN*)
      (* IF ... <= mask THEN *)
      IsUid =  { 4 };     (* set user id on execution *)
      IsGid =  { 5 };     (* set group id on execution *)
      IsVtx =  { 6 };     (* save swapped text even after use *)
      (* permissions on file *)
      OwnerRead = { 7 };  (* read permission, owner *)
      OwnerWrite = { 8 }; (* write permission, owner *)
      OwnerExec = { 9 };  (* execute/search permission, owner *)
      GroupRead = { 10 };
      GroupWrite = { 11 };
      GroupExec = { 12 };
      WorldRead = { 13 };
      WorldWrite = { 14 };
      WorldExec = { 15 };
   *)

   (* following record definition has been taken from SysLib of
      the MOCKA compiler, Karlsruhe
   *)
   CONST
      STFSTYPSZ = 16;
   TYPE
      inoT      = LONGCARD;
      offT      = INTEGER;
      devT      = LONGCARD;
      timeT     = INTEGER;
      modeT     = LONGCARD;
      uidT      = LONGCARD;
      gidT      = uidT;
      nlinkT    = LONGCARD;
      StructStat =
         RECORD
            stDev    : devT;
            stPad1   : ARRAY [0..2] OF LONGCARD; (* reserved for network id *)
            stIno    : inoT;
            stMode   : modeT;
            stNlink  : nlinkT;
            stUid    : uidT;
            stGid    : gidT;
            stRdev   : devT;
            stPad2   : ARRAY [0..1] OF LONGCARD;
            stSize   : offT;
            stPad3   : LONGCARD;		(* future offT expansion *)
            stAtime  : timeT;
            stSpare1 : INTEGER;
            stMtime  : timeT;
            stSpare2 : INTEGER;
            stCtime  : timeT;
            stSpare3 : INTEGER;
            stBlksize: INTEGER;
            stBlocks : INTEGER;
            stFstype : ARRAY [0..STFSTYPSZ-1] OF CHAR;
            stPad4   : ARRAY [0..7] OF LONGCARD;
         END;

   PROCEDURE Expand(VAR from: StructStat; VAR to: StatBuf);
      VAR
	 card: CARDINAL;
   BEGIN
      WITH from DO
         WITH to DO
	    dev := stDev;
	    ino := stIno;
	    card := stMode; card := card * 10000H;
	    mode := BITSET(card);
	    nlink := stNlink;
	    uid := stUid;
	    gid := stGid;
	    rdev := stRdev;
	    size := stSize;
	    atime := stAtime;
	    mtime := stMtime;
	    ctime := stCtime;
	    blksize := stBlksize;
	    blocks := stBlocks;
         END;
      END;
   END Expand;

   PROCEDURE Stat(file: ARRAY OF CHAR; VAR buf: StatBuf) : BOOLEAN;
      VAR sb : StructStat; Buf: Buffer; r0, r1: INTEGER;
   BEGIN
      Copy(Buf, file);
      IF UNIXCALL(stat, r0, r1, ADR(Buf), ADR(sb)) THEN
	 Expand(sb, buf);
         RETURN TRUE
      ELSE
	 errno := r0;
         RETURN FALSE
      END;
   END Stat;

   PROCEDURE Fstat(fd: CARDINAL; VAR buf: StatBuf) : BOOLEAN;
      VAR  sb: StructStat; r0, r1: INTEGER;
   BEGIN
      IF UNIXCALL(fstat, r0, r1, fd, ADR(sb)) THEN
	 Expand(sb, buf);
         RETURN TRUE
      ELSE
	 errno := r0;
         RETURN FALSE
      END;
   END Fstat;

END SysStat.
