#!/usr/bin/env python3
"""Bounded production-protocol lifecycle matrix; seeds control the driver, not XMage RNG."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import random
import signal
import subprocess
import sys
import time
import uuid

from jvm_client import EngineProcess, ROOT

SEEDS = (1907, 2909)
CONFIGURATIONS = ((2, 0), (4, 0), (2, 1), (3, 2), (4, 3))


def cached_identity(root=ROOT):
    """Fingerprint cached bytes, never assert that they were built from Git HEAD.

    Ordered classpath entry digests cover classes/resources and complete jars.
    Paths and file contents are not included in the public receipt.
    """
    def digest(path):
        value = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                value.update(block)
        return value.hexdigest()

    classpath = (root / 'build/runtime-classpath.txt').read_text().strip()
    entries = []
    for entry in classpath.split(os.pathsep):
        if not entry or '*' in entry:
            raise ValueError('Explicit cached classpath entries required')
        path = Path(entry)
        if not path.is_absolute():
            path = Path.cwd() / path
        if path.is_dir():
            files = sorted(p for p in path.rglob('*') if p.is_file())
            snapshot = hashlib.sha256()
            for file in files:
                snapshot.update(json.dumps([file.relative_to(path).as_posix(), digest(file)]).encode() + b'\n')
            entries.append({'kind': 'directory', 'files': len(files), 'sha256': snapshot.hexdigest()})
        else:
            entries.append({'kind': 'file', 'sha256': digest(path)})
    try:
        checkout_root = subprocess.check_output(
            ['git', 'rev-parse', '--show-toplevel'], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
        # An exported candidate may sit beneath another checkout. Do not attribute
        # its modified bytes to that enclosing repository.
        observed_head = None
        if Path(checkout_root).resolve() == root.resolve().parents[1]:
            observed_head = subprocess.check_output(
                ['git', 'rev-parse', 'HEAD'], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        observed_head = None
    return {'sourceIdentity': 'unverified-cached-class-source',
            'scope': 'Cached bytes before execution; association with checkout source is unverified',
            'observedCheckoutHEAD': observed_head,
            'driverSHA256': digest(Path(__file__)),
            'classpathSHA256': hashlib.sha256(classpath.encode()).hexdigest(),
            'classSnapshotSHA256': hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest(),
            'entries': entries}


def run_owned(command, timeout):
    """Own one isolated driver/JVM group; reserve cleanup inside the time budget."""
    if timeout <= 5:
        raise subprocess.TimeoutExpired(command, timeout)
    deadline = time.monotonic() + timeout
    process = None
    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}

    def cancelled(signum, frame):
        raise KeyboardInterrupt('Scenario parent cancelled')

    try:
        for sig in previous:
            signal.signal(sig, cancelled)
        process = subprocess.Popen(command, start_new_session=True)
        return process.wait(timeout=max(0, deadline - time.monotonic() - 5))
    finally:
        # A second cancellation must not interrupt cleanup. The group can still
        # contain a JVM after the driver exits normally or abnormally.
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        try:
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=min(5, max(0, deadline - time.monotonic())))
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)


def configuration(base, seats, ai, seed):
    rng = random.Random(seed)
    result = {"seats": []}
    for index in range(seats):
        seat = copy.deepcopy(base["seats"][index % len(base["seats"])])
        seat.update(seatId=f"seat-{index}", name=f"Soak {index}",
                    controller="human" if index < seats - ai else "ai")
        rng.shuffle(seat["deck"]["main"])
        result["seats"].append(seat)
    return result


def answer(prompt, snapshot, rng):
    """Only explicit legal options from the current authorized prompt are selected."""
    kind, payload = prompt["kind"], prompt["payload"]
    if kind == "PICK_TARGET":
        candidates = payload["candidates"]
        if not candidates:
            raise AssertionError("No explicit target candidates")
        own = snapshot["enginePlayerId"]
        selected = own if "starting player" in payload["message"].lower() and own in candidates else rng.choice(candidates)
        return {"kind": "uuid", "value": selected}
    if kind == "ASK" and "mulligan" in payload["message"].lower():
        return {"kind": "boolean", "value": False}
    if kind == "SELECT":
        return {"kind": "boolean", "value": False}
    if kind == "CHOOSE_CHOICE" and payload.get("choiceOrder"):
        return {"kind": "string", "value": rng.choice(payload["choiceOrder"])}
    raise AssertionError("Unhandled soak prompt family: " + kind)


def human_recipients(engine, config, created):
    # create.seats describes the complete match, including AI. Input authority
    # belongs to the mailbox and must be checked through actual access rejection.
    assert created['seats'] == [s['seatId'] for s in config['seats']], 'Created roster differs from configuration'
    for seat in config['seats']:
        if seat['controller'] == 'ai':
            result = engine.request('poll', matchId=created['matchId'], viewerId=seat['seatId'], after=0)
            assert not result['ok'] and result['error']['code'] == 'unauthorized_seat', 'AI seat gained mailbox access'
    return [s['seatId'] for s in config['seats'] if s['controller'] == 'human']


def scenario(base, seats, ai, seed, report):
    config = configuration(base, seats, ai, seed)
    rng = random.Random(seed)
    record = {"scope": "real-XMage-JVM-protocol-lifecycle", "seed": seed,
              "seedScope": "driver deck-row ordering and explicit choice selection; XMage shuffle/AI scheduling are not seeded",
              "seats": seats, "ai": ai, "commands": [], "nativeExecution": False,
              "configurationSHA256": hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest(),
              "result": "failed"}
    started = time.monotonic()
    try:
        record['stage'] = 'cached-identity'
        record['cachedIdentity'] = cached_identity()
        with EngineProcess(timeout=15) as engine:
            for cycle in range(2):
                record['stage'] = f'cycle-{cycle}-create-and-authority'
                created = engine.call("create", configuration=config)
                match = created["matchId"]
                expected = human_recipients(engine, config, created)
                record['stage'] = f'cycle-{cycle}-prompt-progression'
                seen = set()
                families = set()
                deadline = time.monotonic() + 35
                responses = 0
                progressed = False
                final_revision = None
                # Cycle zero interrupts the opening choice; cycle one reaches live priority.
                target = 0 if cycle == 0 else 8
                while time.monotonic() < deadline:
                    for seat in expected:
                        state = engine.call("poll", matchId=match, viewerId=seat, after=0)
                        assert state["phase"] not in ("failed", "closed", "ended"), "Unexpected terminal phase"
                        prompt = state.get("prompt")
                        if not prompt or prompt.get("submitted") or prompt["promptId"] in seen:
                            continue
                        seen.add(prompt["promptId"])
                        families.add(prompt["kind"])
                        if responses >= target:
                            # Disappearance/submitted flags only mean queued.
                            # Require a decision published AFTER the final receipt,
                            # not an older simultaneous prompt from another seat.
                            if cycle == 0 or (state['phase'] == 'running' and prompt['revision'] > final_revision):
                                progressed = True
                                break
                            continue
                        value = answer(prompt, state["snapshot"], rng)
                        command = {"requestId": str(uuid.uuid5(uuid.NAMESPACE_OID, f"soak-{seed}-{cycle}-{responses}")),
                                   "promptId": prompt["promptId"], "promptRevision": prompt["revision"], "answer": value}
                        receipt = engine.call("respond", matchId=match, viewerId=seat, command=command)
                        assert receipt['status'] == 'queued' and receipt['requestId'] == command['requestId'] and receipt['promptId'] == command['promptId'], 'Unexpected response receipt'
                        # Retain correlation/transcript without card names, private snapshots or raw errors.
                        record["commands"].append({"cycle": cycle, "seat": seat, "kind": prompt["kind"],
                                                   "command": command, "receipt": receipt})
                        responses += 1
                        if responses == target:
                            final_revision = receipt['revision']
                    if progressed:
                        break
                    time.sleep(.01)
                assert progressed, "Opening/post-answer progression not reached before deadline"
                if cycle:
                    assert "SELECT" in families, "Did not reach actual priority"
                record['stage'] = f'cycle-{cycle}-teardown'
                close_start = time.monotonic()
                while True:
                    reply = engine.request("destroy", matchId=match)
                    if reply["ok"]:
                        break
                    if reply["error"]["code"] != "engine_busy_shutdown" or time.monotonic() - close_start > 20:
                        raise AssertionError("Destroy failed or remained busy")
                    time.sleep(.05)
                stale = engine.request("poll", matchId=match, viewerId=expected[0], after=0)
                assert not stale["ok"] and stale["error"]["code"] == "unknown_match"
            record['stage'] = 'shutdown-and-closed-rejection'
            engine.call("shutdown")
            closed = engine.request("create", configuration=config)
            assert not closed["ok"] and closed["error"]["code"] == "engine_closed"
        record["result"] = "passed"
        record['stage'] = 'complete'
    except Exception as error:
        record["failureType"] = type(error).__name__
        raise
    finally:
        record["elapsedSeconds"] = round(time.monotonic() - started, 3)
        report.write_text(json.dumps(record, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", nargs=3, type=int, metavar=("SEATS", "AI", "SEED"))
    parser.add_argument("--output", type=Path, default=ROOT / "evidence/seeded-soak")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.scenario:
        seats, ai, seed = args.scenario
        if (seats, ai) not in CONFIGURATIONS or seed not in SEEDS:
            parser.error("Scenario outside reviewed matrix")
        scenario(json.loads((ROOT / "build/match.json").read_text()), seats, ai, seed,
                 args.output / f"{seats}p-{ai}ai-{seed}.json")
        return
    matrix = {"seeds": SEEDS, "configurations": CONFIGURATIONS, "scenarios": 10,
              "scenarioTimeoutSeconds": 150, "totalTimeoutSeconds": 1550,
              "sourceIdentity": "unverified-cached-class-source; per-scenario byte hashes recorded",
              "scope": "Opening interruption and eight human responses followed by a newer running prompt, then teardown/recreate; not completed games or deterministic XMage RNG"}
    (args.output / "matrix.json").write_text(json.dumps(matrix, indent=2) + "\n")
    deadline = time.monotonic() + 1550
    for seats, ai in CONFIGURATIONS:
        for seed in SEEDS:
            command = [sys.executable, __file__, "--scenario", str(seats), str(ai), str(seed),
                       "--output", str(args.output)]
            try:
                if run_owned(command, min(150, deadline-time.monotonic())) != 0:
                    raise RuntimeError("Scenario failed")
            except subprocess.TimeoutExpired:
                (args.output / f"{seats}p-{ai}ai-{seed}-timeout.json").write_text(
                    json.dumps({"result": "timed-out", "seed": seed, "seats": seats, "ai": ai,
                                "nativeExecution": False}) + "\n")
                raise
    print("PASS 10 real-JVM lifecycle scenarios, 1/2/3 MAD opponents; driver seeds only, no native/phone acceptance")


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print("FAIL seeded soak: " + type(error).__name__ + "; inspect scenario receipt", file=sys.stderr)
        sys.exit(1)
