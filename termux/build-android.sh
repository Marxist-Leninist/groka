#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

target=aarch64-linux-android
api=${ANDROID_API:-28}

find_ndk() {
    local candidate
    for candidate in \
        "${ANDROID_NDK_HOME:-}" \
        "${ANDROID_NDK_ROOT:-}"; do
        if [[ -n "$candidate" && -d "$candidate/toolchains/llvm/prebuilt/linux-x86_64" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    for candidate in \
        "${ANDROID_HOME:-}/ndk" \
        "${ANDROID_SDK_ROOT:-}/ndk" \
        /opt/android-sdk/ndk \
        "$HOME/Android/Sdk/ndk"; do
        [[ -d "$candidate" ]] || continue
        local latest
        latest=$(find "$candidate" -mindepth 1 -maxdepth 1 -type d -print | sort -V | tail -n 1)
        if [[ -n "$latest" && -d "$latest/toolchains/llvm/prebuilt/linux-x86_64" ]]; then
            printf '%s\n' "$latest"
            return 0
        fi
    done
    return 1
}

ndk=$(find_ndk) || {
    printf '%s\n' 'Android NDK not found. Set ANDROID_NDK_HOME to an installed NDK.' >&2
    exit 69
}
toolchain=$ndk/toolchains/llvm/prebuilt/linux-x86_64
linker=$toolchain/bin/aarch64-linux-android${api}-clang
cxx=$toolchain/bin/aarch64-linux-android${api}-clang++

[[ -x "$linker" ]] || { printf 'Missing NDK linker: %s\n' "$linker" >&2; exit 69; }
[[ -x "$cxx" ]] || { printf 'Missing NDK C++ linker: %s\n' "$cxx" >&2; exit 69; }

# Non-interactive Android/CI shells sometimes omit rustup's default bin path.
if ! command -v rustup >/dev/null 2>&1 && [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi
command -v rustup >/dev/null 2>&1 || { printf '%s\n' 'rustup is required.' >&2; exit 69; }
command -v cargo >/dev/null 2>&1 || { printf '%s\n' 'cargo is required.' >&2; exit 69; }

toolchain_version=$(sed -n 's/^[[:space:]]*channel = "\([^"]*\)"/\1/p' rust-toolchain.toml | head -n 1)
[[ -n "$toolchain_version" ]] || { printf '%s\n' 'Could not read rust-toolchain.toml.' >&2; exit 65; }
rustup toolchain install "$toolchain_version" --profile minimal
rustup target add "$target" --toolchain "$toolchain_version"

export CC_aarch64_linux_android=$linker
export CXX_aarch64_linux_android=$cxx
export AR_aarch64_linux_android=$toolchain/bin/llvm-ar
export RANLIB_aarch64_linux_android=$toolchain/bin/llvm-ranlib
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$linker
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR=$toolchain/bin/llvm-ar
export CARGO_INCREMENTAL=0
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-8}
target_dir=${CARGO_TARGET_DIR:-$repo_root/target}
case $target_dir in
    /*) ;;
    *) target_dir=$repo_root/$target_dir ;;
esac
export CARGO_TARGET_DIR=$target_dir

# The upstream release build embeds ripgrep, but upstream publishes no Android
# archive. Build the exact version expected by xai-grok-tools for the same NDK
# target and pass it through the crate's supported local-binary override.
if [[ -z ${GROK_TOOLS_BUNDLE_RG_PATH:-} ]]; then
    rg_version=15.0.0
    rg_root=$target_dir/android-tools/ripgrep-$rg_version-$target
    rg_binary=$rg_root/bin/rg
    if [[ ! -x "$rg_binary" ]]; then
        CARGO_TARGET_DIR=$target_dir/android-tools-build/ripgrep-$rg_version-$target \
            cargo "+$toolchain_version" install ripgrep \
                --version "$rg_version" \
                --locked \
                --target "$target" \
                --root "$rg_root"
    fi
    rg_machine=$($toolchain/bin/llvm-readelf -h "$rg_binary" | \
        sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
    [[ "$rg_machine" == *AArch64* ]] || {
        printf 'Unexpected ripgrep ELF machine: %s\n' "$rg_machine" >&2
        exit 70
    }
    export GROK_TOOLS_BUNDLE_RG_PATH=$rg_binary
fi

# xai-grok-tools and xai-grok-shell have separate release build scripts for
# the same embedded ripgrep payload. Feed both from the one verified Android
# binary so neither can fall back to a GNU/Linux download.
if [[ -z ${GROK_SHELL_BUNDLE_RG_PATH:-} ]]; then
    export GROK_SHELL_BUNDLE_RG_PATH=$GROK_TOOLS_BUNDLE_RG_PATH
fi

cargo "+$toolchain_version" build \
    --release \
    --locked \
    --package xai-grok-pager-bin \
    --target "$target" \
    --no-default-features

binary=$target_dir/$target/release/xai-grok-pager
[[ -x "$binary" ]] || { printf 'Expected binary was not produced: %s\n' "$binary" >&2; exit 70; }

machine=$($toolchain/bin/llvm-readelf -h "$binary" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
[[ "$machine" == *AArch64* ]] || { printf 'Unexpected ELF machine: %s\n' "$machine" >&2; exit 70; }

version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' \
    crates/codegen/xai-grok-pager-bin/Cargo.toml | head -n 1)
package_name=groka-$version-android-arm64
dist_dir=$repo_root/dist
stage=$dist_dir/$package_name
archive=$dist_dir/$package_name.tar.gz
rm -rf "$stage" "$archive" "$archive.sha256"
mkdir -p "$stage/bin"
cp "$binary" "$stage/bin/grok"
cp termux/groka "$stage/bin/groka"
cp termux/install.sh "$stage/install.sh"
cp termux/README.md "$stage/README.md"
cp LICENSE "$stage/LICENSE"
cp THIRD-PARTY-NOTICES "$stage/THIRD-PARTY-NOTICES"
cp third_party/NOTICE "$stage/THIRD-PARTY-COMPONENT-NOTICE"
cp SOURCE_REV "$stage/SOURCE_REV"
printf '%s\n' "$version" > "$stage/VERSION"
source_commit=$(git rev-parse HEAD 2>/dev/null || printf '%s' unknown)
source_state=clean
if ! git diff --quiet --ignore-submodules -- || \
   ! git diff --cached --quiet --ignore-submodules -- || \
   [[ -n $(git ls-files --others --exclude-standard) ]]; then
    source_state=dirty
fi
{
    printf 'git_commit=%s\n' "$source_commit"
    printf 'working_tree=%s\n' "$source_state"
    printf 'target=%s\n' "$target"
    printf 'android_api=%s\n' "$api"
    printf 'rust_toolchain=%s\n' "$toolchain_version"
    printf 'android_ndk=%s\n' "$(basename "$ndk")"
} > "$stage/BUILD-SOURCE"
chmod 700 "$stage/bin/grok" "$stage/bin/groka" "$stage/install.sh"
chmod 600 \
    "$stage/README.md" \
    "$stage/LICENSE" \
    "$stage/THIRD-PARTY-NOTICES" \
    "$stage/THIRD-PARTY-COMPONENT-NOTICE" \
    "$stage/SOURCE_REV" \
    "$stage/VERSION" \
    "$stage/BUILD-SOURCE"

if [[ ${GROKA_STRIP:-1} != 0 ]]; then
    "$toolchain/bin/llvm-strip" --strip-unneeded "$stage/bin/grok"
fi

(
    cd "$stage"
    sha256sum \
        bin/grok \
        bin/groka \
        install.sh \
        README.md \
        LICENSE \
        THIRD-PARTY-NOTICES \
        THIRD-PARTY-COMPONENT-NOTICE \
        SOURCE_REV \
        VERSION \
        BUILD-SOURCE > SHA256SUMS
)

epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || date +%s)}
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
    -C "$dist_dir" -cf - "$package_name" | gzip -n > "$archive"
(
    cd "$dist_dir"
    archive_name=$(basename "$archive")
    sha256sum "$archive_name" > "$archive_name.sha256"
)

printf 'Android binary: %s\n' "$binary"
printf 'Package: %s\n' "$archive"
printf 'Package SHA-256: '
awk '{print $1}' "$archive.sha256"
