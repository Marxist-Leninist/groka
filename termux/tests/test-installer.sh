#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/groka-installer-test.XXXXXX")
trap 'rm -rf "$tmp"' 0 HUP INT TERM

home=$tmp/home
prefix=$tmp/prefix
fake=$tmp/fake-grok
mkdir -p "$home"
cat > "$fake" <<'FAKE'
#!/usr/bin/env sh
printf '%s\n' fake-grok
FAKE
chmod 700 "$fake"

HOME=$home sh "$repo_root/termux/install.sh" \
    --binary "$fake" \
    --prefix "$prefix" \
    --version 1.test >/dev/null

[ -L "$prefix/bin/groka" ]
[ -L "$prefix/bin/grok-android" ]
[ ! -e "$prefix/bin/grok" ]
[ "$(readlink "$prefix/bin/groka")" = "$prefix/share/groka/current/bin/groka" ]
[ "$(readlink "$prefix/bin/grok-android")" = "$prefix/share/groka/current/bin/groka" ]

expected_hash=$(sha256sum "$fake" | awk '{print $1}')
installed=$prefix/share/groka/current/bin/grok
[ "$(sha256sum "$installed" | awk '{print $1}')" = "$expected_hash" ]
grep -F "binary_sha256=$expected_hash" \
    "$prefix/share/groka/current/install-manifest.txt" >/dev/null

# Reinstalling the same verified artifact is idempotent and preserves launchers.
HOME=$home sh "$repo_root/termux/install.sh" \
    --binary "$fake" \
    --prefix "$prefix" \
    --version 1.test >/dev/null
backup_count=$(find "$prefix/share/groka/launcher-backups" -mindepth 1 -maxdepth 1 | wc -l)
[ "$backup_count" -ge 2 ]

# An existing version directory with the same name but different bytes is fatal.
hash_short=$(printf '%.12s' "$expected_hash")
corrupt_root=$prefix/share/groka/versions/2.test-$hash_short
mkdir -p "$corrupt_root/bin"
printf '%s\n' corrupt > "$corrupt_root/bin/grok"
chmod 700 "$corrupt_root/bin/grok"
if HOME=$home sh "$repo_root/termux/install.sh" \
    --binary "$fake" \
    --prefix "$prefix" \
    --version 2.test >/dev/null 2>&1; then
    printf '%s\n' 'installer accepted a corrupt existing version directory' >&2
    exit 1
fi

printf '%s\n' 'PASS: GrokA installer'
