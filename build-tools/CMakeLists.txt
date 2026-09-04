#
# Android Build Tools 36.0.0 for GNU/Linux AArch64
#
# Builds Android SDK tools as native Linux AArch64 binaries.
# Adapted from https://github.com/lzhiyong/android-sdk-tools (Apache 2.0)
#

cmake_minimum_required(VERSION 3.14.2)
project(android-build-tools-linux-aarch64)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)

find_package(Threads REQUIRED)

# set global cflags and cxxflags
set(REPRODUCIBLE_PATH_FLAGS
    "-ffile-prefix-map=${PROJECT_SOURCE_DIR}=android-build-tools -fmacro-prefix-map=${PROJECT_SOURCE_DIR}=android-build-tools")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC -Wno-attributes ${REPRODUCIBLE_PATH_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -Wno-attributes ${REPRODUCIBLE_PATH_FLAGS}")

# GCC compatibility: stub out Clang-specific nullability annotations
if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    add_definitions(-D_Nonnull= -D_Nullable= -D_Null_unspecified=)
endif()

# Android Build Tools version
set(TOOLS_VERSION 36.0.0)
set(SRC ${PROJECT_SOURCE_DIR}/src)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# 64-bit off_t for lseek
add_definitions(-D_FILE_OFFSET_BITS=64)

# third-party libraries
add_subdirectory(src/boringssl EXCLUDE_FROM_ALL)
add_subdirectory(src/fmtlib EXCLUDE_FROM_ALL)
set(PCRE2_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(PCRE2_BUILD_PCRE2GREP OFF CACHE BOOL "" FORCE)
add_subdirectory(src/pcre EXCLUDE_FROM_ALL)
add_subdirectory(src/libpng EXCLUDE_FROM_ALL)
add_subdirectory(src/zopfli EXCLUDE_FROM_ALL)
add_subdirectory(src/jsoncpp EXCLUDE_FROM_ALL)

# Expat: arc4random_buf detection finds glibc 2.41's implementation but the
# symbol is hidden under -std=c99 compilation. Disable it so expat uses
# getrandom() instead.
set(HAVE_ARC4RANDOM_BUF OFF CACHE BOOL "" FORCE)
set(HAVE_ARC4RANDOM OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_PKGCONFIG OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(EXPAT_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
add_subdirectory(src/expat/expat EXCLUDE_FROM_ALL)
configure_file(
    ${SRC}/protobuf/build/config.h
    ${CMAKE_CURRENT_BINARY_DIR}/src/protobuf/config.h
    COPYONLY
    )
add_subdirectory(src/protobuf EXCLUDE_FROM_ALL)
add_subdirectory(src/googletest EXCLUDE_FROM_ALL)

# Android libraries shared by the six executables, then the executables.
add_subdirectory(cmake/libraries)
add_subdirectory(cmake/tools)
