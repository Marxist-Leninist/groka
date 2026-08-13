#!/system/bin/sh
set -eu

usage() {
    cat <<'USAGE'
Usage: install.sh [--binary PATH] [--prefix PATH] [--version VERSION]

Install the native Android ARM64 GrokA build without replacing the official
`grok` command. The installed commands are `groka` and `grok-android`.
USAGE
}

script_path=$0
while [ -L "$script_path" ]; do
    link_target=$(readlink "$script_path")
    case $link_target in
        /*) script_path=$link_target ;;
        *) script_path=$(dirname "$script_path")/$link_target ;;
    esac
done
script_dir=$(CDPATH= cd -- "$(dirname -- "$script_path")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." 2>/dev/null && pwd || printf '%s' "$script_dir")

binary=
prefix=${HOME:?HOME must be set}/.local
version=

while [ "$#" -gt 0 ]; do
    case $1 in
        --binary)
            [ "$#" -ge 2 ] || { printf '%s\n' '--binary requires a path' >&2; exit 64; }
            binary=$2
            shift 2
            ;;
        --prefix)
            [ "$#" -ge 2 ] || { printf '%s\n' '--prefix requires a path' >&2; exit 64; }
            prefix=$2
            shift 2
            ;;
        --version)
            [ "$#" -ge 2 ] || { printf '%s\n' '--version requires a value' >&2; exit 64; }
            version=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [ -z "$binary" ]; then
    if [ -x "$script_dir/bin/grok" ]; then
        binary=$script_dir/bin/grok
    elif [ -x "$repo_root/target/aarch64-linux-android/release/xai-grok-pager" ]; then
        binary=$repo_root/target/aarch64-linux-android/release/xai-grok-pager
    else
        printf '%s\n' 'No native Android binary found. Pass --binary PATH or run termux/build-android.sh.' >&2
        exit 66
    fi
fi

if [ ! -f "$binary" ] || [ ! -x "$binary" ]; then
    printf 'Native Android binary is missing or not executable: %s\n' "$binary" >&2
    exit 66
fi

if [ -f "$script_dir/bin/groka" ]; then
    launcher_source=$script_dir/bin/groka
else
    launcher_source=$script_dir/groka
fi
if [ ! -f "$launcher_source" ]; then
    printf 'GrokA launcher is missing: %s\n' "$launcher_source" >&2
    exit 66
fi

if [ -z "$version" ] && [ -f "$script_dir/VERSION" ]; then
    version=$(sed -n '1p' "$script_dir/VERSION")
fi
if [ -z "$version" ] && [ -f "$repo_root/crates/codegen/xai-grok-pager-bin/Cargo.toml" ]; then
    version=$(sed -n 's/^version = "\([^"]*\)"/\1/p' \
        "$repo_root/crates/codegen/xai-grok-pager-bin/Cargo.toml" | sed -n '1p')
fi
version=${version:-unknown}
case $version in
    ''|*[!A-Za-z0-9._+-]*)
        printf 'Unsafe version value: %s\n' "$version" >&2
        exit 65
        ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
    binary_sha256=$(sha256sum "$binary" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    binary_sha256=$(shasum -a 256 "$binary" | awk '{print $1}')
else
    printf '%s\n' 'sha256sum or shasum is required for verified installation.' >&2
    exit 69
fi
hash_short=$(printf '%.12s' "$binary_sha256")
release_id=$version-$hash_short

umask 077
share_root=$prefix/share/groka
versions_dir=$share_root/versions
install_root=$versions_dir/$release_id
current_link=$share_root/current
bin_dir=$prefix/bin
backup_dir=$share_root/launcher-backups
mkdir -p "$versions_dir" "$bin_dir" "$backup_dir"

cleanup_path=
cleanup() {
    if [ -n "${cleanup_path:-}" ]; then
        rm -rf "$cleanup_path"
    fi
}
trap cleanup 0 HUP INT TERM

if [ -e "$install_root" ]; then
    if [ ! -x "$install_root/bin/grok" ]; then
        printf 'Existing install is incomplete: %s\n' "$install_root" >&2
        exit 73
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        existing_sha256=$(sha256sum "$install_root/bin/grok" | awk '{print $1}')
    else
        existing_sha256=$(shasum -a 256 "$install_root/bin/grok" | awk '{print $1}')
    fi
    if [ "$existing_sha256" != "$binary_sha256" ]; then
        printf 'Existing install hash mismatch: %s\n' "$install_root" >&2
        exit 74
    fi
else
    cleanup_path=$versions_dir/.$release_id.$$
    rm -rf "$cleanup_path"
    mkdir -p "$cleanup_path/bin"
    cp "$binary" "$cleanup_path/bin/grok"
    cp "$launcher_source" "$cleanup_path/bin/groka"
    chmod 700 "$cleanup_path/bin/grok" "$cleanup_path/bin/groka"
    {
        printf 'version=%s\n' "$version"
        printf 'binary_sha256=%s\n' "$binary_sha256"
        printf 'installed_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    } > "$cleanup_path/install-manifest.txt"
    mv "$cleanup_path" "$install_root"
    cleanup_path=
fi

if [ -e "$current_link" ] && [ ! -L "$current_link" ]; then
    printf 'Refusing to replace non-symlink path: %s\n' "$current_link" >&2
    exit 73
fi
candidate=$share_root/.current.$$
rm -f "$candidate"
ln -s "$install_root" "$candidate"
mv -f "$candidate" "$current_link"

timestamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%s)
activate_launcher() {
    name=$1
    destination=$bin_dir/$name
    target=$current_link/bin/groka

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        backup=$backup_dir/$name.$timestamp.$$
        if ! cp -P "$destination" "$backup" 2>/dev/null; then
            cp "$destination" "$backup"
        fi
        printf 'Preserved previous launcher: %s\n' "$backup"
    fi

    launcher_candidate=$bin_dir/.$name.$$
    rm -f "$launcher_candidate"
    ln -s "$target" "$launcher_candidate"
    mv -f "$launcher_candidate" "$destination"
}

activate_launcher groka
activate_launcher grok-android

printf 'Installed GrokA %s\n' "$version"
printf 'Binary SHA-256: %s\n' "$binary_sha256"
printf 'Native binary: %s\n' "$install_root/bin/grok"
printf 'Run: %s\n' "$bin_dir/groka"
case :${PATH:-}: in
    *:$bin_dir:*) ;;
    *) printf 'Add this to PATH: export PATH="%s:$PATH"\n' "$bin_dir" ;;
esac
