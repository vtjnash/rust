//===- RustDebugInfo.h - Declaration of Rust Debug Info Parser   -------===//
//
//                             Enzyme Project
//
// Part of the Enzyme Project, under the Apache License v2.0 with LLVM
// Exceptions. See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// If using this code in an academic setting, please cite the following:
// @incollection{enzymeNeurips,
// title = {Instead of Rewriting Foreign Code for Machine Learning,
//          Automatically Synthesize Fast Gradients},
// author = {Moses, William S. and Churavy, Valentin},
// booktitle = {Advances in Neural Information Processing Systems 33},
// year = {2020},
// note = {To appear in},
// }
//
//===-------------------------------------------------------------------===//
//
// This file contains the declaration of the Rust debug info parsing function
// which parses the debug info appended to LLVM IR generated by rustc and
// extracts useful type info from it. The type info will be used to initialize
// the following type analysis.
//
//===-------------------------------------------------------------------===//
#ifndef ENZYME_RUSTDEBUGINFO_H
#define ENZYME_RUSTDEBUGINFO_H 1

#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"

using namespace llvm;

#include "TypeTree.h"

/// Construct the type tree from debug info of an instruction
TypeTree parseDIType(DbgDeclareInst &I, DataLayout &DL);

#endif // ENZYME_RUSTDEBUGINFO_H
