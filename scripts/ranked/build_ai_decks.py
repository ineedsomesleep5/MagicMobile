#!/usr/bin/env python3
"""Builds ai-decks.json: the AI opponents' decks for Quick Match and Ranked, one pool per bracket.

Each deck starts from EDHREC's average deck for a commander at that bracket (Exhibition, Core,
Upgraded, Optimized). Commanders were picked for what the XMage AI plays well: proactive creature
decks rather than stax, storm or stack tricks. Cards this XMage build doesn't have are dropped and
the gap is refilled from the same commander's other brackets, then with basic lands. A deck is then
checked against commander-brackets.json: a card that would push it above its bracket is swapped
out the same way, so every deck's computed bracket is at most its label.

Usage: build_ai_decks.py [repo] [--offline]   (EDHREC pages are cached in scripts/ranked/.edhrec-cache)
"""
import json, re, sys, time, urllib.request
from pathlib import Path

COMMANDERS = [
    # slug, commander, colors, deck names per bracket, subtitle
    ("krenko-mob-boss", "Krenko, Mob Boss", "R",
     {1: "Goblin Rabble", 2: "Goblin Mob", 3: "Goblin Warband", 4: "Goblin Horde"}, "Mono-red goblin swarm"),
    ("gishath-suns-avatar", "Gishath, Sun's Avatar", "RGW",
     {1: "Dinosaur Stampede", 2: "Sun's Avatar", 3: "Primal Thunder", 4: "Apex Predators"}, "Naya dinosaurs"),
    ("lathril-blade-of-the-elves", "Lathril, Blade of the Elves", "BG",
     {1: "Elven Patrol", 2: "Elven Blades", 3: "Elf Court", 4: "Elven Empire"}, "Golgari elves"),
    ("edgar-markov", "Edgar Markov", "RWB",
     {2: "Blood Court", 3: "Vampire Lords", 4: "Eternal Night"}, "Mardu vampires"),
    ("the-ur-dragon", "The Ur-Dragon", "WUBRG",
     {2: "Dragon Hoard", 3: "Dragonstorm", 4: "Elder Dragons"}, "Five-color dragons"),
    ("wilhelt-the-rotcleaver", "Wilhelt, the Rotcleaver", "UB",
     {2: "Rotting Dead", 3: "Zombie Tide", 4: "Necropolis"}, "Dimir zombies"),
]
VARIANTS = {1: "exhibition", 2: "core", 3: "upgraded", 4: "optimized"}
BASICS = {"W": "Plains", "U": "Island", "B": "Swamp", "R": "Mountain", "G": "Forest"}


def fetch(cache: Path, slug: str, variant: str, offline: bool):
    path = cache / f"{slug}-{variant}.json"
    if not path.exists():
        if offline: raise SystemExit(f"missing cached EDHREC page {path.name}")
        url = f"https://json.edhrec.com/pages/average-decks/{slug}/{variant}.json"
        request = urllib.request.Request(url, headers={"User-Agent": "MagicMobile deck builder (one-off)"})
        with urllib.request.urlopen(request, timeout=30) as response: path.write_bytes(response.read())
        time.sleep(0.6)
    deck = json.loads(path.read_text())["deck"]
    cards = []
    for group in deck["cards"].values():
        for name, quantity in group: cards.append((name, int(quantity)))
    return deck["commander"][0], cards


class Rules:
    def __init__(self, data):
        self.gc = set(data["gameChangers"]); self.mld = set(data["massLandDenial"])
        self.turns = set(data["extraTurns"]); self.combos = data["combos"]; self.chain = data["chainedExtraTurns"]

    def bracket(self, names):
        names = set(names); level = 2
        gc = len(names & self.gc)
        if gc: level = max(level, 3 if gc <= 3 else 4)
        if names & self.mld: level = 4
        if len(names & self.turns) >= self.chain: level = 4
        for combo in self.combos:
            if set(combo["cards"]) <= names: level = max(level, 4 if combo["early"] else 3)
        return level

    def offenders(self, names, bracket):
        """Cards to swap out so the deck's computed bracket is at most `bracket`."""
        names = set(names); out = set()
        if bracket < 4:
            out |= names & self.mld
            turns = sorted(names & self.turns)
            if len(turns) >= self.chain: out |= set(turns[self.chain - 1:])
        gcs = sorted(names & self.gc)
        allowed = 0 if bracket <= 2 else 3 if bracket == 3 else len(gcs)
        out |= set(gcs[allowed:])
        for combo in self.combos:
            if set(combo["cards"]) <= names and (bracket <= 2 or (bracket == 3 and combo["early"])):
                out.add(combo["cards"][1])
        return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    offline = "--offline" in sys.argv
    repo = Path(args[0]) if args else Path(__file__).resolve().parents[2]
    cache = repo / "scripts/ranked/.edhrec-cache"; cache.mkdir(exist_ok=True)
    catalogue = json.loads((repo / "apps/ios/MagicMobile/Resources/ondevice-catalogue.json").read_text())
    meta = catalogue["cardMetadata"]; known = {c["name"] for c in catalogue["cards"]}
    aliases = catalogue.get("nameAliases") or {}
    rules = Rules(json.loads((repo / "apps/ios/MagicMobile/Resources/commander-brackets.json").read_text()))

    def canonical(name):
        if name in known: return name
        if name in aliases: return aliases[name]
        front = name.split(" // ")[0]
        return front if front in known else None

    decks = []
    for slug, commander, colors, names, subtitle in COMMANDERS:
        identity = set(colors)
        assert canonical(commander) == commander, f"commander missing: {commander}"
        pages = {b: fetch(cache, slug, VARIANTS[b], offline) for b in names}
        # Fallback pool: every card any of this commander's brackets plays, most-played first.
        votes = {}
        for _, cards in pages.values():
            for name, _q in cards:
                c = canonical(name)
                if c and c not in BASICS.values() and c != commander: votes[c] = votes.get(c, 0) + 1

        def legal(card):
            m = meta.get(card) or {}
            return set(m.get("colorIdentity") or []) <= identity

        for bracket, name in names.items():
            page_commander, cards = pages[bracket]
            assert page_commander == commander, (page_commander, commander)
            dropped = []
            singles, basics = [], {}
            for raw, quantity in cards:
                card = canonical(raw)
                if card == commander: continue
                if card is None or not legal(card): dropped.append(raw); continue
                if card in BASICS.values(): basics[card] = basics.get(card, 0) + quantity
                elif card not in singles: singles.append(card)
            # Swap out anything above this bracket, then refill from the fallback pool.
            for _ in range(6):
                bad = rules.offenders(singles + [commander], bracket)
                if not bad: break
                singles = [c for c in singles if c not in bad]
                for candidate in sorted(votes, key=lambda c: (-votes[c], c)):
                    if len(singles) + sum(basics.values()) >= 99: break
                    if candidate in singles or candidate in bad or not legal(candidate): continue
                    if rules.bracket(singles + [commander, candidate]) > max(2, bracket): continue
                    singles.append(candidate)
            for candidate in sorted(votes, key=lambda c: (-votes[c], c)):
                if len(singles) + sum(basics.values()) >= 99: break
                if candidate in singles or not legal(candidate): continue
                if rules.bracket(singles + [commander, candidate]) > max(2, bracket): continue
                singles.append(candidate)
            # Basic lands make up the rest, split over the deck's colors.
            spread = [BASICS[c] for c in colors]
            i = 0
            while len(singles) + sum(basics.values()) < 99:
                land = spread[i % len(spread)]; basics[land] = basics.get(land, 0) + 1; i += 1
            while len(singles) + sum(basics.values()) > 99:
                land = max(basics, key=basics.get); basics[land] -= 1
                if basics[land] == 0: del basics[land]
            computed = rules.bracket(singles + [commander])
            # Bracket 1 differs from 2 by intent only: the list check stops at 2.
            assert computed <= max(2, bracket), (name, computed, bracket)
            entries = [{"name": commander, "quantity": 1, "section": "commander"}]
            entries += [{"name": c, "quantity": 1, "section": "deck"} for c in sorted(singles)]
            entries += [{"name": b, "quantity": q, "section": "deck"} for b, q in sorted(basics.items())]
            assert sum(e["quantity"] for e in entries) == 100
            decks.append({"id": f"ai-{slug}-{VARIANTS[bracket]}", "name": name, "subtitle": subtitle,
                          "colors": colors, "commander": commander, "bracket": bracket,
                          "computedBracket": computed, "entries": entries})
            print(f"{name:20} B{bracket} (computed {computed})  dropped {len(dropped)}: {', '.join(dropped[:6])}")
    out = {"schemaVersion": 1,
           "source": "EDHREC average decks by bracket, fetched 2026-10-04, limited to this XMage catalogue",
           "catalogueHash": catalogue["catalogueHash"], "decks": decks}
    target = repo / "apps/ios/MagicMobile/Resources/ai-decks.json"
    target.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"wrote {target.relative_to(repo)}: {len(decks)} decks")


if __name__ == "__main__":
    main()
