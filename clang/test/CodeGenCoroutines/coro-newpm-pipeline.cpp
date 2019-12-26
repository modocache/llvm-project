// Tests that coroutine passes are added to and run by the new pass manager
// pipeline, at -O0 and above.

// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm-bc -o /dev/null \
// RUN:   -fexperimental-new-pass-manager -fdebug-pass-manager -fcoroutines-ts \
// RUN:   -O0 %s 2>&1 | FileCheck %s
// RUN: %clang_cc1 -triple x86_64-unknown-linux-gnu -emit-llvm-bc -o /dev/null \
// RUN:   -fexperimental-new-pass-manager -fdebug-pass-manager -fcoroutines-ts \
// RUN:   -O1 %s 2>&1 | FileCheck %s
//
// CHECK: Starting llvm::Module pass manager run.
// CHECK: Running pass:{{.*}}CoroEarlyPass
// CHECK: Running pass:{{.*}}CoroSplitPass
// CHECK: Running pass:{{.*}}CoroElidePass
// CHECK: Running pass:{{.*}}CoroSplitPass
// CHECK: Running pass:{{.*}}CoroCleanupPass
// CHECK: Finished llvm::Module pass manager run.
void foo() {}
