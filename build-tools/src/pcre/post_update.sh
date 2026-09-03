#!/bin/bash

set -e

cd $(dirname "$0")

CONFIGURE_ARGS=(
  ac_cv_func_secure_getenv=no
  ac_cv_header_bzlib_h=no
)

# Show the commands on the terminal.
set -x

./autogen.sh
./configure "${CONFIGURE_ARGS[@]}"

make
