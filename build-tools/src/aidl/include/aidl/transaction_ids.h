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

#pragma once

namespace android {
namespace aidl {

// Copied from android.is.IBinder.[FIRST|LAST]_CALL_TRANSACTION
const int kFirstCallTransaction = 1;
const int kLastCallTransaction = 0x00ffffff;

// Following IDs are all offsets from  kFirstCallTransaction

// IDs for meta transactions. Most of the meta transactions are implemented in
// the framework side (Binder.java or Binder.cpp). But these are the ones that
// are auto-implemented by the AIDL compiler.
const int kFirstMetaMethodId = kLastCallTransaction - kFirstCallTransaction;
const int kGetInterfaceVersionId = kFirstMetaMethodId;
const int kGetInterfaceHashId = kFirstMetaMethodId - 1;
// Additional meta transactions implemented by AIDL should use
// kFirstMetaMethodId -1, -2, ...and so on.

// Reserve 100 IDs for meta methods, which is more than enough. If we don't reserve,
// in the future, a newly added meta transaction ID will have a chance to
// collide with the user-defined methods that were added in the past. So,
// let's prevent users from using IDs in this range from the beginning.
const int kLastMetaMethodId = kFirstMetaMethodId - 99;

// Range of IDs that is allowed for user-defined methods.
const int kMinUserSetMethodId = 0;
const int kMaxUserSetMethodId = kLastMetaMethodId - 1;

}  // namespace aidl
}  // namespace android
