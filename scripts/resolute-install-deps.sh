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

# Upgrade the native runtime packages before installing their arm64 multiarch
# peers so both architectures resolve to the same archive versions.
host_packages=(
    binutils binutils-aarch64-linux-gnu ca-certificates cmake curl file gawk
    g++-aarch64-linux-gnu gcc-aarch64-linux-gnu ninja-build
    libc6 libc6-dev libc-bin libgcc-s1 libstdc++6
    openjdk-21-jdk-headless pkg-config python3
    qemu-user-binfmt tar unzip zip zlib1g-dev
)
"${sudo_command[@]}" apt-get update
"${sudo_command[@]}" apt-get install -y --no-install-recommends "${host_packages[@]}"

if [[ "$arch" == amd64 ]]; then
    libc_version="$(dpkg-query -W -f='${Version}' libc6:amd64)"
    libc_dev_version="$(dpkg-query -W -f='${Version}' libc6-dev:amd64)"
    libgcc_version="$(dpkg-query -W -f='${Version}' libgcc-s1:amd64)"
    libstdcxx_version="$(dpkg-query -W -f='${Version}' libstdc++6:amd64)"
    zlib_version="$(dpkg-query -W -f='${Version}' zlib1g-dev:amd64)"
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
        "${ports_options[@]}" \
        "libc6:arm64=$libc_version" \
        "libc6-dev:arm64=$libc_dev_version" \
        "libgcc-s1:arm64=$libgcc_version" \
        libc++-22-dev:arm64 \
        libc++abi-22-dev:arm64 \
        "libstdc++6:arm64=$libstdcxx_version" \
        "zlib1g:arm64=$zlib_version" \
        "zlib1g-dev:arm64=$zlib_version"
    rm -f -- "$ports_sources"
    trap - EXIT

    # Package installation does not always reload binfmt on a hosted runner.
    # Register only AArch64, then require transparent execution for child tools.
    if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
        "${sudo_command[@]}" mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
    fi
    binfmt_entry=/proc/sys/fs/binfmt_misc/qemu-aarch64
    if [[ ! -r "$binfmt_entry" ]] || ! grep -Fxq enabled "$binfmt_entry" ||
       ! grep -Eq '^flags:.*F' "$binfmt_entry"; then
        "${sudo_command[@]}" /usr/lib/systemd/systemd-binfmt \
            /usr/lib/binfmt.d/qemu-aarch64.conf
    fi
    grep -Fxq enabled "$binfmt_entry"
    grep -Eq '^flags:.*F' "$binfmt_entry"
    echo "QEMU AArch64 binfmt registration enabled."
else
    "${sudo_command[@]}" apt-get install -y --no-install-recommends \
        libc++-22-dev libc++abi-22-dev
fi

echo "Dependencies installed for Ubuntu 26.04 $arch."
