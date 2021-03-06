(* Copyright (C) 2015
   Free Software  Foundation, Inc.  *)

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
Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.  *)

IMPLEMENTATION MODULE mcComp ;


FROM FIO IMPORT StdErr ;
FROM libc IMPORT exit ;

FROM decl IMPORT node, isNodeF, isDef, isImp, isModule, isMainModule,
                 setMainModule, setCurrentModule, getSource,
                 lookupDef, lookupModule, lookupImp, setSource, getSymName,
		 foreachDefModuleDo, getMainModule, out ;

FROM symbolKey IMPORT performOperation ;

FROM SYSTEM IMPORT ADDRESS ;
FROM mcReserved IMPORT toktype ;
FROM mcSearch IMPORT findSourceDefFile, findSourceModFile ;
FROM mcLexBuf IMPORT openSource, closeSource, currenttoken, getToken, reInitialize, currentstring ;
FROM mcFileName IMPORT calculateFileName ;
FROM mcPreprocess IMPORT preprocessModule ;

FROM FormatStrings IMPORT Sprintf1 ;

IMPORT mcflex ;
IMPORT mcp1 ;
IMPORT mcp2 ;
IMPORT mcp3 ;


FROM mcError IMPORT writeFormat0, flushErrors, flushWarnings ;
FROM nameKey IMPORT Name, NulName, getKey, keyToCharStar, makekey ;
FROM mcPrintf IMPORT fprintf1 ;
FROM mcQuiet IMPORT qprintf0, qprintf1, qprintf2 ;
FROM DynamicStrings IMPORT String, InitString, KillString, InitStringCharStar, Dup, Mark, string ;

CONST
   Debugging = FALSE ;

TYPE
   parserFunction = PROCEDURE () : BOOLEAN ;
   openFunction = PROCEDURE (node, BOOLEAN) : BOOLEAN ;

VAR
   currentPass: CARDINAL ;


(*
   doCompile - translate file, s, using a 6 pass technique.
*)

PROCEDURE doCompile (s: String) ;
VAR
   n: node ;
BEGIN
   n := initParser (s) ;
   doPass (TRUE, TRUE, 1, p1, 'lexical analysis, modules, root decls and C preprocessor') ;
   doPass (TRUE, TRUE, 2, p2, '[definition modules] type equivalence and enumeration types') ;
   doPass (TRUE, TRUE, 3, p3, '[definition modules] import lists, constants, types, variables and procedures') ;
(*
   IF NOT isDef (n)
   THEN
      qprintf0 ('Parse implementation or program module\n') ;
      doPass (FALSE, FALSE, p4, 4, 'imports and constants') ;
      doPass (FALSE, FALSE, p5, 5, 'import lists, constants, types, variables and procedures') ;
      doPass (FALSE, FALSE, p6, 6, 'build tree of all procedure and module initialisation code') ;
      qprintf0 ('walk tree converting it to C/C++\n')
   END
*)
   out
END doCompile ;


(*
   compile - check, s, is non NIL before calling doCompile.
*)

PROCEDURE compile (s: String) ;
BEGIN
   IF s#NIL
   THEN
      doCompile (s)
   END
END compile ;


(*
   examineCompilationUnit - opens the source file to obtain the module name and kind of module.
*)

PROCEDURE examineCompilationUnit () : node ;
BEGIN
   (* stop if we see eof, ';' or '[' *)
   WHILE (currenttoken#eoftok) AND (currenttoken#semicolontok) AND (currenttoken#lsbratok) DO
      IF currenttoken=definitiontok
      THEN
         getToken ;
         IF currenttoken=moduletok
         THEN
            getToken ;
	    IF currenttoken=fortok
            THEN
               getToken ;
	       IF currenttoken=stringtok
               THEN
                  getToken
               ELSE
                  mcflex.mcError (string (InitString ('expecting language string after FOR keyword'))) ;
                  exit (1)
               END
            END ;
            IF currenttoken=identtok
            THEN
               RETURN lookupDef (makekey (currentstring))
            END
         ELSE
            mcflex.mcError (string (InitString ('MODULE missing after DEFINITION keyword')))
         END
      ELSIF currenttoken=implementationtok
      THEN
         getToken ;
         IF currenttoken=moduletok
         THEN
            getToken ;
            IF currenttoken=identtok
            THEN
               RETURN lookupImp (makekey (currentstring))
            END
         ELSE
            mcflex.mcError (string (InitString ('MODULE missing after IMPLEMENTATION keyword')))
         END
      ELSIF currenttoken=moduletok
      THEN
         getToken ;
         IF currenttoken=identtok
         THEN
            RETURN lookupModule (makekey (currentstring))
         END
      END ;
      getToken
   END ;
   mcflex.mcError (string (InitString ('failed to find module name'))) ;
   exit (1)
END examineCompilationUnit ;


(*
   peepInto - peeps into source, s, and initializes a definition/implementation or
              program module accordingly.
*)

PROCEDURE peepInto (s: String) : node ;
VAR
   n       : node ;
   fileName: String ;
BEGIN
   fileName := preprocessModule (s) ;
   IF openSource (fileName)
   THEN
      n := examineCompilationUnit () ;
      setSource (n, makekey (string (fileName))) ;
      setMainModule (n) ;
      closeSource ;
      reInitialize ;
      RETURN n
   ELSE
      fprintf1 (StdErr, 'failed to open %s\n', s) ;
      exit (1)
   END
END peepInto ;


(*
   initParser - returns the node of the module found in the source file.
*)

PROCEDURE initParser (s: String) : node ;
BEGIN
   qprintf1 ('Compiling: %s\n', s) ;
   RETURN peepInto (s)
END initParser ;


(*
   p1 - wrap the pass procedure with the correct parameter values.
*)

PROCEDURE p1 (n: node) ;
BEGIN
   pass (1, n, mcp1.CompilationUnit, isDef, openDef)
END p1 ;


(*
   p2 - wrap the pass procedure with the correct parameter values.
*)

PROCEDURE p2 (n: node) ;
BEGIN
   pass (2, n, mcp2.CompilationUnit, isDef, openDef)
END p2 ;


(*
   p3 - wrap the pass procedure with the correct parameter values.
*)

PROCEDURE p3 (n: node) ;
BEGIN
   pass (3, n, mcp3.CompilationUnit, isDef, openDef)
END p3 ;


(*
   doOpen -
*)

PROCEDURE doOpen (n: node; symName, fileName: String; exitOnFailure: BOOLEAN) : BOOLEAN ;
VAR
   postProcessed: String ;
BEGIN
   qprintf2('   Module %-20s : %s\n', symName, fileName) ;
   postProcessed := preprocessModule (fileName) ;
   setSource (n, makekey (string (postProcessed))) ;
   setCurrentModule (n) ;
   IF openSource (postProcessed)
   THEN
      RETURN TRUE
   END ;
   fprintf1 (StdErr, 'failed to open %s\n', fileName) ;
   IF exitOnFailure
   THEN
      exit (1)
   END ;
   RETURN FALSE
END doOpen ;


(*
   openDef - try and open the definition module source file.
             Returns true/false if successful/unsuccessful or
             exitOnFailure.
*)

PROCEDURE openDef (n: node; exitOnFailure: BOOLEAN) : BOOLEAN ;
VAR
   sourceName: Name ;
   symName,
   fileName  : String ;
BEGIN
   sourceName := getSource (n) ;
   symName := InitStringCharStar (keyToCharStar (getSymName (n))) ;
   IF sourceName=NulName
   THEN
      IF NOT findSourceDefFile (symName, fileName)
      THEN
         fprintf1 (StdErr, 'failed to find definition module %s.def\n', symName) ;
         IF exitOnFailure
         THEN
            exit (1)
         END
      END
   ELSE
      fileName := InitStringCharStar (keyToCharStar (sourceName))
   END ;
   RETURN doOpen (n, symName, fileName, exitOnFailure)
END openDef ;


(*
   openMod - try and open the implementation/program module source file.
             Returns true/false if successful/unsuccessful or
             exitOnFailure.
*)

PROCEDURE openMod (n: node; exitOnFailure: BOOLEAN) : BOOLEAN ;
VAR
   sourceName: Name ;
   symName,
   fileName  : String ;
BEGIN
   sourceName := getSource (n) ;
   symName := InitStringCharStar (keyToCharStar (getSymName (n))) ;
   IF sourceName=NulName
   THEN
      IF NOT findSourceModFile (symName, fileName)
      THEN
         IF isImp (n)
         THEN
            fprintf1 (StdErr, 'failed to find implementation module %s.mod\n', symName)
         ELSE
            fprintf1 (StdErr, 'failed to find program module %s.mod\n', symName)
         END ;
         IF exitOnFailure
         THEN
            exit (1)
         END
      END
   ELSE
      fileName := InitStringCharStar (keyToCharStar (sourceName))
   END ;
   RETURN doOpen (n, symName, fileName, exitOnFailure)
END openMod ;


(*
   pass -
*)

PROCEDURE pass (no: CARDINAL; n: node; f: parserFunction;
                isnode: isNodeF; open: openFunction) ;
BEGIN
   IF isnode (n)
   THEN
      IF open (n, TRUE)
      THEN
         IF NOT f ()
         THEN
            writeFormat0 ('compilation failed') ;
            closeSource ;
            RETURN
         END ;
         closeSource
      END
   END
END pass ;


(*
   doPass -
*)

PROCEDURE doPass (parseDefs, parseMain: BOOLEAN;
                  no: CARDINAL; p: performOperation; desc: ARRAY OF CHAR) ;
VAR
   descs: String ;
BEGIN
   setToPassNo (no) ;
   descs := InitString (desc) ;
   qprintf2 ('Pass %d: %s\n', no, descs) ;
   (*
    *  need to parse the main module (to add definition module
    *  dependencies) but only if the main module is not a definition
    *  module.
    *)
   IF parseMain AND (NOT isDef (getMainModule ()))
   THEN
      p (getMainModule ())
   END ;
   IF parseDefs
   THEN
      foreachDefModuleDo (p)
   END ;
   flushWarnings ; flushErrors ;
   setToPassNo (0)
END doPass ;


(*
   setToPassNo -
*)

PROCEDURE setToPassNo (n: CARDINAL) ;
BEGIN
   currentPass := n
END setToPassNo ;


(*
   init - initialise data structures for this module.
*)

PROCEDURE init ;
BEGIN
   setToPassNo (0)
END init ;


BEGIN
   init
END mcComp.
