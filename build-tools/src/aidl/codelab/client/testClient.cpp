/*
 * Copyright (C) 2025, The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include <gtest/gtest.h>

#include <android/binder_auto_utils.h>
#include <android/binder_manager.h>

#include <aidl/hello/world/IHello.h>

using aidl::hello::world::IHello;

TEST(HelloWorldTestClient, GetServiceSayHello) {
  // Clients will get the binder service using the name that they registered
  // with. This is up to the service. For this example, we use the interface
  // descriptor that AIDL generates + "/default".
  std::string instance = std::string(IHello::descriptor) + "/default";
  ndk::SpAIBinder binder = ndk::SpAIBinder(AServiceManager_waitForService(instance.c_str()));
  ASSERT_NE(binder, nullptr);

  // If this is the wrong interface, this result will be null
  auto hello = IHello::fromBinder(binder);
  ASSERT_NE(hello, nullptr);

  // All AIDL generated interfaces have a return value with the status of the
  // transaction, even for void methods.
  auto res = hello->LogMessage("Hello service!");
  EXPECT_TRUE(res.isOk()) << res;
}
