#!/usr/bin/env python3
"""Profile long AI-vs-AI Commander games on the real XMage JVM engine (lighter engine plan, step 1).

A measurement tool, not an app path. Run build_jvm.sh and `ai_calibration.py decks` first. Subcommands:
  run     seeded same-skill games (AICalibration's phone budget and schedule), one JVM at a time, each observed
          by tools/ai-calibration/LongGameProfile.java. Mode `profile` attaches async-profiler (CPU and allocation,
          JFR) for the game only; mode `memory` instead runs a full GC every few seconds for the live heap, writes a
          class histogram at each new live peak and keeps one heap dump at the largest.
  report  Markdown summary of the game directories: game table, AI searches by skill and turn, game copy cost,
          CPU hotspots and copy sites, allocation sites, heap histogram at the peak.
  heap    retained sizes at each heap dump with Eclipse MAT (--mat): top dominators, and every game object (live
          game, AI search copies, playable-calculation copies) with what it keeps alive.
  equivalence  engine release C's AI search memory changes (card copies on first use, library searches one target
          at a time) against upstream's way: at real AI decisions of seeded games, the same search without a time
          limit, twice the upstream way and once the new way (tools/ai-calibration/SearchEquivalence.java).

Output goes to build/profile-long-games/<mode>/skill<S>-g<N>/ (outside git): result.json, searches.csv,
turns.csv, timeline.csv, gc.csv, worker.log; profile.jfr in profile mode; hist-*.txt and heap-peak.hprof in
memory mode. async-profiler and MAT are not bundled: pass --asprof (the release directory with bin/asprof and
bin/jfrconv) and --mat, or set ASYNC_PROFILER_HOME and MAT_HOME.
"""
from __future__ import annotations
import argparse, csv, json, os, re, statistics, subprocess, sys, time
from collections import Counter, defaultdict
from pathlib import Path

from ai_calibration import BUILD, DECKS, TOOL, deck_index, schedule, pool_decks
from jvm_client import ROOT

OUT = ROOT / 'build/profile-long-games'
RESULT_ENDS = ('ended', 'turn-limit', 'time-limit')


def compile_tool(engine: Path | None = None) -> str:
    """The tools compiled against this build, on the classpath of this build or of another (engine, before/after)."""
    cp = (ROOT / 'build/runtime-classpath.txt').read_text().strip()
    out = BUILD / 'classes'
    sources = [TOOL / 'AICalibration.java', TOOL / 'LongGameProfile.java']
    stamp = out / 'io/magicmobile/xmage/LongGameProfile.class'
    if not stamp.exists() or any(stamp.stat().st_mtime < s.stat().st_mtime for s in sources):
        out.mkdir(parents=True, exist_ok=True)
        subprocess.run(['javac', '-J-Xmx512m', '--release', '17', '-nowarn', '-cp', cp, '-d', str(out), *map(str, sources)],
                       check=True)
    if engine:
        cp = engine.read_text().strip()
    return f'{cp}{os.pathsep}{out}'


def await_line(process, prefix: str, log) -> str:
    for line in process.stdout:
        if line.startswith(prefix):
            return line.strip()
        log.write(line)
    raise RuntimeError(f'Profile JVM exited before {prefix}')


def asprof(args: argparse.Namespace, *command: str) -> None:
    subprocess.run([str(Path(args.asprof) / 'bin/asprof'), *command], check=True, stdout=subprocess.DEVNULL)


def play(args: argparse.Namespace, classpath: str, row: dict, game_dir: Path) -> dict:
    game_dir.mkdir(parents=True, exist_ok=True)
    for stale in game_dir.glob('*'):
        stale.unlink()
    command = ['java', f'-Xmx{args.heap}', '-XX:+UseSerialGC', '-Djava.awt.headless=true', '-XX:+EnableDynamicAgentLoading',
               '-Dlog4j.configuration=file:' + str(TOOL / 'log4j.properties'), '-cp', classpath,
               'io.magicmobile.xmage.LongGameProfile', str(game_dir), str(row['game']), str(row['game_seed']),
               str(row['skill_a']), str(row['skill_b']), '1' if row['a_first'] else '0',
               str(DECKS / f"{row['deck_a']}.json"), str(DECKS / f"{row['deck_b']}.json"),
               str(args.max_turns), str(args.max_seconds), args.mode, str(args.gc_every_ms), str(args.dump_over_mb)]
    with (game_dir / 'worker.log').open('w') as log:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True,
                                   bufsize=1, cwd=BUILD)
        try:
            await_line(process, 'READY', log)
            process.stdin.write('\n')
            process.stdin.flush()
            pid = await_line(process, 'GAME ', log).split()[1]
            if args.mode == 'profile':
                asprof(args, 'start', '-e', 'cpu', '-i', args.interval, '--alloc', args.alloc,
                       '-f', str(game_dir / 'profile.jfr'), pid)
            await_line(process, 'ENDED', log)
            if args.mode == 'profile':
                asprof(args, 'stop', pid)
            process.stdin.write('\n')
            process.stdin.flush()
            process.wait(timeout=600)
        finally:
            if process.poll() is None:
                process.kill()
    result_path = game_dir / 'result.json'
    return json.loads(result_path.read_text()) if result_path.exists() else {'end': 'jvm-exit'}


def run(args: argparse.Namespace) -> None:
    if not (ROOT / 'build/runtime-classpath.txt').exists():
        raise SystemExit('Run scripts/build_jvm.sh first')
    if args.mode == 'profile' and not (Path(args.asprof) / 'bin/asprof').exists():
        raise SystemExit('--asprof must name an async-profiler release directory (bin/asprof, lib/)')
    deck_index()
    decks = [d for pool in args.pool.split('+') for d in pool_decks(pool)]
    classpath = compile_tool(args.engine_classpath)
    for skill in [int(s) for s in args.skills.split(',')]:
        rows = schedule(skill, skill, decks, args.first_game + args.games, args.seed, 'phone')[args.first_game:]
        for row in rows:
            game_dir = args.out / args.mode / f"skill{skill}-g{row['game']}"
            done = game_dir / 'result.json'
            if done.exists() and json.loads(done.read_text()).get('end') in RESULT_ENDS:
                continue
            started = time.monotonic()
            result = play(args, classpath, row, game_dir)
            print(f"skill {skill} game {row['game']} ({row['deck_a']} vs {row['deck_b']}): {result.get('end')} after "
                  f"{result.get('turns', '?')} turns, {time.monotonic() - started:.0f} s; heap after GC max "
                  f"{result.get('max_heap_after_gc_mb', '?')} MB, live max {result.get('max_live_mb', '-')} MB", flush=True)


# ---- Report ------------------------------------------------------------------------------

def read_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with path.open() as stream:
        return list(csv.DictReader(stream))


def pct(values: list[float], q: float) -> float:
    if not values:
        return float('nan')
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def med(values: list[float]) -> float:
    return statistics.median(values) if values else float('nan')


def mean(values: list[float]) -> float:
    return statistics.fmean(values) if values else float('nan')


def turn_bucket(turn: int) -> str:
    return '1–5' if turn <= 5 else '6–10' if turn <= 10 else '11–15' if turn <= 15 else '16–20' if turn <= 20 else '21+'


BUCKETS = ['1–5', '6–10', '11–15', '16–20', '21+']


def games(dirs: list[Path]) -> list[tuple[Path, dict]]:
    found = []
    for base in dirs:
        # Natural order: skill4-g2 before skill4-g12.
        for result in sorted(base.rglob('result.json'), key=lambda p: [int(t) if t.isdigit() else t
                                                                       for t in re.split(r'(\d+)', str(p))]):
            data = json.loads(result.read_text())
            if data.get('end') in RESULT_ENDS:
                found.append((result.parent, data))
    return found


def game_table(found) -> list[str]:
    lines = ['| Game | Mode | Skill | Decks | Turns | End | Game s | Searches | Game copies | Process CPU s | '
             'Heap before GC max MB | After GC max MB | Live max MB |', '|' + '---|' * 13]
    for path, r in found:
        lines.append(f"| {path.name} | {r['mode']} | {r['skill_a']} | {r['deck_a'].removeprefix('ai-')} vs "
                     f"{r['deck_b'].removeprefix('ai-')} | {r['turns']} | {r['end']}"
                     f"{' (' + r['winner'] + ')' if r['end'] == 'ended' else ''} | {r['seconds']:.0f} | {r['searches']} | "
                     f"{r['copies']:,} | {r['process_cpu_s']:.0f} | {r['max_heap_before_gc_mb']:.0f} | "
                     f"{r['max_heap_after_gc_mb']:.0f} | {r.get('max_live_mb', '–')} |")
    return lines


def search_tables(found) -> list[str]:
    by_skill: dict[int, list[dict]] = defaultdict(list)
    game_seconds = {}
    for path, r in found:
        if r['mode'] != 'profile':
            continue
        game_seconds[path.name] = r['seconds']
        for s in read_csv(path / 'searches.csv'):
            by_skill[int(s['skill'])].append(dict(s, game=path.name))
    lines = ['| Skill | Decisions searched | Wall ms median | p90 | max | Used ≥ 90% of the think budget | Nodes median | p90 | '
             'Game copies/decision median | CPU ms per node | Game copies per node | CPU s/decision mean | '
             'Alloc MB/decision mean | Alloc per copy KB |', '|' + '---|' * 14]
    for skill in sorted(by_skill):
        rows = by_skill[skill]
        wall = [float(s['wall_ms']) for s in rows]
        # Phone budget: skill × 3 s on an empty stack, 2 s while responding. An expert's full search gets the whole
        # seconds left after its quick one, so a search that ran out of time can end up to a second early.
        hit = sum(w >= 0.9 * (skill * 3000 if s['stack'] == '0' else 2000) for w, s in zip(wall, rows))
        # An expert decision is a quick search plus the full one; both count as nodes.
        nodes = [int(s['nodes']) + int(s['nodes_quick'] or 0) for s in rows]
        copies = [int(s['copies']) for s in rows]
        cpu = [float(s['game_cpu_ms']) + float(s['sim_cpu_ms']) for s in rows]
        alloc = [float(s['game_alloc_mb']) + float(s['sim_alloc_mb']) for s in rows]
        lines.append(f"| {skill} | {len(rows)} | {med(wall):.0f} | {pct(wall, .9):.0f} | {max(wall):.0f} | "
                     f"{hit} ({100 * hit / len(rows):.0f}%) | {med(nodes):.0f} | {pct(nodes, .9):.0f} | {med(copies):.0f} | "
                     f"{sum(cpu) / max(1, sum(nodes)):.1f} | {sum(copies) / max(1, sum(nodes)):.1f} | {mean(cpu) / 1000:.2f} | "
                     f"{mean(alloc):.0f} | {1024 * sum(alloc) / max(1, sum(copies)):.0f} |")
    lines += ['', 'Think time per game: share of game time the AIs spent searching, and the longest single AI turn '
              '(sum of one player\'s searches in one turn).', '',
              '| Skill | Games | Searching / game time | AI turn think s median | p90 | max |', '|---|---|---|---|---|---|']
    for skill in sorted(by_skill):
        per_game = defaultdict(float)
        per_turn = defaultdict(float)
        for s in by_skill[skill]:
            per_game[s['game']] += float(s['wall_ms']) / 1000
            per_turn[(s['game'], s['turn'], s['seat'])] += float(s['wall_ms']) / 1000
        seconds = sum(game_seconds[g] for g in per_game)
        turns_ = list(per_turn.values())
        lines.append(f"| {skill} | {len(per_game)} | {100 * sum(per_game.values()) / max(1, seconds):.0f}% | "
                     f"{med(turns_):.1f} | {pct(turns_, .9):.1f} | {max(turns_):.1f} |")
    alive = {skill: [int(s['copies_alive_max']) for s in rows if s.get('copies_alive_max')] for skill, rows in by_skill.items()}
    if any(alive.values()):
        lines += ['', 'Game copies one decision held alive at once (AISearchMemory, engine release C; the listing allowance of 3 '
                  'included) and its cap.', '',
                  '| Skill | Decisions | Copies alive median | p90 | max | Cap min | Decisions at the cap |', '|---|---|---|---|---|---|---|']
        for skill in sorted(by_skill):
            if not alive[skill]:
                continue
            caps = [int(s['copy_cap']) for s in by_skill[skill] if s.get('copy_cap')]
            capped = sum(s.get('capped') == '1' for s in by_skill[skill])
            lines.append(f"| {skill} | {len(alive[skill])} | {med(alive[skill]):.0f} | {pct(alive[skill], .9):.0f} | "
                         f"{max(alive[skill])} | {min(caps) if caps else '–'} | {capped} |")
    lines += ['', '| Skill | Turns | Searches | Wall ms median | p90 | Alloc MB/search mean | Copies/search mean | '
              'Heap during search max MB |', '|' + '---|' * 8]
    for skill in sorted(by_skill):
        for bucket in BUCKETS:
            rows = [s for s in by_skill[skill] if turn_bucket(int(s['turn'])) == bucket]
            if not rows:
                continue
            wall = [float(s['wall_ms']) for s in rows]
            alloc = [float(s['game_alloc_mb']) + float(s['sim_alloc_mb']) for s in rows]
            lines.append(f"| {skill} | {bucket} | {len(rows)} | {med(wall):.0f} | {pct(wall, .9):.0f} | {mean(alloc):.0f} | "
                         f"{mean([int(s['copies']) for s in rows]):.0f} | {max(float(s['heap_max_mb']) for s in rows):.0f} |")
    return lines


def copy_tables(found) -> list[str]:
    rows = []
    for path, r in found:
        rows += [dict(t, mode=r['mode']) for t in read_csv(path / 'turns.csv')]
    lines = ['| Turns | Probes | Permanents | Cards in game | Copy wall ms median | Copy CPU ms median | Copy alloc KB median | '
             'Copy retained KB median | Search copy retained KB median | Engine estimate KB median |', '|' + '---|' * 10]
    for bucket in BUCKETS:
        sel = [t for t in rows if turn_bucket(int(t['turn'])) == bucket]
        if not sel:
            continue
        retained = [float(t['copy_retained_kb']) for t in sel if t['copy_retained_kb']]
        # Two GCs around held copies; a late search thread can free memory in between, so drop readings under 0.
        sim = [float(t['sim_copy_retained_kb']) for t in sel if t.get('sim_copy_retained_kb') and float(t['sim_copy_retained_kb']) > 0]
        estimate = [float(t['sim_copy_estimate_kb']) for t in sel if t.get('sim_copy_estimate_kb')]
        tail = f" {med(sim):.0f} |" if sim else ' – |'
        tail += f" {med(estimate):.0f} |" if estimate else ' – |'
        lines.append(f"| {bucket} | {len(sel)} | {med([int(t['permanents']) for t in sel]):.0f} | "
                     f"{med([int(t['game_cards']) for t in sel]):.0f} | {med([float(t['copy_wall_ms']) for t in sel]):.1f} | "
                     f"{med([float(t['copy_cpu_ms']) for t in sel]):.1f} | {med([float(t['copy_alloc_kb']) for t in sel]):.0f} | "
                     f"{med(retained):.0f} |" + tail if retained else
                     f"| {bucket} | {len(sel)} | {med([int(t['permanents']) for t in sel]):.0f} | "
                     f"{med([int(t['game_cards']) for t in sel]):.0f} | {med([float(t['copy_wall_ms']) for t in sel]):.1f} | "
                     f"{med([float(t['copy_cpu_ms']) for t in sel]):.1f} | {med([float(t['copy_alloc_kb']) for t in sel]):.0f} | – |" + tail)
    return lines


# Collapsed stacks from jfrconv: "[thread];frame;frame;... value", frames like mage/game/GameImpl.<init>_[j].
SUFFIX = re.compile(r'_\[[a-z0-9]\]$')
COPY_ENTRY = ('mage/game/GameImpl.createSimulationForAI', 'mage/game/GameImpl.createSimulationForPlayableCalc')
CONTEXTS = ['mage/player/ai/ComputerPlayer6.simulatePriority', 'mage/player/ai/SimulatedPlayer2.simulatePriority',
            'mage/player/ai/SimulatedPlayer2.', 'mage/player/ai/ComputerPlayer6.createSimulation',
            'mage/player/ai/ComputerPlayer6.resolve', 'mage/player/ai/util/CombatUtil.',
            'io/magicmobile/xmage/CombatPlanner.', 'io/magicmobile/xmage/MobileAICancellation$CancellablePlayer.priorityLive',
            'mage/player/ai/ComputerPlayer.']


def collapsed(jfr: Path, kind: str, args) -> Path:
    target = jfr.with_name(f'{kind}.collapsed')
    if not target.exists() or target.stat().st_mtime < jfr.stat().st_mtime:
        extra = ['--total'] if kind == 'alloc' else []
        subprocess.run([str(Path(args.asprof) / 'bin/jfrconv'), f'--{kind}', '-t', *extra, '-o', 'collapsed', str(jfr),
                        str(target)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return target


def stacks(path: Path):
    with path.open() as stream:
        for line in stream:
            body, _, value = line.rstrip('\n').rpartition(' ')
            frames = [SUFFIX.sub('', f) for f in body.split(';')]
            yield frames, int(value)


def thread_group(frames: list[str]) -> str:
    name = frames[0].strip('[]')
    if name.startswith('GAME'):
        return 'GAME thread'
    if name.startswith('AI-SIM-MAD'):
        return 'AI search threads'
    if 'Compiler' in name or any(f.startswith('CompileBroker::') for f in frames):
        return 'JIT compiler (not on phones)'
    if name.startswith(('VM Thread', 'GC')) or any(f.startswith(('VM_GC', 'GenCollectedHeap', 'SerialHeap')) for f in frames):
        return 'GC and VM'
    if name.startswith(('main', 'mm-profile', 'Notification')):
        return 'harness'
    return 'other'


def short(frame: str) -> str:
    return frame.replace('/', '.').replace('io.magicmobile.xmage.', '').replace('mage.player.ai.', 'ai.')


def copy_site(frames: list[str]) -> str | None:
    """Caller of the outermost game copy in this stack, with the AI context that led to it."""
    for i, f in enumerate(frames):
        if f.startswith(COPY_ENTRY) or f == 'io/magicmobile/xmage/MobileCommanderGame.copy':
            if any('LongGameProfile' in g for g in frames[:i]):
                return 'harness probe'
            caller = short(frames[i - 1]) if i else '?'
            context = next((short(g) for g in reversed(frames[:i - 1]) if g.startswith(tuple(CONTEXTS))), '')
            kind = 'playable calc' if f.endswith('ForPlayableCalc') else 'AI simulation'
            return f'{caller} ({kind}{"; in " + context if context and context != caller else ""})'
    return None


INCLUSIVE = [('Any game copy (GameImpl copy constructor)', 'mage/game/GameImpl.<init>'),
             ('  of which card copies (CardImpl copy constructors)', 'mage/cards/CardImpl.<init>'),
             ('  of which game state copy (GameState copy)', 'mage/game/GameState.<init>'),
             ('Playable calculation (PlayerImpl.getPlayable)', 'mage/players/PlayerImpl.getPlayable'),
             ('Mana options (PlayerImpl.getManaAvailable)', 'mage/players/PlayerImpl.getManaAvailable'),
             ('Score (GameStateEvaluator2.evaluate)', 'mage/player/ai/score/GameStateEvaluator2.evaluate'),
             ('State hash string (GameState.getValue)', 'mage/game/GameState.getValue'),
             ('Continuous effects (ContinuousEffects.apply)', 'mage/abilities/effects/ContinuousEffects.apply'),
             ('State-based actions and triggers (GameImpl.checkStateAndTriggered)', 'mage/game/GameImpl.checkStateAndTriggered')]


def profile_tables(found, args) -> list[str]:
    cpu_groups, cpu_incl, cpu_sites, cpu_total = Counter(), Counter(), Counter(), 0
    alloc_incl, alloc_sites, alloc_classes, alloc_methods, alloc_total = Counter(), Counter(), Counter(), Counter(), 0
    profiled = 0
    for path, r in found:
        jfr = path / 'profile.jfr'
        if r['mode'] != 'profile' or not jfr.exists():
            continue
        profiled += 1
        for frames, value in stacks(collapsed(jfr, 'cpu', args)):
            cpu_total += value
            cpu_groups[thread_group(frames)] += value
            for label, needle in INCLUSIVE:
                if any(f.startswith(needle) for f in frames):
                    cpu_incl[label] += value
            site = copy_site(frames)
            if site:
                cpu_sites[site] += value
        for frames, value in stacks(collapsed(jfr, 'alloc', args)):
            alloc_total += value
            alloc_classes[frames[-1].replace('/', '.')] += value
            method = next((short(f) for f in reversed(frames[:-1]) if not f.startswith(('java/', 'jdk/', 'sun/'))), '?')
            alloc_methods[method] += value
            for label, needle in INCLUSIVE:
                if any(f.startswith(needle) for f in frames):
                    alloc_incl[label] += value
            site = copy_site(frames)
            if site:
                alloc_sites[site] += value
    if not profiled:
        return ['No profile.jfr files.']
    # Phones run the engine ahead-of-time compiled: JIT compiler threads (and this harness) are left out of "engine CPU".
    engine = cpu_total - cpu_groups['JIT compiler (not on phones)'] - cpu_groups['harness']
    seconds = sum(r['seconds'] for _, r in found if r['mode'] == 'profile' and (_ / 'profile.jfr').exists())
    lines = [f'{profiled} profiled games, {seconds / 60:.0f} min of play; {cpu_total:,} CPU samples (10 ms), of which '
             f'{engine:,} engine CPU (all threads except the JIT compiler and the harness); {alloc_total / 2**30:.0f} GB '
             f'allocated ({alloc_total / 2**20 / max(1, seconds):.0f} MB per second of play; async-profiler TLAB sampling, '
             f'scaled to bytes).', '', '| Thread group | Share of all CPU | Share of engine CPU |', '|---|---|---|']
    lines += [f'| {g} | {100 * v / cpu_total:.1f}% | {"–" if g.startswith(("JIT", "harness")) else f"{100 * v / engine:.1f}%"} |'
              for g, v in cpu_groups.most_common()]
    lines += ['', '| Inclusive frame | Share of engine CPU | Share of allocated bytes |', '|---|---|---|']
    lines += [f'| {label} | {100 * cpu_incl[label] / engine:.1f}% | {100 * alloc_incl[label] / max(1, alloc_total):.1f}% |'
              for label, _ in INCLUSIVE]
    lines += ['', '| Game copy site (caller; context) | Share of engine CPU | Share of allocated bytes |', '|---|---|---|']
    sites = sorted(set(cpu_sites) | set(alloc_sites), key=lambda s: -(cpu_sites[s] + alloc_sites[s] * cpu_total / max(1, alloc_total)))
    lines += [f'| {s} | {100 * cpu_sites[s] / engine:.1f}% | {100 * alloc_sites[s] / max(1, alloc_total):.1f}% |'
              for s in sites[:14]]
    lines += anatomy_table(found, args)
    lines += ['', '| Allocating method (first non-JDK frame) | Share of bytes |', '|---|---|']
    lines += [f'| {m} | {100 * v / alloc_total:.1f}% |' for m, v in alloc_methods.most_common(20)]
    lines += ['', '| Allocated class | Share of bytes |', '|---|---|']
    lines += [f'| {c} | {100 * v / alloc_total:.1f}% |' for c, v in alloc_classes.most_common(15)]
    return lines


LINED = re.compile(r'^(.*):(\d+)$')
UPSTREAM = ROOT / '.upstream/mage/Mage/src/main/java'


def source_line(cls: str, line: int, cache: dict = {}) -> str:
    if cls not in cache:
        path = UPSTREAM / f'{cls}.java'
        cache[cls] = path.read_text().splitlines() if path.exists() else []
    text = cache[cls][line - 1].strip() if 0 < line <= len(cache[cls]) else '?'
    return re.sub(r'^this\.', '', text).rstrip(';')


def copy_field(frames: list[str]) -> str | None:
    """Which line of the GameImpl (or, inside its state copy, GameState) copy constructor this sample is under."""
    for i, f in enumerate(frames):
        m = LINED.match(f)
        if m and m.group(1) == 'mage/game/GameImpl.<init>':
            for g in frames[i + 1:]:
                n = LINED.match(g)
                if n and n.group(1) == 'mage/game/GameState.<init>':
                    return 'state: ' + source_line('mage/game/GameState', int(n.group(2)))
            return source_line('mage/game/GameImpl', int(m.group(2)))
    return None


def anatomy_table(found, args) -> list[str]:
    """Copy CPU and bytes by the field being copied (needs line numbers, so a second jfrconv pass)."""
    cpu, alloc = Counter(), Counter()
    for path, r in found:
        jfr = path / 'profile.jfr'
        if r['mode'] != 'profile' or not jfr.exists():
            continue
        for kind, total in (('cpu', cpu), ('alloc', alloc)):
            target = path / f'{kind}-lines.collapsed'
            if not target.exists() or target.stat().st_mtime < jfr.stat().st_mtime:
                subprocess.run([str(Path(args.asprof) / 'bin/jfrconv'), f'--{kind}', '--lines',
                                *(['--total'] if kind == 'alloc' else []), '-o', 'collapsed', str(jfr), str(target)],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for frames, value in stacks(target):
                if any('LongGameProfile' in f for f in frames):
                    continue
                field = copy_field(frames)
                if field:
                    total[field] += value
    if not cpu:
        return []
    c_total, a_total = sum(cpu.values()), sum(alloc.values())
    lines = ['', 'What a game copy spends its time and bytes on (share of all game-copy CPU and bytes, by the line of '
             "the GameImpl or GameState copy constructor; the harness's own probe copies left out):", '',
             '| Copied field | Share of copy CPU | Share of copy bytes |', '|---|---|---|']
    for field in sorted(set(cpu) | set(alloc), key=lambda f: -(cpu[f] / c_total + alloc[f] / max(1, a_total)))[:16]:
        lines.append(f'| `{field}` | {100 * cpu[field] / c_total:.1f}% | {100 * alloc[field] / max(1, a_total):.1f}% |')
    return lines


HIST_ROW = re.compile(r'^\s*\d+:\s+(\d+)\s+(\d+)\s+(\S+)')


def histogram(path: Path) -> dict[str, tuple[int, int]]:
    rows = {}
    for line in path.read_text().splitlines():
        m = HIST_ROW.match(line)
        if m:
            rows[m.group(3)] = (int(m.group(1)), int(m.group(2)))
    return rows


def histogram_tables(found) -> list[str]:
    peaks = []
    for path, r in found:
        hists = sorted(path.glob('hist-t*.txt'), key=lambda p: int(re.search(r'-(\d+)mb', p.name).group(1)))
        if hists:
            peaks.append((int(re.search(r'-(\d+)mb', hists[-1].name).group(1)), path, hists[-1]))
    if not peaks:
        return ['No memory-mode histograms.']
    lines = ['| Game | Live peak MB | Turn | Baseline MB |', '|---|---|---|---|']
    for mb_, path, hist in sorted(peaks, reverse=True):
        base = sum(b for _, b in histogram(path / 'hist-baseline.txt').values()) / 2**20
        lines.append(f"| {path.name} | {mb_} | {re.search(r'-t(\d+)', hist.name).group(1).lstrip('0')} | {base:.0f} |")
    mb_, path, hist = max(peaks)
    rows, base = histogram(hist), histogram(path / 'hist-baseline.txt')
    total = sum(b for _, b in rows.values())
    lines += ['', f'Top 20 classes at the largest live peak ({path.name}, {total / 2**20:.0f} MB live), with growth over the '
                  'same JVM before the game:', '',
              '| # | Class | Instances | MB | Share | Instances over baseline | MB over baseline |', '|' + '---|' * 7]
    for i, (name, (count, size)) in enumerate(sorted(rows.items(), key=lambda kv: -kv[1][1])[:20], 1):
        b_count, b_size = base.get(name, (0, 0))
        lines.append(f'| {i} | `{name}` | {count:,} | {size / 2**20:.1f} | {100 * size / total:.1f}% | {count - b_count:,} | '
                     f'{(size - b_size) / 2**20:.1f} |')
    return lines


def mat_query(args: argparse.Namespace, hprof: Path, command: str) -> list[list[str]]:
    """Rows of one Eclipse MAT query on a heap dump (headless ParseHeapDump; indexes are kept next to the dump)."""
    import html, zipfile
    hprof = hprof.resolve()
    subprocess.run([str(Path(args.mat) / 'ParseHeapDump.sh'), str(hprof), f'-command={command}', 'org.eclipse.mat.api:query'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=hprof.parent)
    rows = []
    with zipfile.ZipFile(hprof.with_name(hprof.stem + '_Query.zip')) as archive:
        for name in archive.namelist():
            if name.endswith('.html') and name != 'toc.html':
                text = archive.read(name).decode()
                for row in re.findall(r'<tr[^>]*>(.*?)</tr>', text, re.S):
                    # MAT appends link text ("All objects", the query) to object cells.
                    cells = [re.sub(r'All objects.*$', '', html.unescape(re.sub('<[^>]+>', '', c))).strip()
                             for c in re.findall(r'<td[^>]*>(.*?)</td>', row, re.S)]
                    if cells:
                        rows.append(cells)
    return rows


def size(text: str) -> int:
    return int(text.replace(',', ''))


def heap(args: argparse.Namespace) -> None:
    """Retained sizes at each game's largest live peak: top dominators by class, and every game object (live game,
    AI search copies, playable-calculation copies) with what it keeps alive."""
    for hprof in sorted(p for d in args.dirs for p in d.rglob('heap-peak.hprof')):
        result = json.loads((hprof.parent / 'result.json').read_text())
        print(f"## {hprof.parent.name}: {result.get('dump_live_mb')} MB live at turn {result.get('dump_turn')}\n")
        rows = mat_query(args, hprof, 'dominator_tree -groupBy BY_CLASS')
        print('| Top-level dominator class | Objects | Retained MB | Share |\n|---|---|---|---|')
        for r in rows[:12]:
            if len(r) >= 5:
                name = re.sub(r'(First \d+ of [\d,]+ objects|All \d+ objects|Only object).*$', '', r[0]).strip()
                print(f'| `{name}` | {r[1]} | {size(r[3]) / 2**20:.1f} | {r[4]} |')
        print()
        games_ = mat_query(args, hprof, 'oql "SELECT g.simulation, g.checkPlayableState, g.@retainedHeapSize '
                                        'FROM INSTANCEOF mage.game.GameImpl g"')
        kinds = defaultdict(list)
        for r in games_:
            if len(r) >= 3 and r[-1].replace(',', '').isdigit():
                kind = 'live game' if r[-3] == 'false' else 'playable-calc copy' if r[-2] == 'true' else 'AI search copy'
                kinds[kind].append(size(r[-1]))
        print('| Game object | Count | Retained MB total | Median KB each | Max KB |\n|---|---|---|---|---|')
        for kind, values in sorted(kinds.items()):
            print(f'| {kind} | {len(values)} | {sum(values) / 2**20:.1f} | {med(values) / 1024:.0f} | {max(values) / 1024:.0f} |')
        # The live AIs (only they have a search state): everything each one keeps alive, and the part held only by the
        # root alternatives the adapter records for deliberate mistakes (MobileAICancellation.CancellablePlayer.rootChoices).
        # The tree a search is still building is held by its AI-SIM-MAD thread's stack instead.
        ai = 'io.magicmobile.xmage.MobileAICancellation$CancellablePlayer'
        for r in mat_query(args, hprof, f'oql "SELECT p.@retainedHeapSize, p.rootChoices.@retainedHeapSize FROM {ai} p '
                                        f'WHERE (p.rootChoices != null)"'):
            if len(r) >= 2 and r[0].replace(',', '').isdigit():
                choices = size(r[1]) if r[1].replace(',', '').isdigit() else 0
                print(f'| live AI player (of which root alternatives {choices / 2**20:.1f} MB) | 1 | {size(r[0]) / 2**20:.1f} | | |')
        print()


def report(args: argparse.Namespace) -> None:
    found = games(args.dirs)
    sections = [('Games', game_table(found)), ('AI searches', search_tables(found)),
                ('Game copy cost by turn (live game, measured on the GAME thread)', copy_tables(found)),
                ('CPU and allocation profile', profile_tables(found, args)), ('Heap at the live peak', histogram_tables(found))]
    for title, lines in sections:
        print(f'## {title}\n')
        print('\n'.join(lines))
        print()


def equivalence(args: argparse.Namespace) -> None:
    """Release C's search memory changes against upstream's way at real AI decisions (SearchEquivalence.java)."""
    classpath = compile_tool()
    subprocess.run(['javac', '-J-Xmx512m', '--release', '17', '-nowarn', '-cp', classpath, '-d', str(BUILD / 'classes'),
                    str(TOOL / 'SearchEquivalence.java')], check=True)
    args.out.mkdir(parents=True, exist_ok=True)
    table = args.out / 'equivalence.csv'
    done = {row['game_seed'] for row in read_csv(table)}
    decks = [d for pool in args.pool.split('+') for d in pool_decks(pool)]
    for skill in [int(s) for s in args.skills.split(',')]:
        for row in schedule(skill, skill, decks, args.first_game + args.games, args.seed, 'phone')[args.first_game:]:
            if str(row['game_seed']) in done:
                continue
            started = time.monotonic()
            with (args.out / f"equivalence-skill{skill}-g{row['game']}.log").open('w') as log:
                subprocess.run(['java', f'-Xmx{args.heap}', '-XX:+UseSerialGC', '-Djava.awt.headless=true',
                                '-Dlog4j.configuration=file:' + str(TOOL / 'log4j.properties'), '-cp', classpath,
                                'io.magicmobile.xmage.SearchEquivalence', str(table), str(row['game_seed']), str(skill), str(skill),
                                '1' if row['a_first'] else '0', str(DECKS / f"{row['deck_a']}.json"),
                                str(DECKS / f"{row['deck_b']}.json"), str(args.max_turns), str(args.probes), str(args.max_nodes)],
                               stdout=log, stderr=subprocess.STDOUT, cwd=BUILD, check=False)
            print(f"skill {skill} game {row['game']} ({row['deck_a']} vs {row['deck_b']}): {time.monotonic() - started:.0f} s",
                  flush=True)
    rows = read_csv(table)
    repeatable = [r for r in rows if r['repeatable'] == '1']
    equal = [r for r in repeatable if r['equal'] == '1']
    print(f'{len(rows)} decisions probed; {len(repeatable)} repeat with upstream\'s way; the new way matches {len(equal)} of them')
    for r in repeatable:
        if r['equal'] != '1':
            print(f"  differs: seed {r['game_seed']} turn {r['turn']} {r['step']}: {r['decision_upstream']} | {r['decision_new']}")
    if rows:
        def total(key): return sum(int(r[key]) for r in rows)
        print(f"copies made: upstream {total('copies_upstream'):,}, new {total('copies_new'):,}; most alive at once: upstream "
              f"{max(int(r['alive_upstream']) for r in rows)}, new {max(int(r['alive_new']) for r in rows)}; "
              f"time: upstream {total('ms_upstream') / 1000:.0f} s, new {total('ms_new') / 1000:.0f} s")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    r = sub.add_parser('run', help='play and observe seeded games, one JVM at a time')
    r.add_argument('--mode', choices=('profile', 'memory'), default='profile')
    r.add_argument('--skills', default='4,5,6', help='comma-separated; each plays itself (skill S vs skill S)')
    r.add_argument('--games', type=int, default=4, help='games per skill')
    r.add_argument('--first-game', type=int, default=0, help="schedule index of the first game (AICalibration's order)")
    r.add_argument('--pool', default='upgraded+optimized', help='ai_calibration pools joined with + (bracket 3 and 4)')
    r.add_argument('--seed', type=int, default=20261015)
    r.add_argument('--heap', default='4g')
    r.add_argument('--max-turns', type=int, default=40)
    r.add_argument('--max-seconds', type=int, default=3600)
    r.add_argument('--gc-every-ms', type=int, default=2500, help='memory mode: full GC interval')
    r.add_argument('--dump-over-mb', type=int, default=40,
                   help='memory mode: dump the heap only once the live heap is this far above the pre-game baseline')
    r.add_argument('--asprof', default=os.environ.get('ASYNC_PROFILER_HOME', ''), help='async-profiler directory')
    r.add_argument('--interval', default='10ms', help='CPU sampling interval')
    r.add_argument('--alloc', default='512k', help='allocation sampling interval in bytes')
    r.add_argument('--out', type=Path, default=OUT)
    r.add_argument('--engine-classpath', type=Path,
                   help="another engine build's runtime-classpath.txt (a saved copy, for before and after runs)")
    rep = sub.add_parser('report', help='Markdown summary')
    rep.add_argument('dirs', nargs='*', type=Path, default=[OUT])
    rep.add_argument('--asprof', default=os.environ.get('ASYNC_PROFILER_HOME', ''), help='for jfrconv')
    eq = sub.add_parser('equivalence', help="release C's search memory changes against upstream's way, at real decisions")
    eq.add_argument('--skills', default='4,5,6')
    eq.add_argument('--games', type=int, default=2, help='games per skill')
    eq.add_argument('--first-game', type=int, default=0)
    eq.add_argument('--pool', default='upgraded+optimized')
    eq.add_argument('--seed', type=int, default=20261015)
    eq.add_argument('--heap', default='4g')
    eq.add_argument('--max-turns', type=int, default=30)
    eq.add_argument('--probes', type=int, default=12, help='decisions probed per game')
    eq.add_argument('--max-nodes', type=int, default=600, help="each probe search's node limit (it has no time limit)")
    eq.add_argument('--out', type=Path, default=OUT / 'equivalence')
    hp = sub.add_parser('heap', help='Eclipse MAT retained sizes at each memory-mode heap dump')
    hp.add_argument('dirs', nargs='*', type=Path, default=[OUT / 'memory'])
    hp.add_argument('--mat', default=os.environ.get('MAT_HOME', ''), help='Eclipse MAT directory (ParseHeapDump.sh)')
    args = parser.parse_args()
    if getattr(args, 'out', None):
        args.out = args.out.resolve()  # the game JVMs run in build/ai-calibration, so a relative path would land there
    {'run': run, 'report': report, 'heap': heap, 'equivalence': equivalence}[args.command](args)


if __name__ == '__main__':
    main()
