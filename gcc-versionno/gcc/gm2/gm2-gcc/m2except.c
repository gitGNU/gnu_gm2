/* Copyright (C) 2008, 2009, 2010, 2011, 2012, 2013
 * Free Software Foundation, Inc.
 *
 *  Gaius Mulley <gaius@glam.ac.uk> constructed this file.
 *  It was built by borrowing code from the gcc-.../gcc/cp/except.c
 *  file and its function is to provide an interface between the
 *  Modula-2 front end quadruples and GCC's exception handling ABI.
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

#include "config.h"
#include "system.h"
#include "coretypes.h"
#include "tm.h"
#include "tree.h"
#include "toplev.h"
#include "tm_p.h"
#include "flags.h"
#include <stdio.h>


/*
 *  utilize some of the C build routines
 */

#include "c-tree.h"
#include "rtl.h"
#include "function.h"
#include "expr.h"
#include "output.h"
#include "ggc.h"
#include "intl.h"
#include "convert.h"
#include "target.h"
#include "debug.h"
#include "diagnostic.h"
#include "except.h"
#include "libfuncs.h"
#include "../gm2-tree.h"


#define GM2
#define GM2_BUG_REPORT "Please report this crash to the GNU Modula-2 mailing list <gm2@glam.ac.uk>\n"

#define ASSERT(X,Y)   { if (!(X)) { debug_tree(Y); internal_error("[%s:%d]:condition `%s' failed", \
                                                                   __FILE__, __LINE__, #X); } }
#define ERROR(X)      { internal_error("[%s:%d]:%s",               __FILE__, __LINE__, X); }

/* external functions */

#define m2except_c
#include "m2decl.h"
#include "m2assert.h"
#include "m2expr.h"
#include "m2type.h"
#include "m2tree.h"
#include "m2statement.h"
#include "m2block.h"

/* local prototypes */

#include "m2except.h"

static tree build_exc_ptr (location_t location);
static tree do_begin_catch (location_t location);
static tree do_end_catch (location_t location);
static tree begin_handler (location_t location);
static void finish_handler (location_t location, tree handler);
static tree finish_handler_parms (location_t location, tree handler);
static void finish_handler_sequence (tree try_block);
static tree begin_try_block (location_t location);
static tree finish_expr_stmt (location_t location, tree expr);
static tree maybe_cleanup_point_expr_void (tree expr);
static tree build_target_expr_with_type (location_t location, tree init, tree type);
static tree get_target_expr (location_t location, tree init);
static tree build_eh_type_type (location_t location, tree type);
static tree get_tinfo_decl_m2 (location_t location);
static tree eh_type_info (location_t location, tree type);
static tree build_address (tree t);

void _M2_gm2except_init (void);
void _M2_gm2except_finally (void);

/* exception handling library functions */

static GTY(()) tree fn_begin_catch_tree = NULL_TREE;
static GTY(()) tree fn_end_catch_tree = NULL_TREE;
static GTY(()) tree fn_throw_tree = NULL_TREE;
static GTY(()) tree fn_rethrow_tree = NULL_TREE;
static GTY(()) tree cleanup_type = NULL_TREE;
static GTY(()) tree fn_allocate_exception_tree = NULL_TREE;
static GTY(()) tree fn_free_exception_tree = NULL_TREE;
static GTY(()) tree gm2_eh_int_type = NULL_TREE;

/* Modula-2 linker fodder */

void _M2_gm2except_init (void) {}
void _M2_gm2except_finally (void) {}


/*
 *  InitExceptions - initialize this module, it declares the
 *                   external functions and assigns them to
 *                   the appropriate global tree variables.
 */

void
m2except_InitExceptions (location_t location)
{
  tree t;

  m2assert_AssertLocation (location);
  m2block_pushGlobalScope ();
  flag_exceptions = 1;
  init_eh ();

  m2decl_BuildStartFunctionDeclaration (FALSE);
  fn_rethrow_tree = m2decl_BuildEndFunctionDeclaration (location,
							"__cxa_rethrow",
							void_type_node,
							TRUE, FALSE, TRUE);
  TREE_NOTHROW (fn_rethrow_tree) = 0;

  m2decl_BuildStartFunctionDeclaration (FALSE);
  m2decl_BuildParameterDeclaration (location,  NULL, ptr_type_node, FALSE);
  fn_begin_catch_tree = m2decl_BuildEndFunctionDeclaration (location,
							    "__cxa_begin_catch",
							    ptr_type_node,
							    TRUE, FALSE, TRUE);
  m2decl_BuildStartFunctionDeclaration (FALSE);
  fn_end_catch_tree = m2decl_BuildEndFunctionDeclaration (location,
							  "__cxa_end_catch",
							  void_type_node,
							  TRUE, FALSE, TRUE);
  /* This can throw if the destructor for the exception throws.  */
  TREE_NOTHROW (fn_end_catch_tree) = 0;

  /* The CLEANUP_TYPE is the internal type of a destructor.  */
  t = void_list_node;
  t = tree_cons (NULL_TREE, ptr_type_node, t);
  t = build_function_type (void_type_node, t);
  cleanup_type = build_pointer_type (t);

  /* Declare void __cxa_throw (void*, void*, void (*)(void*)).  */
  m2decl_BuildStartFunctionDeclaration (FALSE);
  m2decl_BuildParameterDeclaration (location, NULL, cleanup_type, FALSE);
  m2decl_BuildParameterDeclaration (location, NULL, ptr_type_node, FALSE);
  m2decl_BuildParameterDeclaration (location, NULL, ptr_type_node, FALSE);
  fn_throw_tree = m2decl_BuildEndFunctionDeclaration (location,
						      "__cxa_throw",
						      void_type_node,
						      TRUE, FALSE, TRUE);

  /* Declare void __cxa_rethrow (void).  */
  m2decl_BuildStartFunctionDeclaration (FALSE);
  fn_rethrow_tree = m2decl_BuildEndFunctionDeclaration (location,
						      "__cxa_rethrow",
						      void_type_node,
						      TRUE, FALSE, TRUE);


  /* Declare void *__cxa_allocate_exception (size_t).  */
  m2decl_BuildStartFunctionDeclaration (FALSE);
  m2decl_BuildParameterDeclaration (location, NULL, size_type_node, FALSE);
  fn_allocate_exception_tree = m2decl_BuildEndFunctionDeclaration (location,
								   "__cxa_allocate_exception",
								   ptr_type_node, 
								   TRUE, FALSE, TRUE);

  /* Declare void *__cxa_free_exception (void *).  */
  m2decl_BuildStartFunctionDeclaration (FALSE);
  m2decl_BuildParameterDeclaration (location, NULL, ptr_type_node, FALSE);
  fn_free_exception_tree = m2decl_BuildEndFunctionDeclaration (location,
							       "__cxa_free_exception",
							       ptr_type_node, 
							       TRUE, FALSE, TRUE);

  /*
   *  define integer type exception type which will match
   *  C++ int type in the C++ runtime library.
   */
  gm2_eh_int_type = build_eh_type_type (location, integer_type_node);
  m2block_popGlobalScope ();

  MARK_TS_TYPED (TRY_BLOCK);
  MARK_TS_TYPED (THROW_EXPR);
  MARK_TS_TYPED (HANDLER);
  MARK_TS_TYPED (EXPR_STMT);
}

/*
 *  build_exc_ptr - creates the GCC internal type, pointer to
 *                  exception control block.
 */

static tree
build_exc_ptr (location_t location)
{
  tree *argarray = XALLOCAVEC (tree, 1);
  tree exe_ptr = builtin_decl_explicit (BUILT_IN_EH_POINTER);

  m2assert_AssertLocation (location);
  argarray[0] = integer_zero_node;
  return build_call_array_loc (location, TREE_TYPE (exe_ptr), exe_ptr, 1, argarray);
}

static
tree
get_tinfo_decl_m2 (location_t location)
{
  tree t = build_decl (location, VAR_DECL, get_identifier ("_ZTIi"),
		       ptr_type_node);

  m2assert_AssertLocation (location);
  TREE_STATIC (t) = 1;
  DECL_EXTERNAL (t) = 1;
  TREE_PUBLIC (t) = 1;
  DECL_ARTIFICIAL (t) = 1;
  DECL_IGNORED_P (t) = 1;
  m2block_pushDecl (t);
  make_decl_rtl (t);
  return t;
}

/* Return the type info for TYPE as used by EH machinery.  */
static
tree
eh_type_info (location_t location, tree type)
{
  m2assert_AssertLocation (location);
  if (type == NULL_TREE || type == error_mark_node)
    return type;

  return get_tinfo_decl_m2 (location);
}

/* Return an ADDR_EXPR giving the address of T.  This function
   attempts no optimizations or simplifications; it is a low-level
   primitive.  */

static
tree
build_address (tree t)
{
  tree addr = build1 (ADDR_EXPR, build_pointer_type (TREE_TYPE (t)), t);

  return addr;
}

/* Build the address of a typeinfo decl for use in the runtime
   matching field of the exception model.  */

static tree
build_eh_type_type (location_t location, tree type)
{
  tree exp = eh_type_info (location, type);

  m2assert_AssertLocation (location);
  if (!exp)
    return NULL;

  TREE_USED (exp) = 1;
  return convert (ptr_type_node, build_address (exp));
}

/* Build a TARGET_EXPR, initializing the DECL with the VALUE.  */

static tree
build_target_expr (tree decl, tree value)
{
  tree t = build4 (TARGET_EXPR, TREE_TYPE (decl), decl, value,
		   NULL_TREE, NULL_TREE);
  /* We always set TREE_SIDE_EFFECTS so that expand_expr does not
     ignore the TARGET_EXPR.  If there really turn out to be no
     side-effects, then the optimizer should be able to get rid of
     whatever code is generated anyhow.  */
  TREE_SIDE_EFFECTS (t) = 1;

  return t;
}

/* Return an undeclared local temporary of type TYPE for use in building a
   TARGET_EXPR.  */

static tree
build_local_temp (location_t location, tree type)
{
  tree slot = build_decl (location, VAR_DECL, NULL_TREE, type);

  m2assert_AssertLocation (location);
  DECL_ARTIFICIAL (slot) = 1;
  DECL_IGNORED_P (slot) = 1;
  DECL_CONTEXT (slot) = current_function_decl;
  layout_decl (slot, 0);
  return slot;
}

/* Build a TARGET_EXPR using INIT to initialize a new temporary of the
   indicated TYPE.  */

static
tree
build_target_expr_with_type (location_t location, tree init, tree type)
{
  tree slot;

  m2assert_AssertLocation (location);
  gcc_assert (!VOID_TYPE_P (type));

  if (TREE_CODE (init) == TARGET_EXPR)
    return init;

  slot = build_local_temp (location, type);
  return build_target_expr (slot, init);
}

/* Like build_target_expr_with_type, but use the type of INIT.  */

static
tree
get_target_expr (location_t location, tree init)
{
  m2assert_AssertLocation (location);
  return build_target_expr_with_type (location, init, TREE_TYPE (init));
}

/*
 *  do_allocate_exception - returns a tree which calls  allocate_exception (sizeof (type));
 */

static tree
do_allocate_exception (location_t location, tree type)
{
  tree func;

  m2statement_BuildParam (location, size_in_bytes (type));
  func = m2statement_BuildProcedureCallTree (location,
					     fn_allocate_exception_tree, ptr_type_node);
  m2statement_SetLastFunction (NULL_TREE);
  return func;
}

/* Call __cxa_free_exception from a cleanup.  This is never invoked
   directly, but see the comment for stabilize_throw_expr.  */

static tree
do_free_exception (location_t location, tree ptr)
{
  tree func;

  m2statement_BuildParam (location, ptr);
  func = m2statement_BuildProcedureCallTree (location,
					     fn_free_exception_tree, ptr_type_node);
  m2statement_SetLastFunction (NULL_TREE);
  return func;
}

/*
 *  do_throw - returns tree for a call to throw (ptr, gm2_eh_int_type, 0).
 */

static tree
do_throw (location_t location, tree ptr)
{
  tree func;

  m2statement_BuildParam (location, ptr);
  m2statement_BuildParam (location, gm2_eh_int_type);
  m2statement_BuildParam (location, build_int_cst (cleanup_type, 0));

  func = m2statement_BuildProcedureCallTree (location,
					     fn_throw_tree, void_type_node);
  m2statement_SetLastFunction (NULL_TREE);
  return func;
}

/*
 *  do_rethrow - returns a tree containing the call to rethrow ().
 */

static tree
do_rethrow (location_t location)
{
  tree func;

  func = m2statement_BuildProcedureCallTree (location,
					     fn_rethrow_tree, void_type_node);
  m2statement_SetLastFunction (NULL_TREE);
  return func;
}

/*
 *  gm2_build_throw - build a GCC throw expression tree which looks identical to the C++
 *                    front end.
 */

static tree
gm2_build_throw (location_t location, tree exp)
{
  m2assert_AssertLocation (location);

  if (exp == NULL_TREE)
    {
      /* rethrow the current exception */
      return build1 (THROW_EXPR, void_type_node, do_rethrow (location));
    }
  else
    {
      tree cleanup;
      tree object, ptr;
      tree allocate_expr;
      tree tmp;
      tree *argarray = XALLOCAVEC (tree, 3);

      exp = m2expr_FoldAndStrip (convert (m2type_GetIntegerType (), m2expr_FoldAndStrip (exp)));
      exp = m2expr_GetIntegerOne ();

      /* Allocate the space for the exception.  */
      allocate_expr = do_allocate_exception (location, TREE_TYPE (exp));
      allocate_expr = get_target_expr (location, allocate_expr);
      ptr = TARGET_EXPR_SLOT (allocate_expr);
      TARGET_EXPR_CLEANUP (allocate_expr) = do_free_exception (location, ptr);
      CLEANUP_EH_ONLY (allocate_expr) = 1;

      object = build1 (NOP_EXPR, build_pointer_type (TREE_TYPE (exp)), ptr);
      object = m2expr_BuildIndirect (location, object, TREE_TYPE (exp));

      /* And initialize the exception object.  */
      exp = build2 (INIT_EXPR, TREE_TYPE (object), object, exp);

      /* Prepend the allocation.  */
      exp = build2 (COMPOUND_EXPR, TREE_TYPE (exp), allocate_expr, exp);

      /* Force all the cleanups to be evaluated here so that we don't have
	 to do them during unwinding.  */
      exp = build1 (CLEANUP_POINT_EXPR, void_type_node, exp);

      tmp = do_throw (location, ptr);

      /* Tack on the initialization stuff.  */
      exp = build2 (COMPOUND_EXPR, TREE_TYPE (tmp), exp, tmp);
      exp = build1 (THROW_EXPR, void_type_node, exp);

      return exp;
    }
}

/*
 *  gccgm2_BuildThrow - builds a throw expression and
 *                      return the tree.
 */

tree
m2except_BuildThrow (location_t location, tree expr)
{
  expr = gm2_build_throw (location, expr);

  /* Simplification of inner statement expressions, compound exprs,
     etc can result in us already having an EXPR_STMT.  */
  if (TREE_CODE (expr) != CLEANUP_POINT_EXPR)
    {
      if (TREE_CODE (expr) != EXPR_STMT)
	expr = build_stmt (input_location, EXPR_STMT, expr);
      expr = maybe_cleanup_point_expr_void (expr);
    }
  
  return expr;
}


/*  Build up a call to __cxa_begin_catch, to tell the runtime that the
 *  exception has been handled.
 */

static tree
do_begin_catch (location_t location)
{
  tree *argarray = XALLOCAVEC (tree, 1);

  m2assert_AssertLocation (location);
  argarray[0] = build_exc_ptr (location);
  return build_call_array_loc (location, TREE_TYPE (fn_begin_catch_tree),
			       fn_begin_catch_tree, 1, argarray);
}

/* Build up a call to __cxa_end_catch, to destroy the exception object
   for the current catch block if no others are currently using it.  */

static tree
do_end_catch (location_t location)
{
  tree cleanup = build_call_array_loc (location, TREE_TYPE (fn_end_catch_tree),
				       fn_end_catch_tree, 0, NULL);

  m2assert_AssertLocation (location);
  TREE_NOTHROW (cleanup) = 1;
  return cleanup;
}

/*
 *  BuildTryBegin - returns a tree representing the 'try' block.
 */

tree
m2except_BuildTryBegin (location_t location)
{
  m2assert_AssertLocation (location);
  return begin_try_block (location);
}

/*
 *  BuildTryEnd - builds the end of the Try block and prepares
 *                for the catch handlers.
 */

void
m2except_BuildTryEnd (tree try_block)
{
  TRY_STMTS (try_block) = m2block_pop_statement_list ();
  TRY_STMTS (try_block) = m2block_end_statement_list (TRY_STMTS (try_block));

  TRY_HANDLERS (try_block) = m2block_begin_statement_list ();

  /* now ensure that all successive add_stmts adds to this statement sequence */
  m2block_push_statement_list (TRY_HANDLERS (try_block));
}

/*
 *  BuildCatchBegin - creates a handler tree for the C++
 *                    statement 'catch (...) {'.
 *                    It returns the handler tree.
 */

tree
m2except_BuildCatchBegin (location_t location)
{
  tree handler = begin_handler (location);

  m2assert_AssertLocation (location);
  return finish_handler_parms (location, handler);
}

/*
 *  BuildCatchEnd - completes a try catch block.
 *                  It returns the, try_block, tree.
 *                  It creates the C++ statement
 *
 *                  '}' which matches the catch above.
 */

tree
m2except_BuildCatchEnd (location_t location, tree handler, tree try_block)
{
  m2assert_AssertLocation (location);
  finish_handler (location, handler);
  finish_handler_sequence (try_block);
  return try_block;
}

/* Begin a handler.  Returns a HANDLER if appropriate.  */

static
tree
begin_handler (location_t location)
{
  tree r;

  m2assert_AssertLocation (location);
  r = build_stmt (location, HANDLER, NULL_TREE, NULL_TREE);
  add_stmt (r);

  HANDLER_BODY (r) = m2block_begin_statement_list ();

  /* now ensure that all successive add_stmts adds to this statement sequence */
  m2block_push_statement_list (HANDLER_BODY (r));
  return r;
}

/* Finish a handler, which may be given by HANDLER.  The BLOCKs are
   the return value from the matching call to finish_handler_parms.  */

static
void
finish_handler (location_t location, tree handler)
{
  /* we might need to rethrow the exception if we reach the end */
  /* use this code:  finish_expr_stmt (build_throw (NULL_TREE)); */
  tree body = m2block_pop_statement_list ();

  m2assert_AssertLocation (location);
  HANDLER_BODY (handler) = body;
  m2block_end_statement_list (HANDLER_BODY (handler));
  HANDLER_BODY (handler) = build2 (TRY_FINALLY_EXPR, void_type_node, body, do_end_catch (location));
}

/* Finish the handler-parameters for a handler, which may be given by
   HANDLER.  */

static
tree
finish_handler_parms (location_t location, tree handler)
{
  m2assert_AssertLocation (location);
  /* equivalent to C++ catch (...) */
  finish_expr_stmt (location, do_begin_catch (location));

  HANDLER_TYPE (handler) = NULL_TREE;
  return handler;
}

/* Finish a handler-sequence for a try-block, which may be given by
   TRY_BLOCK.  */

static
void
finish_handler_sequence (tree try_block)
{
  TRY_HANDLERS (try_block) = m2block_pop_statement_list ();
  m2block_end_statement_list (TRY_HANDLERS (try_block));
}

/* Begin a try-block.  Returns a newly-created TRY_BLOCK if
   appropriate.  */

static
tree
begin_try_block (location_t location)
{
  tree r = build_stmt (location, TRY_BLOCK, NULL_TREE, NULL_TREE);

  m2assert_AssertLocation (location);
  TRY_STMTS (r) = m2block_begin_statement_list ();

  /* now ensure that all successive add_stmts adds to this statement sequence */
  m2block_push_statement_list (TRY_STMTS (r));
  return r;
}

/* Finish an expression-statement, whose EXPRESSION is as indicated.  */

static
tree
finish_expr_stmt (location_t location, tree expr)
{
  tree r = NULL_TREE;

  m2assert_AssertLocation (location);
  if (expr != NULL_TREE)
    {
      expr = build1 (CONVERT_EXPR, void_type_node, expr);

      /* Simplification of inner statement expressions, compound exprs,
	 etc can result in us already having an EXPR_STMT.  */
      if (TREE_CODE (expr) != CLEANUP_POINT_EXPR)
	{
	  if (TREE_CODE (expr) != EXPR_STMT)
	    expr = build_stmt (location, EXPR_STMT, expr);
	  expr = maybe_cleanup_point_expr_void (expr);
	}
      r = add_stmt (expr);
    }

  return r;
}

/* Like maybe_cleanup_point_expr except have the type of the new expression be
   void so we don't need to create a temporary variable to hold the inner
   expression.  The reason why we do this is because the original type might be
   an aggregate and we cannot create a temporary variable for that type.  */

static tree
maybe_cleanup_point_expr_void (tree expr)
{
  /* if (stmts_are_full_exprs_p ()) */
  return fold_build_cleanup_point_expr (void_type_node, expr);
}

#include "gt-gm2-m2except.h"