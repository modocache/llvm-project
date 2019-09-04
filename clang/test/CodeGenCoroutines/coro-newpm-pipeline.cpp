// Tests that coroutine passes are added to and run by the new pass manager
// pipeline.

// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm-bc -o /dev/null \
// RUN:   -fexperimental-new-pass-manager -fdebug-pass-manager -fcoroutines-ts \
// RUN:   -O0 %s 2>&1 | FileCheck %s -check-prefix=CHECK-O0
//
// Clang must run certain LLVM passes, even at -O0: 'always_inline' functions
// must be inlined, and coroutines must be transformed. (NB: coro-early is a
// function pass, but is adapted here to run as part of a module pass manager.
// As a result, an analysis pass to grab the function analysis manager is run
// as part of the pipeline we're testing here.)
//
// CHECK-O0: Starting llvm::Module pass manager run.
// CHECK-O0-NEXT: Running pass: AlwaysInlinerPass
// CHECK-O0-NEXT: Running analysis: InnerAnalysisManagerProxy<llvm::FunctionAnalysisManager, llvm::Module>
// CHECK-O0-NEXT: Running pass: ModuleToFunctionPassAdaptor<llvm::CoroEarlyPass>
// CHECK-O0-NEXT: Running pass: BitcodeWriterPass
// CHECK-O0-NEXT: Finished llvm::Module pass manager run.

// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm-bc -o /dev/null \
// RUN:   -fexperimental-new-pass-manager -fdebug-pass-manager -fcoroutines-ts \
// RUN:   -O1 %s 2>&1 | FileCheck %s -check-prefix=CHECK-O1
//
// Clang runs many passes in -O1 and above, and we don't want this test to fail
// if any of those change, so here we just verify that coroutines passes are run
// at some point.
//
// CHECK-O1: Running pass: ModuleToFunctionPassAdaptor<llvm::CoroEarlyPass>
void foo() {}
