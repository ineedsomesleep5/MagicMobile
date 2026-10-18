#!/usr/bin/env python3
"""Summarise a Time Profiler trace of MagicMobile, so phone traces of two builds compare the same way.

Export the time-profile table first (docs/LIGHTER_ENGINE_PLAN.md step 1):

    xcrun xctrace export --input phone.trace \
        --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output phone-tp.xml
    python3 -I scripts/ios/time_profile_summary.py phone-tp.xml

It prints each thread's share of the samples; for the main thread, how often SwiftUI's display link updated the
board in each window (the gap between updates: 16.7 ms is 60 a second, 33.3 ms is 30) and the app's own frames;
and the app's own frames on the polling thread. Read-only; the trace is data.
"""
from __future__ import annotations

import argparse
import collections
import xml.etree.ElementTree as ET

APP_BINARY = "MagicMobile"


def rows(path):
    """Yields (time_ns, thread, frames leaf first) for every sample; xctrace refers back to earlier ids."""
    frames, binaries, stacks, threads, times = {}, {}, {}, {}, {}

    def frame(el):
        if el.get("ref"):
            return frames.get(el.get("ref"), "?")
        name = el.get("name") or el.get("addr") or "?"
        binary = el.find("binary")
        if binary is not None:
            owner = binaries.get(binary.get("ref")) if binary.get("ref") else binary.get("name")
            if binary.get("id"):
                binaries[binary.get("id")] = binary.get("name")
            if owner == APP_BINARY:
                name = "APP " + name
        frames[el.get("id")] = name
        return name

    for _, el in ET.iterparse(path, events=("end",)):
        if el.tag != "row":
            continue
        time, thread, stack = None, None, []
        for child in el:
            if child.tag == "sample-time":
                time = times[child.get("ref")] if child.get("ref") else int(child.text)
                if child.get("id"):
                    times[child.get("id")] = time
            elif child.tag == "thread":
                thread = threads.get(child.get("ref")) if child.get("ref") else child.get("fmt")
                if child.get("id"):
                    threads[child.get("id")] = thread
            elif child.tag in ("backtrace", "tagged-backtrace"):
                if child.get("ref"):
                    stack = stacks.get(child.get("ref"), [])
                else:
                    stack = [frame(f) for f in child if f.tag == "frame"]
                    stacks[child.get("id")] = stack
        el.clear()
        if time is not None and thread:
            yield time, thread, stack


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("export", help="xctrace export of the time-profile table")
    parser.add_argument("--window", type=int, default=30, help="seconds per row of the update-rate table")
    parser.add_argument("--top", type=int, default=25, help="app frames to list per thread")
    args = parser.parse_args()

    per_thread = collections.Counter()
    main_app, poll_app = collections.Counter(), collections.Counter()
    main_total = poll_total = 0
    updates = collections.defaultdict(list)
    window_main = collections.Counter()
    for time, thread, stack in rows(args.export):
        name = thread.split(" (0x")[0]
        per_thread[name] += 1
        app = {f for f in stack if f.startswith("APP ") and f != "APP main"}
        if name == "Main Thread":
            main_total += 1
            window = time // 1_000_000_000 // args.window * args.window
            window_main[window] += 1
            if any("displayLinkTimer" in f for f in stack):
                updates[window].append(time)
            main_app.update(app)
        elif any("beginPolling" in f for f in app):
            poll_total += 1
            poll_app.update(app)

    total = sum(per_thread.values()) or 1
    print("Threads (share of all samples)")
    for name, count in per_thread.most_common(10):
        print(f"  {100 * count / total:5.1f}%  {name}")

    print(f"\nMain thread, per {args.window} s: samples (1 ms each), display-link share, updates a second, and how many "
          "gaps between updates were 16.7 ms (60/s) or 33.3 ms (30/s)")
    for window in sorted(window_main):
        times = sorted(updates[window])
        starts = [t for i, t in enumerate(times) if i == 0 or t - times[i - 1] > 2_500_000]
        gaps = [(b - a) / 1e6 for a, b in zip(starts, starts[1:])]
        g60 = sum(1 for g in gaps if 14 < g < 19)
        g30 = sum(1 for g in gaps if 30 < g < 36)
        print(f"  {window:5d} s  {window_main[window]:6d}  {100 * len(times) / max(window_main[window], 1):5.1f}%  "
              f"{len(starts) / args.window:5.1f}/s  60/s gaps {g60:5d}  30/s gaps {g30:5d}")

    for title, counter, count in (("Main thread", main_app, main_total), ("Polling thread", poll_app, poll_total)):
        print(f"\n{title}: app frames, inclusive ({count} samples)")
        for name, hits in counter.most_common(args.top):
            print(f"  {100 * hits / max(count, 1):5.1f}%  {name[4:150]}")


if __name__ == "__main__":
    main()
