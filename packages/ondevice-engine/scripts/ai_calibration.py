#!/usr/bin/env python3
"""AI-vs-AI calibration on the real XMage JVM engine (a measurement tool, not an app path).

Run build_jvm.sh first. Subcommands:
  decks      resolve the ranked AI deck pools (the precons in PreconCatalog.swift and ai-decks.json)
  run        one pairing: two skills on a deck pool or two named decks, N seeded games, CSV out
  matrix     every pairing in a matrix file (tools/ai-calibration/baseline-matrix.json), CSV per pairing
  summarize  win rates with Wilson 95% intervals and average game length, as Markdown

Games run in parallel, one JVM per worker (upstream AI search state is static). Each worker JVM
runs games one at a time from a queue, so slow pairings do not leave CPUs idle. Results are
appended as each game ends, and a rerun with the same arguments skips games already in the CSV.
"""
from __future__ import annotations
import argparse, csv, itertools, json, math, os, queue, random, re, subprocess, sys, threading, time
from pathlib import Path

from jvm_client import ROOT
from resolve_deck import resolve

REPO = ROOT.parents[1]
TOOL = ROOT / 'tools/ai-calibration'
BUILD = ROOT / 'build/ai-calibration'
DECKS = BUILD / 'decks'
FIELDS = ['game', 'game_seed', 'budget', 'skill_a', 'skill_b', 'deck_a', 'deck_b', 'first', 'winner',
          'winner_skill', 'turns', 'seconds', 'end']
# Ranked tier pools (docs/RANKED.md): Bronze plays the precons; the others the bracket decks.
POOLS = {'precon': lambda d: d['precon'], 'core': lambda d: d['bracket'] == 2 and not d['precon'],
         'upgraded': lambda d: d['bracket'] == 3, 'optimized': lambda d: d['bracket'] == 4}


def ranked_decks() -> list[dict]:
    """The decks the apps ship for AI opponents, as name/count rows like the app's DeckList."""
    decks = []
    swift = (REPO / 'apps/ios/MagicMobile/PreconCatalog.swift').read_text()
    for match in re.finditer(r'id: "([^"]+)",.*?commander: "([^"]+)",.*?rawList: """\n(.*?)"""', swift, re.S):
        deck_id, commander, raw = match.groups()
        rows = [line.strip() for line in raw.splitlines() if line.strip()]
        decks.append({'id': deck_id, 'commander': commander, 'bracket': 2, 'precon': True, 'list': rows})
    data = json.loads((REPO / 'apps/ios/MagicMobile/Resources/ai-decks.json').read_text())
    for deck in data['decks']:
        rows = [f"{e['quantity']} {e['name']}" for e in deck['entries']]
        decks.append({'id': deck['id'], 'commander': deck['commander'], 'bracket': deck['bracket'],
                      'precon': False, 'list': rows})
    if len([d for d in decks if d['precon']]) != 5:
        raise SystemExit('Expected the 5 precons in PreconCatalog.swift; the parser needs updating')
    return decks


def export_decks() -> list[dict]:
    catalogue = [json.loads(line) for line in (ROOT / 'build/generated/catalogue.jsonl').read_text().splitlines()
                 if line.strip()]
    DECKS.mkdir(parents=True, exist_ok=True)
    decks = ranked_decks()
    for deck in decks:
        resolved = resolve('\n'.join(deck['list']), catalogue, [deck['commander']], [])
        resolved['name'] = deck['id']
        (DECKS / f"{deck['id']}.json").write_text(json.dumps(resolved, ensure_ascii=False, indent=1) + '\n')
    index = [{k: d[k] for k in ('id', 'commander', 'bracket', 'precon')} for d in decks]
    (DECKS / 'index.json').write_text(json.dumps(index, indent=1) + '\n')
    return index


def deck_index() -> list[dict]:
    path = DECKS / 'index.json'
    return json.loads(path.read_text()) if path.exists() else export_decks()


def pool_decks(pool: str) -> list[str]:
    index = deck_index()
    if pool in POOLS:
        return [d['id'] for d in index if POOLS[pool](d)]
    if pool == 'core+precon':
        return [d['id'] for d in index if d['bracket'] == 2]
    ids = pool.split(',')
    known = {d['id'] for d in index}
    missing = [i for i in ids if i not in known]
    if missing:
        raise SystemExit(f'Unknown decks: {missing}. Known pools: {sorted(POOLS) + ["core+precon"]}')
    return ids


def mix(seed: int, *parts: int) -> int:
    """SplitMix64 over the parts, so neighbouring games get unrelated XMage seeds."""
    value = seed & 0xFFFFFFFFFFFFFFFF
    for part in parts:
        value = (value + 0x9E3779B97F4A7C15 * (part + 1)) & 0xFFFFFFFFFFFFFFFF
        value = ((value ^ (value >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        value = ((value ^ (value >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        value ^= value >> 31
    return value & 0x7FFFFFFFFFFFFFFF


def schedule(skill_a: int, skill_b: int, decks: list[str], games: int, seed: int, budget: str) -> list[dict]:
    """Every block of 4 games plays one deck pair with both deck assignments and both seatings.

    Skill A plays deck X going first, deck X going second, deck Y going first, deck Y going second, so
    neither deck strength nor going first favours either skill. Pairs come in a seeded order and repeat.
    """
    if len(decks) < 2:
        raise SystemExit('A pool needs at least two decks')
    pairs = list(itertools.combinations(decks, 2))
    random.Random(seed).shuffle(pairs)
    rows = []
    for game in range(games):
        x, y = pairs[(game // 4) % len(pairs)]
        swap = (game // 2) % 2 == 1
        rows.append({'game': game, 'game_seed': mix(seed, skill_a, skill_b, game), 'budget': budget,
                     'skill_a': skill_a, 'skill_b': skill_b, 'deck_a': y if swap else x, 'deck_b': x if swap else y,
                     'a_first': game % 2 == 0})
    return rows


def done_games(path: Path) -> set[int]:
    if not path.exists():
        return set()
    with path.open() as stream:
        return {int(row['game']) for row in csv.DictReader(stream)}


def compile_tool() -> str:
    cp = (ROOT / 'build/runtime-classpath.txt').read_text().strip()
    out = BUILD / 'classes'
    source = TOOL / 'AICalibration.java'
    stamp = out / 'io/magicmobile/xmage/AICalibration.class'
    if not stamp.exists() or stamp.stat().st_mtime < source.stat().st_mtime:
        out.mkdir(parents=True, exist_ok=True)
        subprocess.run(['javac', '-J-Xmx512m', '--release', '17', '-cp', cp, '-d', str(out), str(source)], check=True)
    # The tool's classes go after the engine's, so they never replace production classes.
    return f'{cp}{os.pathsep}{out}'


class Worker:
    """One JVM that plays the games it is given, one at a time."""
    def __init__(self, classpath: str, heap: str, log: Path):
        self.log = log.open('a')
        self.process = subprocess.Popen(
            ['java', f'-Xmx{heap}', '-XX:+UseSerialGC', '-XX:TieredStopAtLevel=4', '-Djava.awt.headless=true',
             '-Dlog4j.configuration=file:' + str(TOOL / 'log4j.properties'),
             '-cp', classpath, 'io.magicmobile.xmage.AICalibration'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.log, text=True, bufsize=1, cwd=BUILD)
        self.games = 0
        self._await('READY')

    def _await(self, prefix: str) -> str:
        for line in self.process.stdout:
            if line.startswith(prefix):
                return line.strip()
            self.log.write(line)
        raise RuntimeError(f'Calibration JVM exited (see {self.log.name})')

    def play(self, line: str) -> list[str]:
        self.process.stdin.write(line + '\n')
        self.process.stdin.flush()
        self.games += 1
        return self._await('RESULT,').split(',')[1:]

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=30)
        except Exception:
            self.process.kill()
        self.log.close()


def play_all(jobs: list[tuple[Path, dict]], workers: int, heap: str, max_turns: int, max_seconds: int,
             restart_every: int) -> None:
    """jobs: (csv path, schedule row). Appends each finished game to its CSV."""
    classpath = compile_tool()
    work: queue.Queue = queue.Queue()
    for job in jobs:
        work.put(job)
    lock = threading.Lock()
    total = len(jobs)
    finished = [0]
    started = time.monotonic()
    errors: list[BaseException] = []
    (BUILD / 'logs').mkdir(parents=True, exist_ok=True)

    def run(index: int):
        worker = None
        try:
            while True:
                try:
                    path, row = work.get_nowait()
                except queue.Empty:
                    return
                if worker is None or worker.games >= restart_every:
                    if worker:
                        worker.close()
                    worker = Worker(classpath, heap, BUILD / f'logs/worker-{index}.log')
                line = ','.join(str(v) for v in (
                    row['game'], row['game_seed'], row['budget'], row['skill_a'], row['skill_b'],
                    1 if row['a_first'] else 0, DECKS / f"{row['deck_a']}.json", DECKS / f"{row['deck_b']}.json",
                    max_turns, max_seconds))
                try:
                    _, first, winner, turns, seconds, end = worker.play(line)
                except RuntimeError:
                    worker.close()
                    worker = None
                    first, winner, turns, seconds, end = '?', 'draw', '0', '0', 'jvm-exit'
                result = {k: row[k] for k in ('game', 'game_seed', 'budget', 'skill_a', 'skill_b', 'deck_a', 'deck_b')}
                result.update(first=first, winner=winner, turns=turns, seconds=seconds, end=end,
                              winner_skill=row['skill_a'] if winner == 'A' else row['skill_b'] if winner == 'B' else '')
                with lock:
                    new = not path.exists()
                    with path.open('a', newline='') as stream:
                        writer = csv.DictWriter(stream, FIELDS)
                        if new:
                            writer.writeheader()
                        writer.writerow(result)
                    finished[0] += 1
                    elapsed = time.monotonic() - started
                    print(f"[{finished[0]}/{total}] {path.stem} game {row['game']}: {winner} "
                          f"(skill {result['winner_skill'] or '-'}) in {turns} turns, {seconds} s, {end}; "
                          f"{elapsed / 60:.0f} min elapsed", flush=True)
        except BaseException as error:  # surface worker failures to the main thread
            errors.append(error)
        finally:
            if worker:
                worker.close()

    threads = [threading.Thread(target=run, args=(i,), daemon=True) for i in range(workers)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    if errors:
        raise errors[0]


def wilson(wins: float, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return 0.0, 1.0
    p = wins / n
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return centre - half, centre + half


def summarize(paths: list[Path]) -> str:
    lines = ['| Pairing (A vs B) | Budget | Games | A wins | B wins | Draws | A win rate (95% CI) | Avg turns | Avg s/game | A first: A wins |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for path in paths:
        with path.open() as stream:
            rows = list(csv.DictReader(stream))
        if not rows:
            continue
        a = sum(r['winner'] == 'A' for r in rows)
        b = sum(r['winner'] == 'B' for r in rows)
        draws = len(rows) - a - b
        decided = a + b
        low, high = wilson(a, decided)
        rate = f"{100 * a / decided:.0f}% ({100 * low:.0f}–{100 * high:.0f})" if decided else '–'
        turns = sum(int(r['turns']) for r in rows) / len(rows)
        seconds = sum(float(r['seconds']) for r in rows) / len(rows)
        first = [r for r in rows if r['first'] == 'A' and r['winner'] in 'AB']
        first_rate = f"{sum(r['winner'] == 'A' for r in first)}/{len(first)}"
        lines.append(f"| skill {rows[0]['skill_a']} vs {rows[0]['skill_b']} | {rows[0]['budget']} | {len(rows)} | "
                     f"{a} | {b} | {draws} | {rate} | {turns:.1f} | {seconds:.0f} | {first_rate} |")
    lines.append('')
    lines.append('Win rate counts decided games only (draws are turn or time limits). Interval: Wilson score, 95%.')
    return '\n'.join(lines)


def pairing_jobs(out: Path, skill_a: int, skill_b: int, pool: str, games: int, seed: int, budget: str):
    path = out / f'skill{skill_a}-vs-skill{skill_b}-{budget}.csv'
    done = done_games(path)
    rows = [r for r in schedule(skill_a, skill_b, pool_decks(pool), games, seed, budget) if r['game'] not in done]
    return path, [(path, r) for r in rows]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('decks', help='resolve the ranked AI deck pools into build/ai-calibration/decks')

    def common(p):
        p.add_argument('--games', type=int, default=80)
        p.add_argument('--seed', type=int, default=20261015)
        p.add_argument('--budget', choices=('phone', 'watcher'), default='phone')
        p.add_argument('--workers', type=int, default=os.cpu_count() or 4)
        p.add_argument('--heap', default='1536m')
        p.add_argument('--max-turns', type=int, default=40)
        p.add_argument('--max-seconds', type=int, default=1800)
        p.add_argument('--restart-every', type=int, default=20, help='games per worker JVM before a fresh one')
        p.add_argument('--out', type=Path, default=BUILD / 'results')

    run = sub.add_parser('run', help='one pairing')
    run.add_argument('--skill-a', type=int, required=True)
    run.add_argument('--skill-b', type=int, required=True)
    run.add_argument('--pool', default='core+precon',
                     help='precon, core, upgraded, optimized, core+precon, or comma-separated deck ids')
    common(run)
    matrix = sub.add_parser('matrix', help='every pairing in a matrix file')
    matrix.add_argument('file', type=Path)
    common(matrix)
    summary = sub.add_parser('summarize', help='Markdown table of result CSVs')
    summary.add_argument('csv', nargs='+', type=Path)
    args = parser.parse_args()

    if args.command == 'decks':
        index = export_decks()
        for name, keep in POOLS.items():
            print(f"{name}: {', '.join(d['id'] for d in index if keep(d))}")
        return
    if args.command == 'summarize':
        print(summarize(args.csv))
        return
    if not (ROOT / 'build/runtime-classpath.txt').exists():
        raise SystemExit('Run scripts/build_jvm.sh first')
    deck_index()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.command == 'run':
        specs = [(args.skill_a, args.skill_b, args.pool)]
    else:
        spec = json.loads(args.file.read_text())
        specs = [(p[0], p[1], spec.get('pool', 'core+precon')) for p in spec['pairings']]
        args.games = spec.get('games', args.games)
    paths, jobs = [], []
    for skill_a, skill_b, pool in specs:
        path, new = pairing_jobs(args.out, skill_a, skill_b, pool, args.games, args.seed, args.budget)
        paths.append(path)
        jobs += new
    # Interleave pairings so partial results cover every pairing.
    jobs.sort(key=lambda job: (job[1]['game'], job[0].name))
    print(f'{len(jobs)} games to play on {args.workers} workers ({args.budget} budget)', flush=True)
    play_all(jobs, args.workers, args.heap, args.max_turns, args.max_seconds, args.restart_every)
    print(summarize([p for p in paths if p.exists()]))


if __name__ == '__main__':
    main()
