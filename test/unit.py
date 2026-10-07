#!/usr/bin/env python3
"""Run the pure Lua unit tests without a Factorio installation.

Usage: python3 test/unit.py [-v] [FILTER]
Prints failures and a summary. FILTER runs only tests whose name contains it.
Requires lupa (pip install lupa), or a local copy under test/.work/python.
"""
from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "test/.work/python"))
try:
    from lupa.lua52 import LuaRuntime, LuaError
except ImportError:
    sys.exit("Install lupa to run the unit tests.")
os.chdir(ROOT)
lua = LuaRuntime(unpack_returned_tuples=True)
args = sys.argv[1:]
if "-v" in args:
    args.remove("-v")
    lua.globals().UNIT_VERBOSE = True
if len(args) > 1:
    sys.exit("usage: python3 test/unit.py [-v] [FILTER]")
if args:
    lua.globals().UNIT_FILTER = args[0]
try:
    lua.execute((ROOT / "test/unit.lua").read_text())
except LuaError as error:
    print(error)
    sys.exit(1)
