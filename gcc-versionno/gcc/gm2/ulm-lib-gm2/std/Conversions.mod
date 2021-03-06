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

IMPLEMENTATION MODULE Conversions;      (* LG *)

(* $T- *)

   TYPE 
      Basetype = (oct, dec, hex);

   PROCEDURE ConvertNumber(num, len: CARDINAL; btyp: Basetype; neg: BOOLEAN;
      VAR str: ARRAY OF CHAR);

      (* conversion of a number into a string of characters *)
      (* num must get the absolute value of the number      *)
      (* len is the minimal length of the generated string  *)
      (* neg means: "the number is negative" for btyp = dec *)

      CONST
	 NumberLen = 11;
      VAR 
         digits          : ARRAY [1..NumberLen] OF CHAR;
         base            : CARDINAL;
         cnt, ix, maxlen : CARDINAL;
         dig             : CARDINAL;

   BEGIN 
      FOR ix := 1 TO NumberLen DO 
         digits[ix] := '0'
      END;                              (* initialisation *)
      IF btyp = oct THEN 
         base := 10B;
      ELSIF btyp = dec THEN 
         base := 10;
      ELSIF btyp = hex THEN 
         base := 10H;
      END;
      cnt := 0;
      REPEAT 
         INC(cnt);
         dig := num MOD base;
         num := num DIV base;
         IF dig < 10 THEN 
            dig := dig + ORD('0');
         ELSE 
            dig := dig - 10 + ORD('A');
         END;
         digits[cnt] := CHR(dig);
      UNTIL num = 0;
      (* (* i don't like this *)
      IF btyp = oct THEN 
         cnt := 11;
      ELSIF btyp = hex THEN 
         cnt := 8;
      ELSIF neg THEN 
      *)
      IF neg THEN
         INC(cnt);
         digits[cnt] := '-';
      END;
      maxlen := HIGH(str) + 1;          (* get maximal length *)
      IF len > maxlen THEN 
         len := maxlen 
      END;
      IF cnt > maxlen THEN 
         cnt := maxlen 
      END;
      ix := 0;
      WHILE len > cnt DO 
         str[ix] := ' ';
         INC(ix);
         DEC(len);
      END;
      WHILE cnt > 0 DO 
         str[ix] := digits[cnt];
         INC(ix);
         DEC(cnt);
      END;
      IF ix < maxlen THEN 
         str[ix] := 0C 
      END;
   END ConvertNumber;

   PROCEDURE ConvertOctal(num, len: CARDINAL; VAR str: ARRAY OF CHAR);
   (* conversion of an octal number to a string *)
   BEGIN 
      ConvertNumber(num,len,oct,FALSE,str);
   END ConvertOctal;

   PROCEDURE ConvertHex(num, len: CARDINAL; VAR str: ARRAY OF CHAR);
   (* conversion of a hexadecimal number to a string *)
   BEGIN 
      ConvertNumber(num,len,hex,FALSE,str);
   END ConvertHex;

   PROCEDURE ConvertCardinal(num, len: CARDINAL; VAR str: ARRAY OF CHAR);
   (* conversion of a cardinal decimal number to a string *)
   BEGIN 
      ConvertNumber(num,len,dec,FALSE,str);
   END ConvertCardinal;

   PROCEDURE ConvertInteger(num: INTEGER; len: CARDINAL; VAR str: ARRAY OF 
      CHAR);
   (* conversion of an integer decimal number to a string *)
   BEGIN 
      IF num = MIN(INTEGER) THEN (* ABS(MIN(INTEGER)) = MIN(INTEGER) *)
	 (* assume 2-complement *)
	 ConvertNumber(ORD(MAX(INTEGER))+1,len,dec,num < 0,str);
      ELSE
	 ConvertNumber(ABS(num),len,dec,num < 0,str);
      END;
   END ConvertInteger;

END Conversions. 
(*
 * Local variables:
 *  compile-command: "gm2 -c -g -I../sys:. Conversions.mod"
 * End:
 *)
