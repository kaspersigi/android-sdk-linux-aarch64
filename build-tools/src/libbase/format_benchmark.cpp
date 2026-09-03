/*
 * Copyright (C) 2019 The Android Open Source Project
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

#include "android-base/format.h"

#include <unistd.h>

#include <limits>

#include <benchmark/benchmark.h>

#include "android-base/stringprintf.h"

using android::base::StringPrintf;

static pid_t pid = getpid();
static int fd = 123;

static void BM_format_fmt_format_ints(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(fmt::format("/proc/{}/fd/{}", pid, fd));
  }
}
BENCHMARK(BM_format_fmt_format_ints);

static void BM_format_std_format_ints(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(std::format("/proc/{}/fd/{}", pid, fd));
  }
}
BENCHMARK(BM_format_std_format_ints);

static void BM_format_StringPrintf_ints(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(StringPrintf("/proc/%d/fd/%d", pid, fd));
  }
}
BENCHMARK(BM_format_StringPrintf_ints);

static void BM_format_fmt_format_floats(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(fmt::format("{} {} {}", 42.42, std::numeric_limits<float>::min(),
                                         std::numeric_limits<float>::max()));
  }
}
BENCHMARK(BM_format_fmt_format_floats);

static void BM_format_std_format_floats(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(std::format("{} {} {}", 42.42, std::numeric_limits<float>::min(),
                                         std::numeric_limits<float>::max()));
  }
}
BENCHMARK(BM_format_std_format_floats);

static void BM_format_StringPrintf_floats(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(StringPrintf("%f %f %f", 42.42, std::numeric_limits<float>::min(),
                                          std::numeric_limits<float>::max()));
  }
}
BENCHMARK(BM_format_StringPrintf_floats);

static void BM_format_fmt_format_strings(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(fmt::format("{} hello there {}", "hi,", "!!"));
  }
}
BENCHMARK(BM_format_fmt_format_strings);

static void BM_format_std_format_strings(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(std::format("{} hello there {}", "hi,", "!!"));
  }
}
BENCHMARK(BM_format_std_format_strings);

static void BM_format_StringPrintf_strings(benchmark::State& state) {
  for (auto _ : state) {
    benchmark::DoNotOptimize(StringPrintf("%s hello there %s", "hi,", "!!"));
  }
}
BENCHMARK(BM_format_StringPrintf_strings);

// Run the benchmark
BENCHMARK_MAIN();
