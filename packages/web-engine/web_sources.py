#!/usr/bin/env python3
"""Web threading mode: copies the engine sources and rewrites them for GraalVM Web Image (docs/WEB_ENGINE_M1.md).

Reads packages/ondevice-engine and a prepared upstream checkout (scripts/prepare_upstream.py) and never writes to
either, so phone builds stay byte-for-byte unchanged. Every rewrite must match exactly as often as listed, or this
fails.

    web_sources.py <ondevice-engine dir> <prepared upstream mage dir> <output dir>

Output: <out>/core, <out>/xmage, <out>/platform (the adapter sources, rewritten where listed below) and
<out>/upstream/... (the rewritten upstream files, compiled over the upstream classes and placed before them on the
classpath). <out>/web-sources.json lists each rewrite and the SHA-256 of every input and output file, for the web
engine's own identity (docs/WEB_ENGINE_M1.md, "Engine identity").
"""
import hashlib, json, shutil, sys
from pathlib import Path

CP6 = 'Mage.Server.Plugins/Mage.Player.AI.MAD/src/mage/player/ai/ComputerPlayer6.java'
GAME = 'Mage/src/main/java/mage/game/GameImpl.java'
PLAYER = 'Mage/src/main/java/mage/players/PlayerImpl.java'
INTERRUPTED = 'Thread.currentThread().isInterrupted()'
WEB_INTERRUPTED = 'mage.util.MobileWebInterrupt.isSet()'

CP6_METHODS = '''    // MOBILE_WEB (web build only, packages/web-engine/web_sources.py): Web Image runs one thread, so the search runs
    // inline, on the game's own thread. AISearchMemory checks the deadline at every game copy and node it enters;
    // past it (or at the copy cap) it sets mage.util.MobileWebInterrupt, which the checks upstream makes for a
    // thread interrupt read instead (Thread.interrupt() does nothing on Web Image). The search unwinds, and this
    // returns as upstream does when task.get times out.
    private static boolean mobileWebSearching;
    private static long mobileWebDeadline;

    public static boolean mobileWebExpired() {
        return mobileWebSearching && System.nanoTime() - mobileWebDeadline >= 0;
    }

    /** MOBILE_WEB: the inline search's outcome, read as upstream reads its FutureTask (FutureTask needs a thread). */
    private static final class MobileWebTask {
        private Integer value;
        private Throwable failure;
        private boolean late;

        Integer get(long timeout, TimeUnit unit) throws InterruptedException, ExecutionException, TimeoutException {
            if (late) {
                throw new TimeoutException("AI search reached its deadline");
            }
            if (failure != null) {
                throw new ExecutionException(failure);
            }
            return value;
        }

        void cancel(boolean mayInterruptIfRunning) {
            // the search has already returned
        }
    }

    private MobileWebTask mobileWebRun(Callable<Integer> search) {
        int seconds = COMPUTER_DISABLE_TIMEOUT_IN_GAME_SIMULATIONS ? 3600 : maxThinkTimeSecs;
        boolean outerSearching = mobileWebSearching;
        long outerDeadline = mobileWebDeadline;
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(seconds);
        MobileWebTask task = new MobileWebTask();
        mobileWebSearching = true;
        mobileWebDeadline = deadline;
        try {
            task.value = search.call();
        } catch (Throwable e) {
            task.failure = e;
        } finally {
            mobileWebSearching = outerSearching;
            mobileWebDeadline = outerDeadline;
            task.late = System.nanoTime() - deadline >= 0;
            mage.util.MobileWebInterrupt.clear(); // the deadline's (or the copy cap's) stop was for the search only
        }
        return task;
    }

    private void printFreezeNode(SimulationNode2 root) {'''

# (file relative to the copied tree, old, new, expected matches, why)
REWRITES = [
    ('core/src/main/java/io/magicmobile/core/MatchMailbox.java',
     '        delivery=Executors.newSingleThreadExecutor(r -> {\n'
     '            Thread t=new Thread(r,"CALL mobile-"+matchId);t.setDaemon(true);return t;\n        });\n',
     '        delivery=WebThreads.inline(); // MOBILE_WEB: delivered on the caller\'s thread, inside the respond request\n',
     1, 'CALL thread: answers are delivered synchronously'),
    ('xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java',
     '            worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME mobile-"+game.getId());t.setDaemon(true);return t;});\n',
     '            worker=WebThreads.deferred(); // MOBILE_WEB: the game runs after create\'s reply, on the worker\'s thread\n',
     1, 'GAME thread: the worker\'s own thread, after the request that created the match'),
    ('xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java',
     '            cancellation.runIfOpen(()->{mailbox.publishSnapshots(views);left.forEach(mailbox::retract);});\n        }\n',
     '            cancellation.runIfOpen(()->{mailbox.publishSnapshots(views);left.forEach(mailbox::retract);});\n'
     '            WebThreads.servePending(); // MOBILE_WEB: a poll sees each published snapshot, AI turns included\n        }\n',
     1, 'polls during AI turns: one waiting request is served at each published snapshot'),
    ('xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java',
     '            if(task!=null) task.cancel(true);\n',
     '            if(task!=null) task.cancel(false); // MOBILE_WEB: never interrupt the only thread; the game stops at hasEnded()\n',
     1, 'close: no interrupt (it would hit the request loop itself)'),
    ('xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java',
     '                answer=input.answers.poll(250,TimeUnit.MILLISECONDS);\n',
     '                answer=WebThreads.awaitAnswer(input.answers); // MOBILE_WEB: serves the page (Atomics.wait) until answered\n',
     1, 'human question: blocks in the host channel, serving requests, instead of a timed queue poll'),
    # An AI simulation copies the live game, MobileHumanPlayer included, and a copy shares the live seat's input channel.
    # When the copy ends (a player loses in it: CombatUtil.willItSurviveSimple, the AI choosing blocks), GameImpl.end
    # aborts its players and the live human's channel closed: every later question threw "Mobile match stopped" until
    # XMage ended the game (Caleb, 2026-10-26, about to win with his commander). Phones have the same bug; their fix
    # is commit ccd1365a (branch claude/engine-copy-abort-channel), for their own engine release.
    ('xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java',
     '    private transient Channel channel;\n',
     '    private transient Channel channel;\n'
     '    /** MOBILE_WEB: true for the live seat (constructed or restored), false for copies and proxies. */\n'
     '    private transient boolean ownsChannel;\n',
     1, 'ended copy: only the live seat owns its channel'),
    ('xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java',
     '        channel=new Channel();\n',
     '        channel=new Channel();ownsChannel=true; // MOBILE_WEB: the live seat\n',
     1, 'ended copy: a constructed seat owns its channel'),
    ('xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java',
     '        channel=new Channel(); // HumanPlayer.readObject',
     '        channel=new Channel();ownsChannel=true; // MOBILE_WEB: a restored seat owns its channel. HumanPlayer.readObject',
     1, 'ended copy: a restored seat owns its channel'),
    ('xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java',
     '    @Override public void abort() { closeChannel();super.abort(); }\n',
     '    // MOBILE_WEB: GameImpl.end aborts every player of the game that ended; a copy\'s end leaves the live seat answerable.\n'
     '    @Override public void abort() { if(ownsChannel) closeChannel();super.abort(); }\n',
     1, 'ended copy: abort closes the channel only on the live seat (Running.close still closes it)'),
    ('xmage/src/main/java/io/magicmobile/xmage/Checkpoints.java',
     '            if(available==null) available=selfTest();\n',
     '            if(available==null) available=false; // MOBILE_WEB: Java serialization traps the Wasm instance; no self-test\n',
     1, 'saveResume false without running the serialization self-test'),
    ('xmage/src/main/java/io/magicmobile/xmage/AISearchMemory.java',
     '            Thread.currentThread().interrupt(); // as upstream\'s timeout: the search unwinds and scores what it has\n',
     '            mage.util.MobileWebInterrupt.set(); // MOBILE_WEB: as upstream\'s timeout, the search unwinds and scores what it has\n',
     1, 'copy cap: stop flag instead of a thread interrupt'),
    ('xmage/src/main/java/io/magicmobile/xmage/AISearchMemory.java',
     '    volatile boolean abandoned;\n',
     '    volatile boolean abandoned;\n'
     '    /** MOBILE_WEB: the inline search passed its deadline (ComputerPlayer6.mobileWebExpired) and is unwinding. */\n'
     '    private boolean outOfTime;\n',
     1, 'AI deadline state'),
    ('xmage/src/main/java/io/magicmobile/xmage/AISearchMemory.java',
     '        } else if(memory.abandoned) throw new Stopped("AI search abandoned");\n        memory.running.push(node);\n',
     '        } else if(memory.abandoned) throw new Stopped("AI search abandoned");\n'
     '        // MOBILE_WEB: past the deadline, upstream\'s stop checks make this node score what it has.\n'
     '        if(mage.player.ai.ComputerPlayer6.mobileWebExpired()) mage.util.MobileWebInterrupt.set();\n'
     '        memory.running.push(node);\n',
     1, 'AI deadline checked at every node'),
    ('xmage/src/main/java/io/magicmobile/xmage/AISearchMemory.java',
     '        if(capped) throw new Stopped("AI search at its copy cap");\n',
     '        if(capped) throw new Stopped("AI search at its copy cap");\n'
     '        // MOBILE_WEB: the inline search\'s deadline, checked at every game copy: past it, the search unwinds as on\n'
     '        // upstream\'s timeout and, as a capped one, makes no further copy.\n'
     '        if(outOfTime) throw new Stopped("AI search out of time");\n'
     '        if(mage.player.ai.ComputerPlayer6.mobileWebExpired()) { outOfTime=true;mage.util.MobileWebInterrupt.set(); }\n',
     1, 'AI deadline checked at every game copy'),
    ('xmage/src/main/java/io/magicmobile/xmage/GameRecorder.java',
     '        CRC32 crc=new CRC32();\n',
     '        java.util.zip.Checksum crc=new io.magicmobile.core.WebCrc32(); // MOBILE_WEB: no native zip library\n',
     2, 'game record checksums: plain-Java CRC-32, same values'),
    ('platform/java/mage/cards/repository/MobileCardCatalogue.java',
     'new GZIPInputStream(stream)',
     'io.magicmobile.core.WebInflate.gunzip(stream) /* MOBILE_WEB: no native zip library */',
     1, 'card catalogue: plain-Java gzip'),
    ('platform/java/mage/cards/MobileExpansionSet.java',
     'new GZIPInputStream(stream)',
     'io.magicmobile.core.WebInflate.gunzip(stream) /* MOBILE_WEB: no native zip library */',
     1, 'set catalogue: plain-Java gzip'),
]
UPSTREAM_REWRITES = [
    (CP6, '        FutureTask<Integer> task = new FutureTask<>(() -> addActions(root, maxDepth, Integer.MIN_VALUE, Integer.MAX_VALUE));\n'
          '        threadPoolSimulations.execute(task);\n',
     '        // MOBILE_WEB: inline on this thread, until its deadline, instead of on threadPoolSimulations\n'
     '        MobileWebTask task = mobileWebRun(() -> addActions(root, maxDepth, Integer.MIN_VALUE, Integer.MAX_VALUE));\n',
     1, 'AI search: inline instead of on threadPoolSimulations'),
    (CP6, '    private void printFreezeNode(SimulationNode2 root) {', CP6_METHODS, 1, 'AI search deadline'),
    (CP6, INTERRUPTED, WEB_INTERRUPTED, 4, 'AI search stop checks: the web stop flag'),
    (GAME, INTERRUPTED, WEB_INTERRUPTED, 1, 'simulated game ends when its search stops'),
    (PLAYER, INTERRUPTED, WEB_INTERRUPTED, 1, 'simulated players stop responding when their search stops'),
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def apply(files: dict, rewrites: list, root: Path, log: list) -> None:
    for rel, old, new, expected, why in rewrites:
        path = root / rel
        text = files.setdefault(path, path.read_text(encoding='utf-8'))
        count = text.count(old)
        if count != expected:
            sys.exit(f'web_sources.py: expected {expected} match(es) in {rel} for "{why}", found {count}')
        files[path] = text.replace(old, new)
        log.append({'file': rel, 'why': why, 'matches': expected})


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    engine, upstream, out = (Path(a).resolve() for a in sys.argv[1:])
    if not (upstream / '.mobile-patch.json').is_file():
        sys.exit('web_sources.py: run scripts/prepare_upstream.py on the upstream checkout first')
    if out.exists():
        shutil.rmtree(out)
    trees = {'core': engine / 'engine/core', 'xmage': engine / 'engine/xmage', 'platform': engine / 'platform'}
    for name, src in trees.items():
        shutil.copytree(src, out / name, ignore=shutil.ignore_patterns('test', '*.class'))
    log, files, upstream_files = [], {}, {}
    apply(files, REWRITES, out, log)
    apply(upstream_files, UPSTREAM_REWRITES, upstream, log)
    for path, text in files.items():
        path.write_text(text, encoding='utf-8')
    written = list(files)
    for path, text in upstream_files.items():
        target = out / 'upstream' / path.relative_to(upstream)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding='utf-8')
        written.append(target)
    for path in written:
        if 'MOBILE_WEB' not in path.read_text(encoding='utf-8') and 'MobileWebInterrupt' not in path.read_text(encoding='utf-8'):
            sys.exit(f'web_sources.py: {path} has no MOBILE_WEB marker')
    inputs = sorted(p for tree in trees.values() for p in tree.rglob('*.java') if '/test/' not in str(p))
    manifest = {
        'rewrites': log,
        'inputs': {str(p.relative_to(engine)): sha(p) for p in inputs}
                  | {'upstream/' + rel: sha(upstream / rel) for rel in (CP6, GAME, PLAYER)},
        'outputs': {str(p.relative_to(out)): sha(p) for p in sorted(out.rglob('*.java'))},
    }
    (out / 'web-sources.json').write_text(json.dumps(manifest, indent=1, sort_keys=True) + '\n', encoding='utf-8')
    print(f'web_sources.py: {len(log)} rewrites in {len(written)} files -> {out}')


if __name__ == '__main__':
    main()
