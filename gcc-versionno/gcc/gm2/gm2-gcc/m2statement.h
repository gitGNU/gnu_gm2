/* Copyright (C) 2012
 * Free Software Foundation, Inc.
 *
 *  Gaius Mulley <gaius@glam.ac.uk> constructed this file.
 */

/*
This file is part of GNU Modula-2.

GNU Modula-2 is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

GNU Modula-2 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Modula-2; see the file COPYING.  If not, write to the
Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.
*/

#if !defined(m2statement_h)
#   define m2statement_h
#   if defined(m2statement_c)
#       define EXTERN 
#   else
#       define EXTERN extern
#   endif

EXTERN void m2statement_BuildEndMainModule (void);
EXTERN void m2statement_BuildStartMainModule (void);
EXTERN void m2statement_BuildCallInner (location_t location, tree fndecl);
EXTERN void m2statement_BuildEnd (tree fndecl, int nested);
EXTERN tree m2statement_BuildStart (location_t location, char *name, int inner_module);
EXTERN void m2statement_BuildIncludeVarVar (location_t location,
					    tree type, tree varset, tree varel,
					    int is_lvalue, tree low);
EXTERN void m2statement_BuildIncludeVarConst (location_t location,
					      tree type, tree op1, tree op2,
					      int is_lvalue, int fieldno);
EXTERN void m2statement_BuildExcludeVarVar (location_t location,
					    tree type, tree varset, tree varel,
					    int is_lvalue, tree low);
EXTERN void m2statement_BuildExcludeVarConst (location_t location,
					      tree type, tree op1, tree op2,
					      int is_lvalue, int fieldno);
EXTERN void m2statement_BuildUnaryForeachWordDo (location_t location,
						 tree type, tree op1, tree op2,
						 tree (*unop)(location_t, tree, int),
						 int is_op1lvalue, int is_op2lvalue,
						 int is_op1const, int is_op2const);
EXTERN void m2statement_BuildAsm (location_t location,
				  tree instr, int isVolatile, int isSimple,
				  tree inputs, tree outputs, tree trash, tree labels);
EXTERN void m2statement_BuildFunctValue (location_t location, tree value);
EXTERN tree m2statement_BuildIndirectProcedureCallTree (location_t location, tree procedure, tree rettype);
EXTERN tree m2statement_BuildProcedureCallTree (location_t location, tree procedure, tree rettype);
EXTERN void m2statement_BuildParam (location_t location, tree param);

EXTERN tree m2statement_BuildIfThenElseEnd (tree condition, tree then_block, tree else_block);
EXTERN tree m2statement_BuildIfThenDoEnd (tree condition, tree then_block);

EXTERN void m2statement_DeclareLabel (location_t location, char *name);
EXTERN void m2statement_BuildGoto (location_t location, char *name);
EXTERN tree m2statement_BuildAssignmentTree (location_t location, tree des, tree expr);
EXTERN void m2statement_BuildPopFunctionContext (void);
EXTERN void m2statement_BuildPushFunctionContext (void);
EXTERN void m2statement_BuildReturnValueCode (location_t location, tree fndecl, tree value);
EXTERN void m2statement_BuildEndFunctionCode (tree fndecl, int nested);
EXTERN void m2statement_BuildStartFunctionCode (tree fndecl, int isexported, int isinline);
EXTERN void m2statement_DoJump (location_t location, tree exp, char *falselabel, char *truelabel);
EXTERN tree m2statement_BuildCall2 (location_t location, tree function, tree rettype, tree arg1, tree arg2);
EXTERN tree m2statement_BuildCall3 (location_t location, tree function, tree rettype, tree arg1, tree arg2, tree arg3);
EXTERN void m2statement_SetLastFunction (tree t);
EXTERN tree m2statement_GetLastFunction (void);
EXTERN void m2statement_SetParamList (tree t);
EXTERN tree m2statement_GetParamList (void);
EXTERN tree m2statement_GetCurrentFunction (void);

#   undef EXTERN
#endif