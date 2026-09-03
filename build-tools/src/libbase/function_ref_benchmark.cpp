/*
 * Copyright (C) 2022 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "android-base/function_ref.h"

#include <benchmark/benchmark.h>

#include <functional>
#include <utility>

#include <time.h>

using android::base::function_ref;

template <class Callable, class... Args>
[[clang::noinline]] auto call(Callable&& c, Args&&... args) {
  return c(std::forward<Args>(args)...);
}

[[clang::noinline]] static int testFunc(int, const char*, char) {
  return time(nullptr);
}

using Func = decltype(testFunc);

static void BM_FuncRaw(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(testFunc, 1, "1", '1'));
  }
}
BENCHMARK(BM_FuncRaw);

static void BM_FuncPtr(benchmark::State& state) {
  auto ptr = &testFunc;
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(ptr, 1, "1", '1'));
  }
}
BENCHMARK(BM_FuncPtr);

static void BM_StdFunction(benchmark::State& state) {
  std::function<Func> f(testFunc);
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(f, 1, "1", '1'));
  }
}
BENCHMARK(BM_StdFunction);

static void BM_FunctionRef(benchmark::State& state) {
  function_ref<Func> f(testFunc);
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(f, 1, "1", '1'));
  }
}
BENCHMARK(BM_FunctionRef);

namespace {
struct BigFunc {
  char big[128];
  [[clang::noinline]] int operator()(int, const char*, char) const { return time(nullptr); }
};

static BigFunc bigFunc;
}  // namespace

static void BM_BigRaw(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(bigFunc, 1, "1", '1'));
  }
}
BENCHMARK(BM_BigRaw);

static void BM_BigStdFunction(benchmark::State& state) {
  std::function<Func> f(bigFunc);
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(f, 1, "1", '1'));
  }
}
BENCHMARK(BM_BigStdFunction);

static void BM_BigFunctionRef(benchmark::State& state) {
  function_ref<Func> f(bigFunc);
  for (auto _ : state) {
    benchmark::DoNotOptimize(call(f, 1, "1", '1'));
  }
}
BENCHMARK(BM_BigFunctionRef);

static void BM_MakeFunctionRef(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(call<function_ref<Func>>(bigFunc, 1, "1", '1'));
  }
}
BENCHMARK(BM_MakeFunctionRef);

static void BM_MakeStdFunction(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(call<std::function<Func>>(bigFunc, 1, "1", '1'));
  }
}
BENCHMARK(BM_MakeStdFunction);
