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
//! Service that registers the IHello interface for a codelab

use hello_service::Hello;
use hello_world::aidl::hello::world::IHello::{BnHello, IHello};

fn main() {
    // We join the threadpool with this main thread and never exit. We don't
    // have any callback binders in this interface, so the single thread is OK.
    // Set the max to 0 here so libbinder doesn't spawn any additional threads.
    binder::ProcessState::set_thread_pool_max_thread_count(0);

    let service = BnHello::new_binder(Hello, binder::BinderFeatures::default());
    let service_name = format!("{}/default", Hello::get_descriptor());
    binder::add_service(&service_name, service.as_binder())
        .expect("Failed to register IHello service!");

    binder::ProcessState::join_thread_pool()
}
