#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# shellcheck disable=SC1091
source /etc/os-release
arch="$(dpkg --print-architecture)"
if [[ "${ID:-}" != ubuntu || "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}" != resolute ]] ||
   [[ "$arch" != amd64 && "$arch" != arm64 ]]; then
    echo "error: expected Ubuntu 26.04 (Resolute) amd64 or arm64" >&2
    exit 1
fi

if (( EUID == 0 )); then
    sudo_command=()
else
    command -v sudo >/dev/null || { echo "error: sudo is required" >&2; exit 1; }
    sudo_command=(sudo)
fi

host_packages=(
    binutils binutils-aarch64-linux-gnu ca-certificates cmake curl file gawk
    g++-aarch64-linux-gnu gcc-aarch64-linux-gnu ninja-build
    openjdk-21-jdk-headless pkg-config python3
    qemu-user-binfmt tar unzip zip
)
"${sudo_command[@]}" apt-get update
"${sudo_command[@]}" apt-get install -y --no-install-recommends "${host_packages[@]}"

if [[ "$arch" == arm64 ]]; then
    "${sudo_command[@]}" apt-get install -y --no-install-recommends zlib1g-dev
else
    if ! dpkg --print-foreign-architectures | grep -Fxq arm64; then
        "${sudo_command[@]}" dpkg --add-architecture arm64
    fi
    ports_sources="$(mktemp --suffix=.sources)"
    trap 'rm -f -- "$ports_sources"' EXIT
    cat > "$ports_sources" <<'EOF'
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: resolute resolute-updates resolute-backports resolute-security
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    ports_options=(
        -o APT::Architectures=arm64
        -o "Dir::Etc::sourcelist=$ports_sources"
        -o Dir::Etc::sourceparts=-
    )
    "${sudo_command[@]}" apt-get update "${ports_options[@]}"
    "${sudo_command[@]}" apt-get install -y --no-install-recommends \
        "${ports_options[@]}" zlib1g-dev:arm64
    rm -f -- "$ports_sources"
    trap - EXIT
fi

echo "Dependencies installed for Ubuntu 26.04 $arch."
