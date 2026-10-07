#!/usr/bin/env bash
# Route search time per tick for routes of 200, 1000 and 3000 tiles.
# The game is paused so on_tick never runs; every simulated tick is one RCON
# command that runs the scheduler tick inside a profiler. The chunk cache is
# dropped before each length, so every run reads its chunks.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_sandbox || exit 0
trap stop_server EXIT
start_server || exit 0

python3 - "$ROOT" <<'PY'
import os, re, socket, struct, sys

ROOT = sys.argv[1]
MAX_TICKS = 20000
CHUNK_UNITS = 300

sock = socket.create_connection(("127.0.0.1", int(os.environ["AB_RCON_PORT"])), timeout=120)

def send(i, k, b):
    p = struct.pack("<ii", i, k) + b.encode() + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(p)) + p)

def rx():
    n = struct.unpack("<i", sock.recv(4))[0]
    d = b""
    while len(d) < n:
        d += sock.recv(n - len(d))
    return d[8:-2].decode("utf8", "replace")

send(1, 3, os.environ["AB_RCON_PW"]); rx()

def run(lua):
    send(2, 2, "/silent-command __auto-belt__ " + lua.replace("\n", " "))
    return rx()

setup = open(os.path.join(ROOT, "test/bench_setup.lua")).read()
TICK = ("local p = helpers.create_profiler() AUTO_BELT.scheduler.tick() p.stop() "
        "local j = storage.jobs[storage.bench_job] "
        "rcon.print({'', p, '|', j and j.stage or 'gone', '|', j and j.effort or 0, '|', j and j.chunk_reads or 0})")

for length in (200, 1000, 3000):
    out = run("local ok, err = pcall(function() " + setup.replace("__LENGTH__", str(length)).replace("\n", " ") + " end) if not ok then rcon.print('FAIL: ' .. tostring(err)) end")
    if "FAIL" in out and "setup" not in out:
        print(f"{length} tiles: setup failed: {out.strip()}")
        continue
    times, ticks, stage, effort, reads = [], 0, "?", 0, 0
    read_ticks, quiet_ticks, prev, prev_effort, worst = [], [], 0, 0, (0, 0, "", 0, 0)
    while ticks < MAX_TICKS:
        out = run(TICK)
        m = re.search(r"([\d.]+)\s*(ms|us|µs|s)\b.*?\|(\w+)\|(\d+)\|(\d+)", out)
        if not m:
            stage = "unparsed: " + out.strip()[:80]
            break
        v = float(m.group(1)) * {"ms": 1, "us": 0.001, "µs": 0.001, "s": 1000}[m.group(2)]
        stage, effort, reads = m.group(3), int(m.group(4)), int(m.group(5))
        times.append(v)
        (read_ticks if reads > prev else quiet_ticks).append(v)
        if v >= worst[0]: worst = (v, reads - prev, stage, effort - prev_effort, ticks)
        prev, prev_effort = reads, effort
        ticks += 1
        if stage not in ("abstract", "refine"):
            break
    run("local j = storage.jobs[storage.bench_job] if j then AUTO_BELT.jobs.remove(j) end")
    if stage != "ready":
        print(f"{length} tiles: not ready ({stage}) after {ticks} ticks, highest {max(times, default=0):.3f} ms")
        continue
    exp = effort - reads * CHUNK_UNITS
    print(f"{length} tiles: {ticks} ticks to ready, highest {max(times):.3f} ms/tick, "
          f"average {sum(times) / len(times):.3f} ms/tick, {reads} chunk reads, {exp} expansions")
    avg = lambda a: sum(a) / len(a) if a else 0.0
    print(f"  ticks with chunk reads: {len(read_ticks)}, average {avg(read_ticks):.3f} ms; ticks without: {len(quiet_ticks)}, average {avg(quiet_ticks):.3f} ms; slowest tick: {worst[1]} chunk reads, {worst[3]} effort units, stage after it {worst[2]}, tick number {worst[4]}")
PY
exit 0
