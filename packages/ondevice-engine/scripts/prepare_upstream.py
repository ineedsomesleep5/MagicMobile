#!/usr/bin/env python3
"""Narrow, checked source transformations. Never translates or reimplements MTG rules."""
from __future__ import annotations
import argparse, hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def java_mask(text: str) -> str:
    """Preserve positions, masking comments and string/char literals for brace matching."""
    chars=list(text);i=0
    while i<len(text):
        if text.startswith('//',i):
            end=text.find('\n',i);end=len(text) if end<0 else end
        elif text.startswith('/*',i):
            close=text.find('*/',i+2)
            if close<0: raise ValueError('Unclosed comment')
            end=close+2
        elif text[i] in ('"',"'"):
            quote=text[i];end=i+1
            while end<len(text):
                if text[end]=='\\':end+=2;continue
                if text[end]==quote:end+=1;break
                end+=1
            else:raise ValueError('Unclosed Java literal')
        else:i+=1;continue
        for j in range(i,min(end,len(chars))):
            if chars[j]!='\n':chars[j]=' '
        i=end
    return ''.join(chars)

def replace_body(text: str, signature: str, body: str) -> str:
    masked=java_mask(text)
    matches=list(re.finditer(re.escape(signature),masked))
    if len(matches)!=1:raise ValueError(f'Expected exactly one method: {signature}')
    start=masked.find('{',matches[0].end())
    if start<0:raise ValueError('Missing body')
    depth=1;end=start+1
    while end<len(masked) and depth:
        depth += (masked[end]=='{')-(masked[end]=='}');end+=1
    if depth:raise ValueError('Unbalanced braces')
    return text[:start+1]+'\n'+body+'\n    '+text[end-1:]

def patch_card(text: str) -> str:
    text=replace_body(text,'public static Card createCard(String name, CardSetInfo setInfo)',
        '        return MobileCardFactories.create(name, setInfo); // MOBILE_NATIVE_FACTORY')
    text=replace_body(text,'public static Card createCard(Class<?> clazz, CardSetInfo setInfo, List<String> errorList)',
        '        try {\n            return MobileCardFactories.create(clazz.getName(), setInfo);\n'
        '        } catch (RuntimeException e) {\n            if (errorList != null) errorList.add("Mobile card construction failed: " + clazz.getName());\n'
        '            throw e;\n        }')
    return text

def exact(text: str, old: str, new: str, what: str) -> str:
    if text.count(old)!=1:raise ValueError(what+' changed')
    return text.replace(old,new)

def patch_human(text: str) -> str:
    # Assignable, so a player read from a checkpoint gets a new response object
    # (Java deserialization leaves upstream's final transient field null).
    return exact(text,'private final transient PlayerResponse response;',
        'private void readObject(java.io.ObjectInputStream in) throws java.io.IOException, ClassNotFoundException {'
        ' in.defaultReadObject(); responseOpenedForAnswer = false; response = new PlayerResponse(); } // MOBILE_CHECKPOINT\n'
        '    protected transient PlayerResponse response; // MOBILE_RESPONSE_HOOK','HumanPlayer response field')

# Save/resume checkpoints (docs/PROTOCOL.md). Each change completes Java deserialization of
# existing state in a new process; none changes a rule, a choice or a live game.
def patch_exile(text: str) -> str:
    # A random static key differs per process, so a restored game could not find its main exile.
    return exact(text,'private static final UUID PERMANENT = UUID.randomUUID();',
        'private static final UUID PERMANENT = UUID.fromString("c276a832-6671-479c-af2d-841c8d22a391");'
        ' // MOBILE_CHECKPOINT: same main exile key in every process','Exile main zone key')

def patch_game(text: str) -> str:
    text=exact(text,'private transient final LinkedList<UUID> stackObjectsCheck = new LinkedList<>();',
        'private transient LinkedList<UUID> stackObjectsCheck = new LinkedList<>(); // MOBILE_CHECKPOINT: recreated by readObject',
        'GameImpl stack loop check')
    return exact(text,'        playerQueryEventSource = new PlayerQueryEventSource();\n        gameStates = new GameStates();\n    }',
        '        playerQueryEventSource = new PlayerQueryEventSource();\n        gameStates = new GameStates();\n'
        '        // MOBILE_CHECKPOINT: the remaining transients a live (not replay) game uses.\n'
        '        gameStatesRollBack = new HashMap<>();\n        stackObjectsCheck = new LinkedList<>();\n    }',
        'GameImpl.readObject')

def patch_random(text: str) -> str:
    text=exact(text,'private static final Random random = new Random(); // thread safe with seed support',
        'private static volatile Random random = new Random(); // thread safe with seed support;'
        ' MOBILE_CHECKPOINT: replaced only by restoreRandom','RandomUtil generator')
    return exact(text,'    public static void setSeed(long newSeed) {',
        '    /** MOBILE_CHECKPOINT: continue exactly from a generator state saved with a game. */\n'
        '    public static void restoreRandom(Random state) {\n        random = java.util.Objects.requireNonNull(state);\n    }\n\n'
        '    public static void setSeed(long newSeed) {','RandomUtil.setSeed')

def patch_computer(text: str) -> str:
    for field in ('List<PickedCard> pickedCards = new ArrayList<>();','List<ColoredManaSymbol> chosenColors = new ArrayList<>();'):
        text=exact(text,'private final transient '+field,'private transient '+field+' // MOBILE_CHECKPOINT','ComputerPlayer '+field)
    return exact(text,'private final transient Map<UUID, ManaCost> lastUnpaidMana = new LinkedHashMap<>();',
        'private transient Map<UUID, ManaCost> lastUnpaidMana = new LinkedHashMap<>(); // MOBILE_CHECKPOINT\n\n'
        '    private void readObject(java.io.ObjectInputStream in) throws java.io.IOException, ClassNotFoundException {\n'
        '        in.defaultReadObject(); // MOBILE_CHECKPOINT: upstream leaves these working collections null\n'
        '        pickedCards = new ArrayList<>();\n        chosenColors = new ArrayList<>();\n        lastUnpaidMana = new LinkedHashMap<>();\n    }',
        'ComputerPlayer lastUnpaidMana')

def patch_sets(text: str) -> str:
    return replace_body(text,'private Sets()',
        '        // MOBILE_STATIC_SETS: populated by GeneratedSetRegistry, with direct getInstance calls.\n'
        '        // No classpath/plugin scanning in the phone runtime.')

FACTORY="""package mage.cards;
/** Installed by the mobile adapter before constructing any card. */
public final class MobileCardFactories {
    public interface Factory { Card create(String name, CardSetInfo info); }
    private static volatile Factory factory;
    private MobileCardFactories() {}
    public static synchronized void install(Factory f) { factory=java.util.Objects.requireNonNull(f); }
    public static Card create(String name,CardSetInfo info) {
        Factory f=factory;
        if(f==null) throw new IllegalStateException("Mobile card factory was not installed");
        return f.create(name,info);
    }
}
"""

def git_blob(data: bytes) -> str:
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

FACTORY_PATH='Mage/src/main/java/mage/cards/MobileCardFactories.java'
# Reviewed upstream path -> transformation. upstream.lock.json lists exactly these paths.
PATCHES={
    'Mage/src/main/java/mage/cards/CardImpl.java':patch_card,
    'Mage/src/main/java/mage/cards/Sets.java':patch_sets,
    'Mage.Server.Plugins/Mage.Player.Human/src/mage/player/human/HumanPlayer.java':patch_human,
    'Mage/src/main/java/mage/game/Exile.java':patch_exile,
    'Mage/src/main/java/mage/game/GameImpl.java':patch_game,
    'Mage/src/main/java/mage/util/RandomUtil.java':patch_random,
    'Mage.Server.Plugins/Mage.Player.AI/src/mage/player/ai/ComputerPlayer.java':patch_computer,
}

def transform(sources: dict) -> dict:
    out={path:PATCHES[path](data.decode()).encode() for path,data in sources.items()}
    out[FACTORY_PATH]=FACTORY.encode()
    return out

def main() -> None:
    p=argparse.ArgumentParser();p.add_argument('checkout',type=Path);args=p.parse_args()
    checkout=args.checkout.resolve();lock=json.loads((ROOT/'upstream.lock.json').read_text())
    head=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
    if head!=lock['commit']:raise SystemExit('Wrong upstream revision; refusing to patch')
    if set(lock['sourceBlobs'])!=set(PATCHES):raise SystemExit('upstream.lock.json and the reviewed patch list differ')
    stamp=checkout/'.mobile-patch.json'
    if stamp.exists():
        recorded=json.loads(stamp.read_text())['outputs']
        pristine={path:subprocess.check_output(['git','-C',str(checkout),'show','HEAD:'+path]) for path in lock['sourceBlobs']}
        # A stamp from an older patch set must not hide missing or changed transformations.
        if recorded!={path:hashlib.sha256(data).hexdigest() for path,data in transform(pristine).items()}:
            raise SystemExit('The reviewed mobile patch set changed since this checkout was patched; '
                'remove '+str(checkout)+' and run bootstrap.sh again')
        for path,digest in recorded.items():
            if hashlib.sha256((checkout/path).read_bytes()).hexdigest()!=digest:raise SystemExit('Patched files changed; review before proceeding: '+path)
        print('Checked mobile patches already applied');return
    sources={}
    for path,expected in lock['sourceBlobs'].items():
        data=(checkout/path).read_bytes()
        if git_blob(data)!=expected:raise SystemExit('Upstream source differs from reviewed blob: '+path)
        sources[path]=data
    transformed=transform(sources)
    for path,data in transformed.items():(checkout/path).write_bytes(data)
    stamp.write_text(json.dumps({'commit':head,'outputs':{p:hashlib.sha256(b).hexdigest() for p,b in transformed.items()}},indent=2)+'\n')
    print('Applied checked mobile patches: card factory, set registry, human response hook, checkpoint restore')
if __name__=='__main__':main()
