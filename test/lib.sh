#!/usr/bin/env bash
# Shared helpers for the Auto Belt test harness.
# Never touches the live server: own port, own rcon port, own mod dir, own map.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/test/.work"
FACTORIO="${FACTORIO:-$WORK/engine/factorio/bin/x64/factorio}"
MODS="$WORK/mods"
MAP="${AUTO_BELT_TEST_MAP:-$WORK/test-map.zip}"
PORT=34199
export AB_RCON_PORT=27017
export AB_RCON_PW=autobelt
SERVER_PID=""
PACKAGE_PATH=""

setup_sandbox() {
  if [ ! -x "$FACTORIO" ]; then
    echo "Missing isolated Factorio executable: $FACTORIO"
    echo "Install a separate test engine under test/.work/engine, or set FACTORIO explicitly."
    return 1
  fi
  # game.server_save() fails on a fresh checkout without the saves directory.
  mkdir -p "$WORK" "$MODS" "$WORK/saves"
  trap stop_server EXIT
  # A second installed version can silently take precedence over the test target.
  local entry
  for entry in "$MODS"/auto-belt "$MODS"/auto-belt_*; do
    if [ -L "$entry" ] || [[ "$entry" == *.zip && -f "$entry" ]]; then
      rm -f "$entry"
    elif [ -e "$entry" ]; then
      echo "Conflicting unpacked test mod: $entry" >&2
      return 1
    fi
  done
  if [ -n "${AB_TEST_ZIP:-}" ]; then
    local package_name
    package_name="$(python3 - "$AB_TEST_ZIP" <<'PYZIP'
import json, re, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    infos = [name for name in archive.namelist() if name.endswith("/info.json")]
    assert len(infos) == 1, "expected one mod info.json"
    info = json.loads(archive.read(infos[0]))
    assert info["name"] == "auto-belt"
    assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", info["version"])
    name = "auto-belt_" + info["version"]
    assert infos[0] == name + "/info.json"
    assert all(path.startswith(name + "/") for path in archive.namelist())
    assert archive.testzip() is None
    print(name + ".zip")
PYZIP
)"
    PACKAGE_PATH="$MODS/$package_name"
    cp -- "$AB_TEST_ZIP" "$PACKAGE_PATH"
  else
    ln -sfn "$ROOT" "$MODS/auto-belt"
  fi
  cat > "$WORK/config.ini" <<EOF
[path]
read-data=__PATH__executable__/../../data
write-data=$WORK
[general]
locale=auto
EOF
  if [ ! -f "$MAP" ]; then
    "$FACTORIO" --config "$WORK/config.ini" --mod-directory "$MODS" \
      --create "$MAP" >"$WORK/create.log" 2>&1
  fi
}

start_server() {
  # Refuse occupied ports before starting. Never send RCON commands to an
  # already-running process, and never stop a process this harness did not start.
  python3 - "$PORT" "$AB_RCON_PORT" <<'PY'
import socket, sys
for port, kind in [(int(sys.argv[1]), socket.SOCK_DGRAM), (int(sys.argv[2]), socket.SOCK_STREAM)]:
    with socket.socket(socket.AF_INET, kind) as sock:
        sock.bind(("0.0.0.0", port))
PY
  if [ "$?" -ne 0 ]; then return 1; fi
  "$FACTORIO" --config "$WORK/config.ini" --mod-directory "$MODS" \
    --start-server "$MAP" --server-settings "$ROOT/test/server-settings.json" \
    --port "$PORT" --rcon-bind 127.0.0.1:$AB_RCON_PORT --rcon-password "$AB_RCON_PW" \
    >"$WORK/server.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 60); do
    if grep -q "Starting RCON interface" "$WORK/server.log" 2>/dev/null; then
      # A fresh disposable map consumes the first console command to confirm
      # disabling achievements. Prime with a harmless command before tests.
      python3 "$ROOT/test/rcon.py" "/silent-command rcon.print('test-ready')" >/dev/null
      [[ "$(python3 "$ROOT/test/rcon.py" "/silent-command rcon.print('test-ready')")" == "test-ready" ]]
      return $?
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "SERVER DIED ON STARTUP:"; tail -20 "$WORK/server.log"; return 1
    fi
    sleep 1
  done
  echo "SERVER DID NOT START:"; tail -20 "$WORK/server.log"; return 1
}

stop_server() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
  if [ -n "$PACKAGE_PATH" ]; then
    rm -f "$PACKAGE_PATH"
    PACKAGE_PATH=""
  fi
  if [ -d "$MODS" ] && [ ! -e "$MODS/auto-belt" ]; then
    ln -sfn "$ROOT" "$MODS/auto-belt"
  fi
}

mod_version() {
  python3 - "$ROOT/info.json" "$PACKAGE_PATH" <<'PYVERSION'
import json, sys, zipfile
if sys.argv[2]:
    with zipfile.ZipFile(sys.argv[2]) as archive:
        name = next(name for name in archive.namelist() if name.endswith("/info.json"))
        info = json.loads(archive.read(name))
else:
    with open(sys.argv[1]) as source:
        info = json.load(source)
print(info["version"])
PYVERSION
}

# run_case <file> -> prints PASS/FAIL line, returns 0/1
run_case() {
  local f="$1" name body out attempt
  name="$(basename "$f" .lua)"
  body="$(tr '\n' ' ' < "$f")"
  # Cases compare against __MOD_VERSION__, so a release needs no test edits.
  body="${body//__MOD_VERSION__/$(mod_version)}"
  # Combat tests need real engine ticks between assertions. WAIT is bounded
  # (600 tries, about 60 s or 3600 ticks, for long routes) and explicit;
  # a timeout fails rather than silently skipping the case.
  for attempt in $(seq 1 600); do
    out="$(python3 "$ROOT/test/rcon.py" "/silent-command __auto-belt__ local ok, result = pcall(function() $body end) rcon.print(ok and (result or 'PASS') or ('FAIL: ' .. tostring(result)))")"
    if [[ "$out" != WAIT:* ]]; then break; fi
    sleep 0.1
  done
  case "$out" in
    PASS*) echo "$out  $name"; return 0 ;;
    SKIP*) echo "$out" | sed "s/^/SKIP  $name: /"; return 2 ;;
    *)     echo "$out" | sed "s/^/FAIL  $name: /"; return 1 ;;
  esac
}
