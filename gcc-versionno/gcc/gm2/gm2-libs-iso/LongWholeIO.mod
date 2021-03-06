(* Copyright (C) 2013
                 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301 USA *)

IMPLEMENTATION MODULE LongWholeIO ;

FROM ConvTypes IMPORT ScanClass, ScanState ;
FROM TextIO IMPORT WriteChar, ReadChar ;
FROM DynamicStrings IMPORT String, char, KillString, Length ;
FROM StringConvert IMPORT LongIntegerToString, LongCardinalToString ;
FROM WholeConv IMPORT ScanInt, ScanCard ;
FROM StringChan IMPORT writeString ;
FROM IOConsts IMPORT ReadResults ;


(* Input and output of whole numbers in decimal text form
     over specified channels.  The read result is of the
     type IOConsts.ReadResults.
*)

IMPORT IOChan;

(* The text form of a signed whole number is
     ["+" | "-"], decimal digit, {decimal digit}

   The text form of an unsigned whole number is
     decimal digit, {decimal digit}
*)

PROCEDURE ReadInt (cid: IOChan.ChanId; VAR int: LONGINT) ;
  (* Skips leading spaces, and removes any remaining characters
     from cid that form part of a signed whole number.  The
     value of this number is assigned to int.  The read result
     is set to the value allRight, outOfRange, wrongFormat,
     endOfLine, or endOfInput.
  *)
VAR
   chClass  : ScanClass ;
   nextState: ScanState ;
   c        : LONGCARD ;
   ch       : CHAR ;
   negative : BOOLEAN ;
BEGIN
   ReadChar(cid, ch) ;
   negative := FALSE ;
   c := 0 ;
   nextState := ScanInt ;
   REPEAT
      nextState(ch, chClass, nextState) ;
      IF chClass=valid
      THEN
         IF ch='+'
         THEN
            (* ignore *)
         ELSIF ch='-'
         THEN
            negative := NOT negative
         ELSE
            c := c*10+VAL(LONGCARD, ORD(ch)-ORD('0'))
         END ;
         ReadChar(cid, ch)
      ELSIF chClass=padding
      THEN
         ReadChar(cid, ch)
      END
   UNTIL (chClass=invalid) OR (chClass=terminator) ;
   IF chClass=terminator
   THEN
      IF negative
      THEN
         IF c=VAL(LONGCARD, MAX(LONGINT))+1
         THEN
            int := MIN(LONGINT)
         ELSIF c<=VAL(LONGCARD, MAX(LONGINT))
         THEN
            int := -VAL(LONGINT, c)
         ELSE
            (* overflow *)
            IOChan.SetReadResult(cid, outOfRange)
         END
      ELSE
         int := c
      END
   END
END ReadInt ;


PROCEDURE WriteInt (cid: IOChan.ChanId; int: LONGINT;
                    width: CARDINAL) ;
  (* Writes the value of int to cid in text form, in a field of
     the given minimum width. *)
VAR
   s: String ;
BEGIN
   s := LongIntegerToString(int, width, ' ', TRUE, 10, FALSE) ;
   writeString(cid, s) ;
   s := KillString(s)
END WriteInt ;


PROCEDURE ReadCard (cid: IOChan.ChanId; VAR card: LONGCARD) ;
  (* Skips leading spaces, and removes any remaining characters
     from cid that form part of an unsigned whole number.  The
     value of this number is assigned to card. The read result
     is set to the value allRight, outOfRange, wrongFormat,
     endOfLine, or endOfInput.
  *)
VAR
   chClass  : ScanClass ;
   nextState: ScanState ;
   ch       : CHAR ;
   c        : LONGCARD ;
BEGIN
   ReadChar(cid, ch) ;
   c := 0 ;
   nextState := ScanCard ;
   REPEAT
      nextState(ch, chClass, nextState) ;
      IF chClass=valid
      THEN
         IF ch='+'
         THEN
            (* ignore *)
         ELSE
            c := c*10+VAL(LONGCARD, ORD(ch)-ORD('0'))
         END ;
         ReadChar(cid, ch)
      ELSIF chClass=padding
      THEN
         ReadChar(cid, ch)
      END
   UNTIL (chClass=invalid) OR (chClass=terminator) ;
   IF chClass=terminator
   THEN
      card := c
   END
END ReadCard ;


PROCEDURE WriteCard (cid: IOChan.ChanId; card: LONGCARD;
                     width: CARDINAL);
  (* Writes the value of card to cid in text form, in a field
     of the given minimum width. *)
VAR
   s: String ;
BEGIN
   s := LongCardinalToString(card, width, ' ', 10, FALSE) ;
   writeString(cid, s) ;
   s := KillString(s)
END WriteCard ;


END LongWholeIO.
