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
//! Implements and serves the hello.world.IHello interface for the
//! AIDL / Binder codelab

use binder::{Interface, Result};
use hello_world::aidl::hello::world::IHello::IHello;
use log::info;

//pub mod hello_service;

/// Implementation for the IHello service used for a codelab
pub struct Hello;

impl Hello {}

impl Interface for Hello {}

impl IHello for Hello {
    fn LogMessage(&self, msg: &str) -> Result<()> {
        info!("{}", msg);
        Ok(())
    }
    fn getMessage(&self) -> Result<String> {
        Ok("Hello World!".to_string())
    }
}
