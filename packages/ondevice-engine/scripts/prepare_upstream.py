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

# AI search memory (docs/LIGHTER_ENGINE_PLAN.md, step 3). Neither changes a rule or a choice: a copy of
# an AI simulation hands out the same card states as a deep copy, and the library search searches the
# same targets in the same order with the same alpha-beta. Each keeps a static switch that restores
# upstream's way for the equivalence checks (RealSearchMemoryTests, tools/ai-calibration/SearchEquivalence).
# The Modes patch (every ability copy) computes the same fields with less work.
def patch_lazy_cards(text: str) -> str:
    """Copies of an AI simulation share the source's card objects; each game copies a card on first use."""
    text=exact(text,'    protected Map<UUID, Card> gameCards = new HashMap<>();\n',
        '    protected Map<UUID, Card> gameCards = new HashMap<>();\n'
        '    // MOBILE_LAZY_CARDS: a copy of an AI simulation starts with its source\'s card objects, and from then on\n'
        '    // each of the two games copies a shared card the first time it hands it out (getCard, getCards), so the\n'
        '    // cards a simulation never touches, most of both libraries, are never copied. Null when this game owns\n'
        '    // every card in gameCards (always for the live game: only simulations are copied this way).\n'
        '    private transient Set<UUID> ownedCards;\n'
        '    // MOBILE_LAZY_CARDS: an AI handling a trigger with options copies the game in the middle of rules\n'
        '    // processing, which then goes on; those copies take their own cards, as upstream.\n'
        '    private transient int mobileTriggering;\n'
        '    /** MOBILE_LAZY_CARDS: false only in equivalence checks (every copy deep-copies its cards, as upstream). */\n'
        '    public static volatile boolean mobileLazyCards = true;\n','GameImpl.gameCards')
    text=exact(text,'        this.gameCards = CardUtil.deepCopyObject(game.gameCards);\n',
        '        if (mobileLazyCards && game.simulation && game.mobileTriggering == 0) {\n'
        '            // MOBILE_LAZY_CARDS: the deep copy\'s map and iteration order, with the source\'s card objects for now\n'
        '            this.gameCards = new HashMap<>(game.gameCards.size());\n'
        '            for (Entry<UUID, Card> entry : game.gameCards.entrySet()) {\n'
        '                this.gameCards.put(entry.getKey(), entry.getValue());\n'
        '            }\n'
        '            this.ownedCards = new HashSet<>();\n'
        '            if (game.ownedCards == null) {\n'
        '                game.ownedCards = new HashSet<>(); // the source shares them from now on as well\n'
        '            } else {\n'
        '                game.ownedCards.clear();\n'
        '            }\n'
        '        } else {\n'
        '            this.gameCards = CardUtil.deepCopyObject(game.gameCards);\n'
        '        }\n','GameImpl copy of gameCards')
    text=exact(text,'        gameCards.put(card.getId(), card);\n',
        '        gameCards.put(card.getId(), card);\n'
        '        if (ownedCards != null) {\n            ownedCards.add(card.getId()); // MOBILE_LAZY_CARDS\n        }\n',
        'GameImpl.addCardToState')
    text=exact(text,'        return gameCards.values();\n',
        '        if (ownedCards != null) {\n'
        '            // MOBILE_LAZY_CARDS: the caller reads every card, so this game takes its own copy of each first\n'
        '            for (Entry<UUID, Card> entry : gameCards.entrySet()) {\n'
        '                if (ownedCards.add(entry.getKey())) {\n'
        '                    entry.setValue(entry.getValue().copy());\n'
        '                }\n'
        '            }\n'
        '            ownedCards = null;\n'
        '        }\n'
        '        return gameCards.values();\n','GameImpl.getCards')
    text=exact(text,'        Card card = gameCards.get(cardId);\n',
        '        Card card = gameCards.get(cardId);\n'
        '        if (card != null && ownedCards != null && ownedCards.add(cardId)) {\n'
        '            card = card.copy(); // MOBILE_LAZY_CARDS: the first use of a shared card in this game\n'
        '            gameCards.put(cardId, card);\n'
        '        }\n','GameImpl.getCard')
    if text.count('player.triggerAbility(')!=4:raise ValueError('GameImpl trigger calls changed')
    text=text.replace('player.triggerAbility(','mobileTriggerAbility(player, ')
    return exact(text,'    @Override\n    public Integer getGameIndex() {',
        '    /** MOBILE_LAZY_CARDS: copies made while a player handles a trigger take their own cards. */\n'
        '    private boolean mobileTriggerAbility(Player player, TriggeredAbility ability, Game game) {\n'
        '        mobileTriggering++;\n'
        '        try {\n            return player.triggerAbility(ability, game);\n'
        '        } finally {\n            mobileTriggering--;\n        }\n    }\n\n'
        '    @Override\n    public Integer getGameIndex() {','GameImpl.getGameIndex')

def patch_search(text: str) -> str:
    """ComputerPlayer6: a library search's targets one at a time; each node's best line stays reachable."""
    text=exact(text,'                if (!game.getStack().isEmpty()) {\n                    resolve(node, depth, game);\n',
        '                if (!game.getStack().isEmpty()) {\n'
        '                    // MOBILE_SEARCH_MEMORY: this AI\'s own library search tries its targets one at a time\n'
        '                    List<UUID> searchTargets = mobileSearchMemory ? librarySearchTargets(game) : null;\n'
        '                    if (searchTargets == null) {\n'
        '                        resolve(node, depth, game);\n'
        '                    } else if (!searchTargets.isEmpty()) {\n'
        '                        val = searchTargetsOneAtATime(node, depth - 1, alpha, beta, game, searchTargets);\n'
        '                        node.setScore(val);\n'
        '                        return val;\n'
        '                    } // no target: as resolve(), the search stays on the stack and the node simulates priority\n',
        'ComputerPlayer6.addActions resolve')
    text=exact(text,'    protected void resolve(SimulationNode2 node, int depth, Game game) {',
        '    /** MOBILE_SEARCH_MEMORY: false only in equivalence checks (upstream\'s eager library search). */\n'
        '    public static volatile boolean mobileSearchMemory = true;\n\n'
        '    /**\n'
        '     * MOBILE_SEARCH_MEMORY: the targets resolve() would make one child copy each for, in its order (this AI\'s\n'
        '     * library search on top of the stack, targets not yet chosen); null when resolve() would resolve it.\n'
        '     */\n'
        '    private List<UUID> librarySearchTargets(Game game) {\n'
        '        StackObject stackObject = game.getStack().getFirstOrNull();\n'
        '        if (!(stackObject instanceof StackAbility)) {\n            return null;\n        }\n'
        '        SearchEffect effect = getSearchEffect((StackAbility) stackObject);\n'
        '        if (effect == null || !stackObject.getControllerId().equals(playerId)) {\n            return null;\n        }\n'
        '        Target target = effect.getTarget();\n'
        '        if (target.isChoiceCompleted(getId(), (StackAbility) stackObject, game, null)) {\n            return null;\n        }\n'
        '        return new ArrayList<>(target.possibleTargets(stackObject.getControllerId(), stackObject.getStackAbility(), game));\n'
        '    }\n\n'
        '    /**\n'
        '     * MOBILE_SEARCH_MEMORY: resolve()\'s children with minimaxAB() over them, but each target\'s copy is made just\n'
        '     * before it is searched and dropped unless it is the best so far, so one branch is alive at a time instead\n'
        '     * of one per eligible card. Same order, node count, alpha-beta and result as upstream, except that an\n'
        '     * interrupted search (out of time or at its copy cap) makes no more copies.\n'
        '     */\n'
        '    private int searchTargetsOneAtATime(SimulationNode2 node, int depth, int alpha, int beta, Game game, List<UUID> targetIds) {\n'
        '        StackObject stackObject = game.getStack().getFirstOrNull();\n'
        '        UUID currentPlayerId = game.getPlayerList().get();\n'
        '        SimulationNode2 bestChild = null;\n'
        '        SimulationNode2.nodeCount += targetIds.size(); // upstream creates every child before searching one\n'
        '        for (UUID targetId : targetIds) {\n'
        '            if (alpha >= beta) {\n                break;\n            }\n'
        '            if (SimulationNode2.nodeCount > MAX_SIMULATED_NODES_PER_ERROR) {\n'
        '                throw new IllegalStateException("AI ERROR: too much nodes (possible actions)");\n            }\n'
        '            if (SimulationNode2.nodeCount > maxNodes\n'
        '                    || (!COMPUTER_DISABLE_TIMEOUT_IN_GAME_SIMULATIONS && Thread.currentThread().isInterrupted())) {\n'
        '                break;\n            }\n'
        '            Game sim = game.createSimulationForAI();\n'
        '            StackAbility newAbility = (StackAbility) stackObject.copy();\n'
        '            SearchEffect newEffect = getSearchEffect(newAbility);\n'
        '            newEffect.getTarget().addTarget(targetId, newAbility, sim);\n'
        '            sim.getStack().push(sim, newAbility);\n'
        '            SimulationNode2 child = new SimulationNode2(node, sim, depth + 1, stackObject.getControllerId());\n'
        '            SimulationNode2.nodeCount--; // counted above\n'
        '            child.getTargets().add(targetId);\n'
        '            node.children.add(child);\n'
        '            Combat _combat = child.getCombat();\n'
        '            int val = addActions(child, depth - 1, alpha, beta);\n'
        '            boolean best;\n'
        '            if (!currentPlayerId.equals(playerId)) {\n'
        '                best = val < beta;\n                if (best) {\n                    beta = val;\n                }\n'
        '            } else {\n'
        '                best = val > alpha;\n                if (best) {\n                    alpha = val;\n                }\n'
        '            }\n'
        '            if (best) {\n'
        '                if (bestChild != null) {\n                    node.children.remove(bestChild);\n                }\n'
        '                bestChild = child;\n'
        '                if (node.getCombat() == null) {\n'
        '                    node.setCombat(_combat);\n                    bestChild.setCombat(_combat);\n'
        '                }\n'
        '            } else {\n'
        '                node.children.remove(child);\n'
        '            }\n'
        '            if (currentPlayerId.equals(playerId) ? val == GameStateEvaluator2.WIN_GAME_SCORE : val == GameStateEvaluator2.LOSE_GAME_SCORE) {\n'
        '                break;\n            }\n'
        '        }\n'
        '        node.children.clear();\n'
        '        if (bestChild != null) {\n            node.children.add(bestChild);\n        }\n'
        '        return currentPlayerId.equals(playerId) ? alpha : beta;\n'
        '    }\n\n'
        '    protected void resolve(SimulationNode2 node, int depth, Game game) {','ComputerPlayer6.resolve')
    # The best line so far (bestNode) stays in node.children at every depth, as upstream already keeps it at the
    # root, so the copy cap counts it; simulatePriority ends with exactly that child either way.
    keep=('\n                        } else if (mobileSearchMemory) {\n'
          '                            node.children.clear(); // MOBILE_SEARCH_MEMORY\n'
          '                            node.children.add(bestNode);\n')
    text=exact(text,'                            node.children.clear();\n                            node.children.add(bestNode);\n'
        '                            node.setScore(bestNode.getScore());\n                        }\n',
        '                            node.children.clear();\n                            node.children.add(bestNode);\n'
        '                            node.setScore(bestNode.getScore());'+keep+'                        }\n',
        'ComputerPlayer6.simulatePriority best line')
    return exact(text,'                        if (!newNode.getChildren().isEmpty()) {\n'
        '                            bestNode.setCombat(newNode.getChildren().get(0).getCombat());\n                        }\n                    }\n',
        '                        if (!newNode.getChildren().isEmpty()) {\n'
        '                            bestNode.setCombat(newNode.getChildren().get(0).getCombat());\n                        }\n'
        '                        if (mobileSearchMemory) {\n'
        '                            node.children.clear(); // MOBILE_SEARCH_MEMORY\n'
        '                            node.children.add(bestNode);\n                        }\n                    }\n',
        'ComputerPlayer6.simulatePriority opponent best line')

def patch_modes(text: str) -> str:
    """Modes' copy (in every ability copy): selected modes listed once, and a table sized for its modes."""
    text=exact(text,'    protected Modes(final Modes modes) {\n',
        '    protected Modes(final Modes modes) {\n'
        '        super(modes.size() * 4 / 3 + 1); // MOBILE_SEARCH_MEMORY: sized for its modes, not 16 (same insertion order)\n',
        'Modes copy constructor')
    return exact(text,'        this.selectedModes.addAll(modes.getSelectedModes()); // TODO: bugged - can lost multi selects here?\n'
        '        if (modes.getSelectedModes().isEmpty()) {\n',
        '        List<UUID> selected = modes.getSelectedModes(); // MOBILE_SEARCH_MEMORY: listed once, not twice\n'
        '        this.selectedModes.addAll(selected); // TODO: bugged - can lost multi selects here?\n'
        '        if (selected.isEmpty()) {\n','Modes copy of the selected modes')

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
    'Mage/src/main/java/mage/game/GameImpl.java':lambda text:patch_lazy_cards(patch_game(text)),
    'Mage/src/main/java/mage/util/RandomUtil.java':patch_random,
    'Mage.Server.Plugins/Mage.Player.AI/src/mage/player/ai/ComputerPlayer.java':patch_computer,
    'Mage.Server.Plugins/Mage.Player.AI.MAD/src/mage/player/ai/ComputerPlayer6.java':patch_search,
    'Mage/src/main/java/mage/abilities/Modes.java':patch_modes,
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
    print('Applied checked mobile patches: card factory, set registry, human response hook, checkpoint restore, named checkpoint conditions, AI search memory')
if __name__=='__main__':main()
