#!/usr/bin/env bash
# Route search time per tick. Runs: east routes of 200, 1000 and 3000 tiles
# with a cold chunk cache, the 1000-tile route again with a warm cache, and a
# 1000-tile route running south. The game is paused so on_tick never runs;
# every simulated tick is one RCON command that runs the scheduler tick inside
# a profiler.
# The search budget is the mod's default; BENCH_BUDGET=<units> overrides it.
# The map's own value is restored afterwards. BENCH_ONLY=<text> runs only the
# runs whose name contains the text (the warm run needs its cold run first).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

setup_sandbox || exit 1
trap stop_server EXIT
start_server || exit 1

python3 -u - "$ROOT" <<'PY'
import os, re, socket, struct, sys

ROOT = sys.argv[1]
MAX_TICKS = 200000
RUNS = [  # name, length, south, warm
    ("200 east", 200, False, False),
    ("1000 east", 1000, False, False),
    ("1000 east warm", 1000, False, True),
    ("1000 south", 1000, True, False),
    ("3000 east", 3000, False, False),
]
ONLY = os.environ.get("BENCH_ONLY", "")
BUDGET = os.environ.get("BENCH_BUDGET", "")

sock = socket.create_connection(("127.0.0.1", int(os.environ["AB_RCON_PORT"])), timeout=600)

def recv_exact(n):
    d = b""
    while len(d) < n:
        part = sock.recv(n - len(d))
        if not part:
            raise ConnectionError("rcon connection closed")
        d += part
    return d

def send(i, k, b):
    p = struct.pack("<ii", i, k) + b.encode() + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(p)) + p)

def rx():
    n = struct.unpack("<i", recv_exact(4))[0]
    return recv_exact(n)[8:-2].decode("utf8", "replace")

send(1, 3, os.environ["AB_RCON_PW"]); rx()

def run(lua):
    send(2, 2, "/silent-command __auto-belt__ " + lua.replace("\n", " "))
    return rx()

CHUNK_UNITS, REGION_UNITS = (int(v) for v in run(
    "rcon.print(AUTO_BELT.grid.CHUNK_UNITS .. ' ' .. AUTO_BELT.grid.REGION_UNITS)").split())
# The map keeps the budget it was saved with; the bench runs the mod's default.
saved_budget = run("rcon.print(settings.global['auto-belt-search-budget'].value)").strip()
default_budget = run("rcon.print(prototypes.mod_setting['auto-belt-search-budget'].default_value)").strip()
run(f"settings.global['auto-belt-search-budget'] = {{value = {int(BUDGET or default_budget)}}}")
budget = run("rcon.print(settings.global['auto-belt-search-budget'].value)").strip()
print(f"search budget {budget}, chunk read {CHUNK_UNITS} units, region build {REGION_UNITS} units")

# Commands go on one line, so comments are dropped first.
setup = re.sub(r"--[^\n]*", "", open(os.path.join(ROOT, "test/bench_setup.lua")).read())
# The search tables are read before and after the tick, so the counts of a
# search that ends during the tick are still seen.
TICK = ("local j = storage.jobs[storage.bench_job] "
        "local s0, a0 = j and j.search, j and j.abstract "
        "local p = helpers.create_profiler() AUTO_BELT.scheduler.tick() p.stop() "
        "local s1, a1 = j and j.search, j and j.abstract "
        "local function n(t, k) return t and t[k] or 0 end "
        "local rest = table.concat({j and j.stage or 'gone', j and j.effort or 0, j and j.chunk_reads or 0, "
        "j and j.region_builds or 0, tostring(s0), n(s0, 'expansions'), n(s0, 'stale_pops'), "
        "tostring(s1), n(s1, 'expansions'), n(s1, 'stale_pops'), "
        "tostring(a0), n(a0, 'expansions'), tostring(a1), n(a1, 'expansions')}, '|') "
        "rcon.print({'', p, '|' .. rest})")
PAT = re.compile(r"([\d.]+)\s*(ms|us|µs|s)\b.*?\|(\w+)\|(\d+)\|(\d+)\|(\d+)\|([^|]*)\|(\d+)\|(\d+)\|([^|]*)\|(\d+)\|(\d+)\|([^|]*)\|(\d+)\|([^|]*)\|(\d+)")

def lua_bool(v):
    return "true" if v else "false"

def bench():
    for name, length, south, warm in RUNS:
        if ONLY and ONLY not in name:
            continue
        body = (setup.replace("__LENGTH__", str(length)).replace("__NS__", lua_bool(south))
                .replace("__WARM__", lua_bool(warm)).replace("\n", " "))
        out = run("local ok, err = pcall(function() " + body + " end) if not ok then rcon.print('FAIL: ' .. tostring(err)) end")
        if not out.strip().startswith("setup "):
            raise RuntimeError(f"{name}: setup failed: {out.strip()}")
        times, ticks, stage, effort, reads, builds = [], 0, "?", 0, 0, 0
        read_ticks, quiet_ticks, prev, prev_builds, prev_effort, worst = [], [], 0, 0, 0, (0, 0, "", 0, 0)
        quiet_units = 0
        refine_counts, abstract_counts = {}, {}
        while ticks < MAX_TICKS:
            out = run(TICK)
            m = PAT.search(out)
            if not m:
                stage = "unparsed: " + out.strip()[:120]
                break
            v = float(m.group(1)) * {"ms": 1, "us": 0.001, "µs": 0.001, "s": 1000}[m.group(2)]
            stage, effort, reads, builds = m.group(3), int(m.group(4)), int(m.group(5)), int(m.group(6))
            for ref, e, st in ((m.group(7), m.group(8), m.group(9)), (m.group(10), m.group(11), m.group(12))):
                if ref != "nil":
                    refine_counts[ref] = (int(e), int(st))
            for ref, e in ((m.group(13), m.group(14)), (m.group(15), m.group(16))):
                if ref != "nil":
                    abstract_counts[ref] = int(e)
            times.append(v)
            if reads > prev or builds > prev_builds:
                read_ticks.append(v)
            else:
                quiet_ticks.append(v)
                quiet_units += effort - prev_effort
            if v >= worst[0]: worst = (v, reads - prev, stage, effort - prev_effort, ticks)
            prev, prev_builds, prev_effort = reads, builds, effort
            ticks += 1
            if stage not in ("abstract", "refine"):
                break
        run("local j = storage.jobs[storage.bench_job] if j then AUTO_BELT.jobs.remove(j) end")
        if stage != "ready":
            raise RuntimeError(f"{name}: not ready ({stage}) after {ticks} ticks, highest {max(times, default=0):.3f} ms")
        exp = sum(e for e, _ in refine_counts.values()) + sum(abstract_counts.values())
        stale = sum(s for _, s in refine_counts.values())
        avg = lambda a: sum(a) / len(a) if a else 0.0
        print(f"{name}: {ticks} ticks to ready, highest {max(times):.3f} ms/tick, "
              f"average {avg(times):.3f} ms/tick, total {sum(times):.1f} ms, {reads} chunk reads, {builds} region builds, "
              f"{exp} expansions, {stale} stale pops, {effort} units")
        per_unit = sum(quiet_ticks) / quiet_units * 1000 if quiet_units else 0.0
        print(f"  ticks with reads or builds: {len(read_ticks)}, average {avg(read_ticks):.3f} ms; ticks without: {len(quiet_ticks)}, "
              f"average {avg(quiet_ticks):.3f} ms, {per_unit:.2f} us/unit; slowest tick: {worst[1]} chunk reads, "
              f"{worst[3]} effort units, stage after it {worst[2]}, tick number {worst[4]}")

try:
    bench()
    body = (setup.replace("__LENGTH__", "1000").replace("__NS__", "false")
            .replace("__WARM__", "false"))
    out = run(body)
    if not out.strip().startswith("setup "):
        raise RuntimeError(f"calibration setup failed: {out.strip()}")
    run("local j = storage.jobs[storage.bench_job] AUTO_BELT.jobs.remove(j)")
    out = run("local s = game.surfaces['auto-belt-bench'] "
              "local p = helpers.create_profiler() "
              "for cx = 1, 20 do AUTO_BELT.grid.read_chunk(s, cx, 0) end "
              "p.stop() rcon.print({'', '20 chunk reads: ', p}) "
              "p = helpers.create_profiler() "
              "for cx = 1, 20 do AUTO_BELT.grid.build_regions(s.index, cx, 0) end "
              "p.stop() rcon.print({'', '20 region builds: ', p})")
    if not all(re.search(label + r":\s*(?:Duration:\s*)?[\d.]+\s*(?:ms|us|µs|s)\b", out)
               for label in ("20 chunk reads", "20 region builds")):
        raise RuntimeError(f"calibration failed: {out.strip()}")
    print(out.strip())
finally:
    # The server saves the map on exit: leave it running for the engine cases.
    run(f"settings.global['auto-belt-search-budget'] = {{value = {int(saved_budget)}}} "
        "game.tick_paused = false storage.bench_job = nil")
PY
