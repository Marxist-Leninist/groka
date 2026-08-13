#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/groka-launcher-test.XXXXXX")
trap 'rm -rf "$tmp"' 0 HUP INT TERM

mkdir -p "$tmp/bin" "$tmp/home"
cp "$repo_root/termux/groka" "$tmp/bin/groka"
chmod 700 "$tmp/bin/groka"
cat > "$tmp/bin/grok" <<'FAKE'
#!/usr/bin/env sh
printf 'workers=%s\n' "${GROK_WORKER_THREADS:-}"
printf 'rayon=%s\n' "${RAYON_NUM_THREADS:-}"
printf 'tmpdir=%s\n' "${TMPDIR:-}"
printf 'args='
printf '%s|' "$@"
printf '\n'
FAKE
chmod 700 "$tmp/bin/grok"
ln -s "$tmp/bin/groka" "$tmp/groka-link"

output=$(HOME=$tmp/home PREFIX=$tmp/prefix TMPDIR= \
    sh "$tmp/groka-link" alpha 'two words')
printf '%s\n' "$output" | grep -Fx 'workers=2' >/dev/null
printf '%s\n' "$output" | grep -Fx 'rayon=2' >/dev/null
printf '%s\n' "$output" | grep -Fx "tmpdir=$tmp/prefix/tmp" >/dev/null
printf '%s\n' "$output" | grep -Fx 'args=alpha|two words|' >/dev/null
[ -d "$tmp/prefix/tmp" ]

output=$(HOME=$tmp/home PREFIX=$tmp/prefix TMPDIR=$tmp/custom-tmp \
    GROK_WORKER_THREADS=5 RAYON_NUM_THREADS=7 \
    sh "$tmp/groka-link" beta)
printf '%s\n' "$output" | grep -Fx 'workers=5' >/dev/null
printf '%s\n' "$output" | grep -Fx 'rayon=7' >/dev/null
printf '%s\n' "$output" | grep -Fx "tmpdir=$tmp/custom-tmp" >/dev/null
printf '%s\n' "$output" | grep -Fx 'args=beta|' >/dev/null

rm "$tmp/bin/grok"
set +e
HOME=$tmp/home sh "$tmp/groka-link" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 126 ]

printf '%s\n' 'PASS: GrokA launcher'
