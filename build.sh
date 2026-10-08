#!/usr/bin/env bash
# Package committed mod files for the Factorio portal.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REV="$(git -C "$ROOT" rev-parse HEAD)"
PACKAGED=(info.json thumbnail.png data.lua settings.lua control.lua changelog.txt
  README.md LICENSE prototypes scripts locale)
VERSION="$(git -C "$ROOT" show "$REV:info.json" | python3 -c '
import json, re, sys
info = json.load(sys.stdin)
assert info["name"] == "auto-belt"
assert info["factorio_version"] == "2.0"
version = info["version"]
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), version
print(version)
')"
mkdir -p "$ROOT/dist"
STAGE="$(mktemp -d)"
TMP_OUT=""
cleanup() {
  rm -rf "$STAGE"
  if [ -n "$TMP_OUT" ]; then rm -f "$TMP_OUT"; fi
}
trap cleanup EXIT
OUT="$ROOT/dist/auto-belt_$VERSION.zip"
TMP_OUT="$(mktemp "$ROOT/dist/.auto-belt_$VERSION.XXXXXX")"
DEST="$STAGE/auto-belt_$VERSION"
mkdir -p "$DEST"
if [ -n "$(git -C "$ROOT" status --porcelain -- "${PACKAGED[@]}")" ]; then
  echo "warning: uncommitted changes are left out of the package:" >&2
  git -C "$ROOT" status --short -- "${PACKAGED[@]}" >&2
fi
git -C "$ROOT" archive --format=tar "$REV" -- "${PACKAGED[@]}" | tar -x -C "$DEST"
python3 - "$ROOT" "$REV" "$STAGE" "$TMP_OUT" "$VERSION" "${PACKAGED[@]}" <<'PY'
import pathlib
import subprocess
import sys
import zipfile

root, rev, stage, output, version, *packaged = sys.argv[1:]
prefix = f"auto-belt_{version}/"
manifest = subprocess.check_output(
    ["git", "-C", root, "ls-tree", "-r", "--name-only", "-z", rev, "--", *packaged]
).decode().split("\0")[:-1]
for path in packaged:
    assert any(name == path or name.startswith(path + "/") for name in manifest), path
expected = {prefix + name for name in manifest}
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(manifest):
        archive.write(pathlib.Path(stage, prefix, name), prefix + name)
with zipfile.ZipFile(output) as archive:
    names = archive.namelist()
    assert len(names) == len(expected) and set(names) == expected, "package manifest mismatch"
    assert archive.testzip() is None, "corrupt package member"
    for name in manifest:
        committed = subprocess.check_output(["git", "-C", root, "show", f"{rev}:{name}"])
        assert archive.read(prefix + name) == committed, name
print("package ok")
PY
mv -f "$TMP_OUT" "$OUT"
echo "$OUT"
