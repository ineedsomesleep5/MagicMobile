#!/usr/bin/env python3
"""Records the lessons (docs/LESSONS_TUTORIAL.md) from the real engine on the JVM.

  python3 scripts/lessons/record.py --engine <ondevice-engine checkout with build/> [lesson ids]

Needs a JVM engine build (packages/ondevice-engine/scripts/build_jvm.sh) and JDK 17. Writes
apps/ios/MagicMobile/Resources/Lessons/<id>.json, which Android and the web copy at build time.
"""
from __future__ import annotations
import argparse, json, os, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'packages/ondevice-engine/scripts'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from jvm_client import EngineProcess  # noqa: E402
from recorder import Catalogue, Recorder  # noqa: E402
from lessons import LESSONS  # noqa: E402

OUT = REPO / 'apps/ios/MagicMobile/Resources/Lessons'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--engine', type=Path, required=True, help='packages/ondevice-engine with a JVM build')
    parser.add_argument('--java', default=os.environ.get('JAVA', '/opt/homebrew/opt/openjdk@17/bin/java'))
    parser.add_argument('lessons', nargs='*')
    args = parser.parse_args()
    classpath = (args.engine / 'build/runtime-classpath.txt').read_text().strip()
    catalogue = Catalogue(args.engine / 'build/generated/catalogue.jsonl')
    tools = Path(tempfile.mkdtemp(prefix='lesson-cli-'))
    javac = str(Path(args.java).with_name('javac'))
    subprocess.run([javac, '--release', '17', '-cp', classpath, '-d', str(tools),
                    str(REPO / 'packages/ondevice-engine/engine/tools/LessonCli.java')], check=True, stdout=subprocess.DEVNULL)
    command = [args.java, '-Xmx768m', '-Djava.awt.headless=true', '-cp', f'{classpath}:{tools}', 'io.magicmobile.xmage.LessonCli']
    OUT.mkdir(parents=True, exist_ok=True)
    chosen = [lesson for lesson in LESSONS if not args.lessons or lesson['id'] in args.lessons]
    index = []
    for lesson in LESSONS:
        index.append({key: lesson[key] for key in ('id', 'title')})
    for lesson in chosen:
        with EngineProcess(timeout=60, command=command) as engine:
            recorder = Recorder(engine, catalogue, {key: lesson[key] for key in ('id', 'title')})
            lesson['record'](recorder)
            recorder.write(OUT / f"lesson-{lesson['id']}.json", lesson.get('focus'))
            moves = sum(1 for frame in recorder.frames if 'expect' in frame)
            size = (OUT / f"lesson-{lesson['id']}.json").stat().st_size
            print(f"{lesson['id']}: {len(recorder.frames)} frames, {moves} moves, {size // 1024} KB")
    (OUT / 'lessons.json').write_text(json.dumps({'lessons': index}, indent=1, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
