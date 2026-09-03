# Android Platform Binder Codelab

go/android-binder-codelab

This Android Platform Developer codelab explores the use of Binder in the
Android Platform. go/android-codelab is a prerequisite for this work. In this
codelab, you create an AIDL interface along with client and server processes
that communicate with each other over Binder.

## Goals

There are four goals for this codelab:

1.  Introduce you to Binder, Android's core IPC mechanism
2.  Use AIDL to define a Binder interface for a simple client/server interaction
3.  Use Binder's Service Management infrastructure to make the service available
    to clients
4.  Get and use the service with basic error handling

## What to expect

### Estimated time

*   Hands-off time ~4 hours
*   Hands-on time ~1 hours

### Prerequisites

**Before** taking this codelab, complete go/android-codelab first. If external,
follow https://source.android.com/docs/setup/start.

You will need an Android repo with the ability to make changes, build, deploy,
test, and upload the changes. All of this is covered in go/android-codelab.

See the slides at go/onboarding-binder for a summary of key concepts that will
help you understand the steps in this codelab.

## Codelab

Most of this code can be found in `system/tools/aidl/codelab`, but the example
service isn't installed on real devices. The build code to install the service
on the device and the sepolicy changes are described in this `README.md` but not
submitted.

### Create the new AIDL interface

Choose a location for the AIDL interface definition.

*   `hardware/interfaces` - for
    [HAL](https://source.android.com/docs/core/architecture/hal) interfaces that
    device-specific processes implement and the Android Platform depends on as a
    client
*   `frameworks/hardware/interfaces` - for interfaces that the Android Framework
    implements for device-specific clients
*   `system/hardware/interfaces` - for interfaces that Android system process
    implement for device-specific clients
*   Any other directory for interfaces that are used between processes that are
    installed on the same
    [partitions](https://source.android.com/docs/core/architecture/partitions)

Create a new `aidl_interface` module in a new or existing `Android.bp` file.

Note: go/android.bp has all of the available Soong modules and their supported
fields.

```soong
// File: `codelab/aidl/Android.bp`
aidl_interface {
  // Package name for the interface. This is used when generating the libraries
  // that the services and clients will depend on.
  name: "hello.world",
  // The source `.aidl` files that define this interface. It is recommended to
  // create them in a directory next to this Android.bp file with a
  // directory structure that follows the package name. If you want to change
  // this, use `local_include_dir` to point to the new directory.
  srcs: [
    "hello/world/*.aidl",
  ],
  // For simplicity we start with an unstable interface. See
  // https://source.android.com/docs/core/architecture/aidl/stable-aidl
  // for details on stable interfaces.
  unstable: true,
  // This field controls which libraries are generated at build time and their
  // backend-specific configurations. AIDL supports different languages.
  backend: {
    ndk: {
      enabled: true,
    }
    rust: {
      enabled: true,
    }
  }
}
```

Create your first AIDL file.

```java
// File: `codelab/aidl/hello/world/IHello.aidl`
// The package name is recommended to match the `name` in the `aidl_interface`
package hello.world;

interface IHello {
  // Have the service log a message for us
  void LogMessage(String message);
  // Get a "hello world" message from the service
  String getMessage();
}
```

Build the generated AIDL libraries.

```shell
m hello.world-ndk hello.world-rust
```

Note: `m hello.world` without the backend suffix will not build anything.

### Create the service

Android encourages Rust for native services so let's build a Rust service!

Binder has easy-to-use libraries to facilitate fuzzing of binder services that
require the service being defined in its own library. With that in mind, we
create the library that implements the interface first.

#### Interface implementation

Create a separate library for the interface implementation so it can be used
for the service and for the fuzzer.

* See [codelab/service/Android.bp](codelab/service/Android.bp)

* See [codelab/service/hello_service.rs](codelab/service/hello_service.rs)

#### Service binary

Create the service that registers itself with servicemanager and joins the
binder threadpool.

* See [codelab/service/Android.bp](codelab/service/Android.bp)

* See [codelab/service/service_main.rs](codelab/service/service_main.rs)

An init.rc file is required for the process to be started on a device.

* See
  [codelab/service/hello-world-service-test.rc](codelab/service/hello-world-service-test.rc)

#### Sepolicy for the service

Associate the service binary with a selinux context so init can start it.
```
// File: system/sepolicy/private/file_contexts
/system/bin/hello-world-service-test u:object_r:hello_exec:s0
```

Add a file for the service to define its types, associate the binary to the
types, and give permissions to the service..
```
// File: system/sepolicy/private/hello.te

// Permissions required for the process to start
type hello, domain;
typeattribute hello coredomain;
type hello_exec, system_file_type, exec_type, file_type;
init_daemon_domain(hello)

// Permissions to be a binder service and talk to service_manager
binder_service(hello)
binder_use(hello)
binder_call(hello, binderservicedomain)

// Give permissions to this service to register itself with service_manager
allow hello hello_service:service_manager { add find };
```

Declare this service as a service_manager_type
```
// File: system/sepolicy/public/service.te
type hello_service,             service_manager_type;
```

Associate the AIDL interface/instance with this service
```
// File: system/sepolicy/private/service_contexts
hello.world.IHello/default u:object_r:hello_service:s0
```

#### Fuzzer

Create the fuzzer and use `fuzz_service` to do all of the hard work!

* See [codelab/service/Android.bp](codelab/service/Android.bp)

* See [codelab/service/service_fuzzer.rs](codelab/service/service_fuzzer.rs)

Associate the fuzzer with the interface by adding the following to
`system/sepolicy/build/soong/service_fuzzer_bindings.go`:
```
"hello.world.IHello/default":             []string{"hello-world-fuzzer"},
```
This step is required by the build system once we add the sepolicy for the
service in the previous step.

### Create the client

#### Sepolicy for the client

We skip these details by creating the client in a `cc_test`.

The clients need permission to `find` the service through servicemanager:

`allow <client> hello_service:servicemanager find;`

The clients need permission to `call` the service, pass the binders to other
processes, and use any file descriptors returned through the interface. The
`binder_call` macro handles all this for us.

`binder_call(<client>, hello_service);`

### Test the changes

Add the service to the device. Since this is a system service it needs to be
added to the system partition. We add the following to
`build/make/target/product/base_system.mk`.

```
PRODUCT_PACKAGES += hello-world-service-test
```

Build the device.

Launch the device.

Verify the service is in the `dumpsys -l` output.

`atest hello-world-client-test` and verify it passes!

## Wrap up

Congratulations! You are now familiar with some core concepts of Binder and AIDL
in Android.
When you think of IPC in Android, think of Binder.
When you think of Binder, think of AIDL.

See https://source.android.com/docs/core/architecture/aidl for related AIDL and
Binder documentation.
Check out https://source.android.com/docs/core/architecture/aidl/aidl-hals for
details that are more specific to Hardware Abstraction Layer (HAL) services.

### Supporting documentation

*   go/onboarding-binder
*   go/binder-ipc
*   go/stable-aidl
*   go/aidl-backends
*   go/aidl (for app developers with Java/Kotlin)

See all of the other AIDL related pages in our external documentation:
https://source.android.com/docs/core/architecture/aidl.

### Feedback

If you are external please see
https://source.android.com/docs/setup/contribute/report-bugs to find out how to
create a Bug for questions, suggestions, or reporting bugs.

Please write to android-idl-discuss@google.com.

Anyone is free to create and upload CLs in `system/tools/aidl/codelab/` with any
suggestions or corrections.

### Wish list

Add your suggested additions and updates to this codelab here!

1.  I wish this codelab would dive deeper into `DeathRecipients` and remote
    reference counting

