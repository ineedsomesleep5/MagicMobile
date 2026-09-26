#!/usr/bin/env python3
"""SPIKE ONLY: Java 11 copies of the adapter sources for the CheerpJ Java 11 web bundle.

Copies packages/ondevice-engine's core, xmage adapter and platform sources into a git-ignored
build folder and rewrites the six Java 16+ lines there, so `javac --release 11` accepts them.
packages/ondevice-engine itself is never written. Each replacement must match exactly once;
any upstream drift fails the build instead of producing a silently different adapter.

Usage: java11_sources.py <packages/ondevice-engine> <output dir>
Output: <out>/core, <out>/xmage, <out>/platform (source roots) and <out>/java11-patch.json.
"""
import json
import shutil
import sys
from pathlib import Path

# Stream.toList() is unmodifiable; collectingAndThen(toList(), unmodifiableList) keeps that
# (and, like toList(), accepts nulls). Pattern-matching instanceof becomes an explicit cast.
UNMODIFIABLE = ".collect(java.util.stream.Collectors.collectingAndThen(java.util.stream.Collectors.toList(),java.util.Collections::unmodifiableList))"
PATCHES = [
    ("xmage/io/magicmobile/xmage/MobileHumanPlayer.java", 78,
     "if(answer==null && game instanceof MobileCommanderGame mobile && mobile.hasConcedeRequest()) {",
     "if(answer==null && game instanceof MobileCommanderGame && ((MobileCommanderGame)game).hasConcedeRequest()) { MobileCommanderGame mobile=(MobileCommanderGame)game;"),
    ("xmage/io/magicmobile/xmage/ViewProjector.java", 38,
     ".map(player->player.getId().toString()).toList();",
     ".map(player->player.getId().toString())" + UNMODIFIABLE + ";"),
    ("xmage/io/magicmobile/xmage/ViewProjector.java", 102,
     'if(artwork.get("name") instanceof String artworkName && !artworkName.isBlank()',
     'String artworkName=artwork.get("name") instanceof String?(String)artwork.get("name"):""; if(!artworkName.isBlank()'),
    ("xmage/io/magicmobile/xmage/ViewProjector.java", 123,
     "List<String> stackOrder=view.getStack().keySet().stream().map(UUID::toString).toList();",
     "List<String> stackOrder=view.getStack().keySet().stream().map(UUID::toString)" + UNMODIFIABLE + ";"),
    ("xmage/io/magicmobile/xmage/ViewProjector.java", 155,
     '"cardTypes",template.getCardType(null).stream().map(Enum::name).toList(),',
     '"cardTypes",template.getCardType(null).stream().map(Enum::name)' + UNMODIFIABLE + ","),
    ("xmage/io/magicmobile/xmage/ViewProjector.java", 156,
     '"superTypes",template.getSuperType(null).stream().map(Enum::name).toList(),',
     '"superTypes",template.getSuperType(null).stream().map(Enum::name)' + UNMODIFIABLE + ","),
]


def main() -> None:
    engine, out = Path(sys.argv[1]), Path(sys.argv[2])
    roots = {
        "core": engine / "engine/core/src/main/java",
        "xmage": engine / "engine/xmage/src/main/java",
        "platform": engine / "platform/java",
    }
    if out.exists():
        shutil.rmtree(out)
    for name, src in roots.items():
        shutil.copytree(src, out / name)
    applied = []
    for rel, line_no, old, new in PATCHES:
        path = out / rel
        lines = path.read_text().split("\n")
        line = lines[line_no - 1]
        if line.count(old) != 1 or sum(l.count(old) for l in lines) != 1:
            sys.exit(f"java11_sources: {rel}:{line_no} no longer matches the expected Java 16+ form")
        lines[line_no - 1] = line.replace(old, new)
        path.write_text("\n".join(lines))
        applied.append({"file": rel, "line": line_no, "from": old.strip(), "to": new.strip()})
    (out / "java11-patch.json").write_text(json.dumps({"patches": applied}, indent=2) + "\n")
    print(f"java11_sources: copied {', '.join(roots)} and rewrote {len(applied)} lines in {out}")


if __name__ == "__main__":
    main()
