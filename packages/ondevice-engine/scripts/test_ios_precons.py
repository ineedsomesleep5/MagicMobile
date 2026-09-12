#!/usr/bin/env python3
"""Validate exact Swift-exported bundled decks through real XMage create/first-prompt/destroy."""
import argparse
import json
from pathlib import Path
import time
from jvm_client import EngineProcess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
args = parser.parse_args()
names = ["token-triumph", "first-flight", "grave-danger", "chaos-incarnate", "draconic-destruction"]
with EngineProcess(timeout=60) as engine:
    for name in names:
        deck = json.loads((args.directory / (name + ".json")).read_text())
        config = {"seats": [{"seatId": f"player{n}", "name": f"Precon tester {n}",
                              "controller": "human", "deck": deck} for n in (1, 2)]}
        created = engine.call("create", configuration=config)
        match = created["matchId"]
        try:
            deadline = time.monotonic() + 30
            while True:
                state = engine.call("poll", matchId=match, viewerId="player1", after=0)
                if state["phase"] in ("failed", "ended"):
                    raise AssertionError(state.get("failure") or "Match ended before first prompt")
                if state.get("prompt"):
                    assert state["snapshot"]["schema"] == "xmage-gameview-v1"
                    print(f"PASS {name}: real Commander validation and first {state['prompt']['kind']} prompt", flush=True)
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"No initial prompt for {name}")
                time.sleep(.01)
        finally:
            engine.call("destroy", matchId=match)
print("PASS 5 bundled Swift-resolved decks; JVM only, not native gameplay")
