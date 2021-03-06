// RUN: %clang_cc1 -std=c++2a -verify %s

template<int N> struct A {};

using F = bool(*)(int);
extern F *p;
extern int m;

struct Convertible { template<typename T> operator T(); };

void f() {
  int arr1[3];
  for (int n = 5; int x : arr1) {}

  int A<0>::*arr2[3];
  for (int n = 5; int A<true ? 0 : 1>::*x : arr2) {}

  F (*arr3[3])(int);
  for (int n = 5; F (*p)(int n) : arr3) {}
  for (int n = 5; F (*p)(int (n)) : arr3) {}

  // Here, we have a declaration rather than an expression.
  for (int n = 5; F (*p)(int (n)); ++n) {}

  // We detect whether we have a for-range-declaration before parsing so that
  // we can give different diagnostics for for-range-declarations versus
  // conditions (even though the rules are currently identical).
  Convertible arr4[3];
  for (int n = 0; struct { operator bool(); } x = {}; ++n) {} // expected-error {{cannot be defined in a condition}}
  for (int n = 0; struct { operator bool(); } x : arr4) {} // expected-error {{may not be defined in a for range declaration}}

  for (int n = 0; static int m = 0; ++n) {} // expected-error {{type name does not allow storage class}}
  for (int n = 0; static int m : arr1) {} // expected-error {{loop variable 'm' may not be declared 'static'}}
}
