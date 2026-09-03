# aidl - Android Interface Definition Language compiler (Linux build)

add_executable(aidl
    ${SRC}/aidl/aidl_checkapi.cpp
    ${SRC}/aidl/aidl_const_expressions.cpp
    ${SRC}/aidl/aidl_dumpapi.cpp
    ${SRC}/aidl/aidl_language_l.cpp
    ${SRC}/aidl/aidl_language_y.cpp
    ${SRC}/aidl/aidl_language.cpp
    ${SRC}/aidl/aidl_to_common.cpp
    ${SRC}/aidl/aidl_to_cpp_common.cpp
    ${SRC}/aidl/aidl_to_cpp.cpp
    ${SRC}/aidl/aidl_to_java.cpp
    ${SRC}/aidl/aidl_to_ndk.cpp
    ${SRC}/aidl/aidl_to_rust.cpp
    ${SRC}/aidl/aidl_typenames.cpp
    ${SRC}/aidl/aidl.cpp
    ${SRC}/aidl/ast_java.cpp
    ${SRC}/aidl/check_valid.cpp
    ${SRC}/aidl/code_writer.cpp
    ${SRC}/aidl/comments.cpp
    ${SRC}/aidl/diagnostics.cpp
    ${SRC}/aidl/generate_aidl_mappings.cpp
    ${SRC}/aidl/generate_cpp.cpp
    ${SRC}/aidl/generate_cpp_analyzer.cpp
    ${SRC}/aidl/generate_java_binder.cpp
    ${SRC}/aidl/generate_java.cpp
    ${SRC}/aidl/generate_ndk.cpp
    ${SRC}/aidl/generate_rust.cpp
    ${SRC}/aidl/import_resolver.cpp
    ${SRC}/aidl/io_delegate.cpp
    ${SRC}/aidl/location.cpp
    ${SRC}/aidl/logging.cpp
    ${SRC}/aidl/options.cpp
    ${SRC}/aidl/parser.cpp
    ${SRC}/aidl/permission.cpp
    ${SRC}/aidl/preprocess.cpp
    ${SRC}/aidl/main.cpp
    )

target_include_directories(aidl PRIVATE
    ${SRC}/aidl/include
    ${SRC}/libbase/include
    ${SRC}/fmtlib/include
    ${SRC}/googletest/googletest/include
    )

target_compile_definitions(aidl PRIVATE PLATFORM_SDK_VERSION=36)

target_link_libraries(aidl
    libbase
    liblog
    gmock
    fmt::fmt
    Threads::Threads
    )
