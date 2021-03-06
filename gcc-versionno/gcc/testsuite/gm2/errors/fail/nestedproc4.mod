(* Copyright (C) 2001, 2002, 2003, 2004, 2005, 2006 Free Software Foundation, Inc. *)
(* This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2, or (at your option) any later
version.

GNU Modula-2 is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

You should have received a copy of the GNU General Public License along
with gm2; see the file COPYING.  If not, write to the Free Software
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA. *)
MODULE nestedproc4 ;

FROM StdIO IMPORT Write ;
FROM StrIO IMPORT WriteLn ;

VAR
   s: ARRAY [0..10] OF CHAR ;

PROCEDURE a ;

PROCEDURE b ;
VAR
   p: PROC ;

PROCEDURE c ;
VAR
   s: ARRAY [0..10] OF CHAR ;

PROCEDURE d ;

PROCEDURE e ;
BEGIN
   s[4] := 'a' ;
   b2
END e ;

BEGIN
   e
END d ;

BEGIN
   d
END c ;

BEGIN
   foo(b) ;
   p := b ;
   c
END b ;

PROCEDURE b2 ;
BEGIN
   s[4] := 'g' ;
END b2 ;


BEGIN
   s := 'abcdgfghi' ;
   b ;
   Write(s[4]) ; WriteLn
   (* output should be 'g' *)
END a ;


PROCEDURE foo (p: PROC) ;
BEGIN
END foo ;


BEGIN
   a
END nestedproc4.
