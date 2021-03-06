(* Copyright (C) 2009, 2010
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
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA *)

IMPLEMENTATION MODULE LMathLib0 ;

IMPORT cbuiltin, libm ;

PROCEDURE __ATTRIBUTE__ __BUILTIN__ ((__builtin_sqrtl)) sqrt (x: LONGREAL): LONGREAL;
BEGIN
   RETURN cbuiltin.sqrtl (x)
END sqrt ;

PROCEDURE exp (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN libm.expl (x)
END exp ;


(*
                log (b)
   log (b)  =      c
      a         ------
                log (a)
                   c
*)

PROCEDURE ln (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN libm.logl (x) / libm.logl (exp1)
END ln ;

PROCEDURE __ATTRIBUTE__  __BUILTIN__ ((__builtin_sinl)) sin (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN cbuiltin.sinl (x)
END sin ;

PROCEDURE __ATTRIBUTE__  __BUILTIN__ ((__builtin_cosl)) cos (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN cbuiltin.cosl (x)
END cos ;

PROCEDURE tan (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN libm.tanl (x)
END tan ;

PROCEDURE arctan (x: LONGREAL) : LONGREAL ;
BEGIN
   RETURN libm.atanl (x)
END arctan ;

PROCEDURE entier (x: LONGREAL) : INTEGER ;
BEGIN
   RETURN TRUNC (libm.floorl (x))
END entier ;


END LMathLib0.
