#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"
cache_dir="$project_root/.cache"
sources_dir="$project_root/sources"
build_dir="$project_root/build"
dist_dir="$project_root/dist"

# shellcheck disable=SC1091
source "$project_root/sources.lock"

host_jobs="$(nproc)"
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    jobs="${JOBS:-$host_jobs}"
else
    if [[ ${JOBS+x} == x && "$JOBS" != "$host_jobs" ]]; then
        echo "error: local builds must use all $host_jobs processors reported by nproc" >&2
        echo "       JOBS is reserved for GitHub Actions resource limits" >&2
        exit 2
    fi
    jobs="$host_jobs"
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || {
    echo "error: JOBS must be a positive integer" >&2
    exit 2
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_resolute_host() {
    local allow_unsupported_host=${ALLOW_UNSUPPORTED_HOST:-0}
    local ubuntu_codename

    [[ "$allow_unsupported_host" == "0" || "$allow_unsupported_host" == "1" ]] ||
        die "ALLOW_UNSUPPORTED_HOST must be 0 or 1"
    [[ -r /etc/os-release ]] ||
        die "cannot identify the host because /etc/os-release is unavailable"

    # /etc/os-release is the system-provided distribution metadata.
    # shellcheck disable=SC1091
    source /etc/os-release
    ubuntu_codename=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
    if [[ "$allow_unsupported_host" != "1" ]] && {
        [[ "${ID:-}" != "ubuntu" ]] ||
        [[ "${VERSION_ID:-}" != "26.04" ]] ||
        [[ "$ubuntu_codename" != "resolute" ]];
    }; then
        die "this build requires Ubuntu 26.04 (Resolute); detected ${PRETTY_NAME:-unknown}"
    fi

    case "$(uname -m)" in
        x86_64|amd64|aarch64|arm64) ;;
        *) die "unsupported build-host architecture: $(uname -m)" ;;
    esac
}

download_checked() {
    local url="$1" output="$2" algorithm="$3" expected="$4"
    local actual temporary
    mkdir -p -- "$(dirname -- "$output")"

    if [[ -f "$output" ]]; then
        actual="$(${algorithm}sum "$output" | awk '{print $1}')"
        if [[ "$actual" == "$expected" ]]; then
            echo "Using cached $(basename -- "$output")"
            return
        fi
        rm -f -- "$output"
    fi

    temporary="${output}.part"
    rm -f -- "$temporary"
    curl --fail --location --retry 3 --output "$temporary" "$url"
    actual="$(${algorithm}sum "$temporary" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        rm -f -- "$temporary"
        die "checksum mismatch for $url: expected $expected, got $actual"
    }
    mv -- "$temporary" "$output"
}

download_latest_github_release_asset() {
    local repository="$1" asset="$2" checksum_asset="$3" output="$4"
    local result_variable="$5"
    local metadata checksum_temporary expected tag asset_url checksum_url
    local asset_digest checksum_digest actual_checksum_digest
    local -a curl_args release_fields

    [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        die "invalid GitHub repository name: $repository"
    [[ "$asset" != */* && "$checksum_asset" != */* ]] ||
        die "GitHub Release asset names must not contain slashes"

    mkdir -p -- "$(dirname -- "$output")"
    metadata="${output}.release.json.part"
    checksum_temporary="${output}.sha256.part"
    rm -f -- "$metadata" "$checksum_temporary"

    curl_args=(
        --fail --location --retry 3 --silent --show-error
        --header "Accept: application/vnd.github+json"
        --header "X-GitHub-Api-Version: 2022-11-28"
        --header "User-Agent: android-sdk-linux-aarch64-build"
    )
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl_args+=(--header "Authorization: Bearer $GITHUB_TOKEN")
    fi
    curl "${curl_args[@]}" --output "$metadata" \
        "https://api.github.com/repos/$repository/releases/latest"

    mapfile -t release_fields < <(
        python3 - "$metadata" "$asset" "$checksum_asset" <<'PY'
import json
import re
import sys

metadata, asset_name, checksum_name = sys.argv[1:]
with open(metadata, encoding="utf-8") as stream:
    release = json.load(stream)

if release.get("draft") or release.get("prerelease"):
    raise SystemExit("latest endpoint returned a draft or prerelease")
tag = release.get("tag_name")
if not isinstance(tag, str) or not tag or "\n" in tag:
    raise SystemExit("latest Release has an invalid tag_name")

assets = {item.get("name"): item for item in release.get("assets", [])}
selected = []
for name in (asset_name, checksum_name):
    item = assets.get(name)
    if not item or item.get("state") != "uploaded":
        raise SystemExit(f"latest Release {tag} has no uploaded asset named {name}")
    url = item.get("browser_download_url")
    digest = item.get("digest") or ""
    if not isinstance(url, str) or not url.startswith("https://github.com/") or "\n" in url:
        raise SystemExit(f"latest Release {tag} has an invalid URL for {name}")
    if digest and not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
        raise SystemExit(f"latest Release {tag} has an invalid digest for {name}")
    selected.append((url, digest.lower()))

print(tag)
print(selected[0][0])
print(selected[1][0])
print(selected[0][1])
print(selected[1][1])
PY
    )
    rm -f -- "$metadata"
    (( ${#release_fields[@]} == 5 )) ||
        die "could not resolve required assets from $repository latest Release"
    tag=${release_fields[0]}
    asset_url=${release_fields[1]}
    checksum_url=${release_fields[2]}
    asset_digest=${release_fields[3]#sha256:}
    checksum_digest=${release_fields[4]#sha256:}

    curl "${curl_args[@]}" --output "$checksum_temporary" "$checksum_url"
    if [[ -n "$checksum_digest" ]]; then
        actual_checksum_digest=$(sha256sum "$checksum_temporary" | awk '{print $1}')
        [[ "$actual_checksum_digest" == "$checksum_digest" ]] || {
            rm -f -- "$checksum_temporary"
            die "GitHub digest mismatch for $repository Release $tag asset $checksum_asset"
        }
    fi
    expected=$(
        python3 - "$checksum_temporary" "$asset" <<'PY'
import re
import sys

checksum_path, asset_name = sys.argv[1:]
matches = []
with open(checksum_path, encoding="utf-8") as stream:
    for line in stream:
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip("*") == asset_name:
            matches.append(fields[0].lower())
if len(matches) != 1 or not re.fullmatch(r"[0-9a-f]{64}", matches[0]):
    raise SystemExit(f"checksum asset does not contain exactly one SHA-256 for {asset_name}")
print(matches[0])
PY
    )
    if [[ -n "$asset_digest" && "$expected" != "$asset_digest" ]]; then
        rm -f -- "$checksum_temporary"
        die "Release checksum and GitHub digest disagree for $repository Release $tag"
    fi

    download_checked "$asset_url" "$output" sha256 "$expected"
    mv -- "$checksum_temporary" "${output}.sha256"
    printf -v "$result_variable" '%s' "$tag"
    echo "Resolved $repository latest Release $tag: $asset"
}

write_generic_package_xml() {
    local output="$1" path="$2" major="$3" minor="$4" micro="$5" display="$6"
    sed -e "s|@PATH@|$path|g" -e "s|@MAJOR@|$major|g" \
        -e "s|@MINOR@|$minor|g" -e "s|@MICRO@|$micro|g" \
        -e "s|@DISPLAY@|$display|g" \
        "$project_root/templates/package-generic.xml.in" > "$output"
    chmod 0644 "$output"
}

copy_google_package() {
    local archive="$1" package_path="$2" destination="$3"
    local temporary package_root
    local -a property_files
    temporary="$(mktemp -d)"
    unzip -q "$archive" -d "$temporary"
    package_root="$(find "$temporary" -type f -name source.properties -print0 | \
        while IFS= read -r -d '' properties; do
            if grep -Fqx "Pkg.Path=$package_path" "$properties" ||
               grep -Fqx "Pkg.Path = $package_path" "$properties"; then
                dirname -- "$properties"
                break
            fi
        done)"
    if [[ -z "$package_root" ]]; then
        mapfile -d '' -t property_files < <(find "$temporary" -type f -name source.properties -print0)
        if (( ${#property_files[@]} == 1 )); then
            package_root="$(dirname -- "${property_files[0]}")"
        fi
    fi
    [[ -n "$package_root" ]] || {
        rm -rf -- "$temporary"
        die "could not find $package_path inside $(basename -- "$archive")"
    }
    mkdir -p -- "$destination"
    cp -a -- "$package_root/." "$destination/"
    rm -rf -- "$temporary"
}

require_aarch64_elf() {
    local path="$1"
    file -b "$path" | grep -Eq 'ARM aarch64|AArch64' ||
        die "$path is not an AArch64 ELF"
}
