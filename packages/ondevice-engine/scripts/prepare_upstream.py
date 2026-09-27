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

# Checkpoints without serializable lambdas. The pinned GraalVM 22.1 native image fails the whole
# build when a class registered as a serialization lambdaCapturingType also creates any lambda
# without writeReplace, and a SerializedLambda is not a class the checkpoint filter should trust.
# Each Serializable Condition/Predicate lambda or method reference that upstream keeps in game
# state becomes a named enum singleton whose apply is the same upstream code (it calls the same
# static method or holds the same expression). NativeReflectionExporter fails if any remain.
CONDITION='mage.abilities.condition.Condition'
PREDICATE='mage.filter.predicate.Predicate'

def named(name: str, iface: str, params: str, body: str, indent: str, private: bool=False) -> str:
    """A nested singleton implementing a Serializable functional interface, without a lambda."""
    i=indent
    return (f'{i}/** MOBILE_CHECKPOINT: the upstream lambda as a named singleton (no SerializedLambda). */\n'
        f'{i}{"private " if private else ""}enum {name} implements {iface} {{\n{i}    instance;\n\n'
        f'{i}    @Override\n{i}    public boolean apply({params}) {{\n'
        + ''.join(f'{i}        {line}\n' for line in body.split('\n'))
        + f'{i}    }}\n{i}}}\n\n')

def lambda_free(what: str, *edits):
    """Exact (old, new) replacements; each old text must occur exactly once."""
    def patch(text: str) -> str:
        for old,new in edits: text=exact(text,old,new,what+' lambda')
        return text
    return patch

def delegate(name: str, iface: str, params: str, method: str, args: str='game, source') -> tuple:
    """Named singleton nested in a watcher, calling the watcher's existing static check."""
    return ('    static boolean '+method+'(',
        named(name,iface,params,f'return {method}({args});','    ')+'    static boolean '+method+'(')

MOBILE='// MOBILE_CHECKPOINT: named singleton, not a serializable lambda'
LAMBDA_PATCHES={
    'Mage/src/main/java/mage/abilities/keyword/ReconfigureAbility.java':lambda_free('ReconfigureUnattachAbility',
        ('this.condition = ReconfigureUnattachAbility::checkForCreature;',
         'this.condition = AttachedToCreatureCondition.instance; '+MOBILE),
        ('    private static boolean checkForCreature(Game game, Ability source) {',
         named('AttachedToCreatureCondition',CONDITION,'Game game, Ability source','return checkForCreature(game, source);','    ',True)
         +'    private static boolean checkForCreature(Game game, Ability source) {')),
    'Mage.Sets/src/mage/cards/a/ArcaneBombardment.java':lambda_free('ArcaneBombardment',
        ('filter.add(ArcaneBombardmentWatcher::checkSpell);',
         'filter.add(ArcaneBombardmentWatcher.FirstSpellPredicate.instance); '+MOBILE),
        delegate('FirstSpellPredicate',PREDICATE+'<StackObject>','StackObject input, Game game','checkSpell','input, game')),
    'Mage.Sets/src/mage/cards/c/CaptainNghathrod.java':lambda_free('CaptainNghathrod',
        ('filter2.add(CaptainNghathrodWatcher::checkCard);',
         'filter2.add(CaptainNghathrodWatcher.MilledThisTurnPredicate.instance); '+MOBILE),
        delegate('MilledThisTurnPredicate',PREDICATE+'<Card>','Card card, Game game','checkCard','card, game')),
    'Mage.Sets/src/mage/cards/f/ForTheAncestors.java':lambda_free('ForTheAncestorsEffect',
        ('filter.add((Predicate<Card>) (input, game1) -> false);',
         'filter.add(NoCardPredicate.instance); '+MOBILE),
        ('    @Override\n    public boolean apply(Game game, Ability source) {\n        Player player',
         named('NoCardPredicate','Predicate<Card>','Card input, Game game','return false;','    ',True)
         +'    @Override\n    public boolean apply(Game game, Ability source) {\n        Player player')),
    'Mage.Sets/src/mage/cards/h/HotheadedGiant.java':lambda_free('HotheadedGiant',
        ('HotheadedGiantWatcher::checkSpell, null,',
         'HotheadedGiantWatcher.NoOtherRedSpellCondition.instance, null, '+MOBILE),
        delegate('NoOtherRedSpellCondition',CONDITION,'Game game, Ability source','checkSpell')),
    'Mage.Sets/src/mage/cards/l/LeylineImmersion.java':lambda_free('LeylineImmersionConditionalMana',
        # getManaText() is the class simple name: one stable, unique name per condition, as before.
        ('addCondition((game, source) -> source instanceof SpellAbility);\n    }\n',
         'addCondition(LeylineImmersionSpellCondition.instance); '+MOBILE+'\n    }\n\n'
         +named('LeylineImmersionSpellCondition',CONDITION,'mage.game.Game game, Ability source',
                'return source instanceof SpellAbility;','    ',True).rstrip('\n')+'\n')),
    'Mage.Sets/src/mage/cards/m/MaarikaBrutalGladiator.java':lambda_free('MaarikaBrutalGladiator',
        ('filter.add(MaarikaBrutalGladiatorWatcher::checkPermanent);',
         'filter.add(MaarikaBrutalGladiatorWatcher.ExcessDamagePredicate.instance); '+MOBILE),
        delegate('ExcessDamagePredicate',PREDICATE+'<Permanent>','Permanent input, Game game','checkPermanent','input, game')),
    'Mage.Sets/src/mage/cards/n/NeyaliSunsVanguard.java':lambda_free('NeyaliSunsVanguardEffect',
        ('source.getControllerId(), NeyaliSunsVanguardWatcher::checkPlayer',
         'source.getControllerId(), NeyaliSunsVanguardWatcher.AttackedWithTokenCondition.instance '+MOBILE),
        delegate('AttackedWithTokenCondition',CONDITION,'Game game, Ability source','checkPlayer')),
    'Mage.Sets/src/mage/cards/s/SailorsBane.java':lambda_free('SailorsBaneValue',
        ('                SailorsBaneValue::checkAdventure\n',
         '                AdventurePredicate.instance '+MOBILE+'\n'),
        ('    private static boolean checkAdventure(Card input, Game game) {',
         named('AdventurePredicate',PREDICATE+'<Card>','Card input, Game game','return checkAdventure(input, game);','    ',True)
         +'    private static boolean checkAdventure(Card input, Game game) {')),
    'Mage.Sets/src/mage/cards/s/ShaileDeanOfRadiance.java':lambda_free('ShaileDeanOfRadiance',
        ('shaileFilter.add((Predicate<Permanent>) (input, game) -> !input.checkControlChanged(game));',
         'shaileFilter.add(ControlNotChangedPredicate.instance); '+MOBILE),
        ('    private ShaileDeanOfRadiance(final ShaileDeanOfRadiance card) {',
         named('ControlNotChangedPredicate','Predicate<Permanent>','Permanent input, mage.game.Game game',
               'return !input.checkControlChanged(game);','    ',True)
         +'    private ShaileDeanOfRadiance(final ShaileDeanOfRadiance card) {')),
    'Mage.Sets/src/mage/cards/s/SurgeEngine.java':lambda_free('SurgeEngineAbility',
        ('    private static final Condition staticCondition = (game, source) -> Optional\n'
         '            .ofNullable(source.getSourcePermanentIfItStillExists(game))\n'
         '            .map(permanent -> permanent.getColor(game))\n'
         '            .map(ObjectColor::isBlue)\n'
         '            .orElse(false);\n',
         '    private static final Condition staticCondition = BlueSourceCondition.instance; '+MOBILE+'\n\n'
         +named('BlueSourceCondition','Condition','Game game, Ability source',
                'return Optional\n        .ofNullable(source.getSourcePermanentIfItStillExists(game))\n'
                '        .map(permanent -> permanent.getColor(game))\n        .map(ObjectColor::isBlue)\n'
                '        .orElse(false);','    ',True).rstrip('\n')+'\n')),
    'Mage.Sets/src/mage/cards/s/SwordswornCavalier.java':lambda_free('SwordswornCavalier',
        ('SwordswornCavalierWatcher::checkPermanent, "{this} has first strike as long as " +',
         'SwordswornCavalierWatcher.AnotherKnightEnteredCondition.instance, "{this} has first strike as long as " + '+MOBILE),
        delegate('AnotherKnightEnteredCondition',CONDITION,'Game game, Ability source','checkPermanent')),
    'Mage.Sets/src/mage/cards/t/TalarasBattalion.java':lambda_free('TalarasBattalion',
        ('                TalarasBattalionWatcher::checkSpell,\n',
         '                TalarasBattalionWatcher.CastAnotherGreenSpellCondition.instance, '+MOBILE+'\n'),
        delegate('CastAnotherGreenSpellCondition',CONDITION,'Game game, Ability source','checkSpell')),
}

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
    **LAMBDA_PATCHES,
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
    print('Applied checked mobile patches: card factory, set registry, human response hook, checkpoint restore, named checkpoint conditions')
if __name__=='__main__':main()
