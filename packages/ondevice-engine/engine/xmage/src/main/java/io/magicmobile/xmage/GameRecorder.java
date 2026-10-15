package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import mage.MageObject;
import mage.abilities.Ability;
import mage.abilities.Mode;
import mage.abilities.Modes;
import mage.abilities.SpecialAction;
import mage.cards.Card;
import mage.cards.CardWithSpellOption;
import mage.cards.DoubleFacedCard;
import mage.cards.SplitCard;
import mage.cards.decks.Deck;
import mage.constants.ManaType;
import mage.game.Game;
import mage.game.command.CommandObject;
import mage.game.events.Listener;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.Permanent;
import mage.game.stack.StackObject;
import mage.players.Player;
import mage.target.Target;
import mage.target.TargetAmount;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.Supplier;
import java.util.regex.Pattern;
import java.util.zip.CRC32;

/**
 * Writes or replays one game's record (docs/cloud/game-record.md) on the match's GAME thread.
 *
 * Recording never changes the game: every hook calls the same upstream code with the same arguments,
 * and a value the record cannot express stops recording ({@link GameRecord#broken}), not the game.
 * Replaying feeds the recorded decisions back and stops at the first entry that does not fit.
 *
 * XMage object IDs are random UUIDs, so entries name objects by structure, the same way in both runs:
 * {@code p<seat>} players, {@code c<n>} cards and card faces in deck load order, {@code b<k>} other
 * battlefield permanents (tokens), {@code s<k>} stack objects, {@code o<k>} command-zone objects,
 * {@code #<k>} the k-th option of the question being answered, {@code ?} an ID unknown to the game.
 */
final class GameRecorder {
    /** Tests: keep a state digest per entry, to find the first entry where a replay differs. */
    static volatile boolean trace;
    final boolean replaying;
    final GameRecord record;
    private final GameRecord.Parsed replay;
    private int cursor;
    private Game live;
    private Thread thread;
    // GAME thread only.
    private int aiDepth,concedeChecks,lastMarkTurn=-1;
    private final ArrayDeque<Character> ops=new ArrayDeque<>();
    private final Map<UUID,Prompt> prompts=new HashMap<>();
    private Map<UUID,Integer> cardIndex;
    final List<String> digests=Collections.synchronizedList(new ArrayList<>());

    private GameRecorder(boolean replaying,GameRecord record,GameRecord.Parsed replay) {
        this.replaying=replaying;this.record=record;this.replay=replay;
        // A restored record continues its turn marks.
        if(!record.marks.isEmpty()) lastMarkTurn=Integer.parseInt(record.marks.get(record.marks.size()-1).split(" ")[0]);
    }
    static GameRecorder recording(GameRecord record) { return new GameRecorder(false,record,null); }
    /** {@code ids} carries this run's player and card IDs; {@code parsed} the recorded entries. */
    static GameRecorder replaying(GameRecord ids,GameRecord.Parsed parsed) { return new GameRecorder(true,ids,parsed); }

    /** Card and card-face IDs in the order GameImpl.loadCards registers them, seat by seat, main deck first. */
    static List<UUID> cardIds(List<Deck> decks) {
        List<UUID> ids=new ArrayList<>();
        for(Deck deck:decks) for(Set<Card> cards:List.of(deck.getCards(),deck.getSideboard())) for(Card card:cards) {
            ids.add(card.getId());
            if(card instanceof SplitCard) { ids.add(((SplitCard)card).getLeftHalfCard().getId());ids.add(((SplitCard)card).getRightHalfCard().getId()); }
            else if(card instanceof DoubleFacedCard) { ids.add(((DoubleFacedCard)card).getLeftHalfCard().getId());ids.add(((DoubleFacedCard)card).getRightHalfCard().getId()); }
            else if(card instanceof CardWithSpellOption) ids.add(((CardWithSpellOption)card).getSpellCard().getId());
            else if(card.isTransformable() && card.getSecondCardFace()!=null) ids.add(card.getSecondCardFace().getId());
        }
        return ids;
    }

    /** Binds the live game and its GAME thread (again after a restore). */
    void bind(Game game,Thread gameThread) {
        live=game;thread=gameThread;
        game.addPlayerQueryEventListener(new PromptListener(this));
    }
    boolean active(Game game) { return game!=null && game==live && Thread.currentThread()==thread; }
    /** True while AI reasoning runs on the GAME thread (outside the engine calls it makes). */
    boolean inAI() { return aiDepth>0; }
    /** A decision called by rules code, not from inside another decision's AI reasoning. */
    boolean top(Game game) { return active(game) && aiDepth==0; }
    /** Recording: AI reasoning is calling into the engine. */
    boolean recordsEffect(Game game) { return !replaying && active(game) && aiDepth>0 && record.broken==null; }
    char currentOp() { Character op=ops.peek();return op==null?'?':op; }
    void enterAI(char op) { aiDepth++;ops.push(op); }
    void exitAI() { aiDepth--;ops.pop(); }
    /** Rules code the AI calls: its own decisions inside are recorded or replayed, and it draws the seeded stream. */
    <T> T engine(Supplier<T> call) {
        int saved=aiDepth;aiDepth=0;
        try { return call.get(); } finally { aiDepth=saved; }
    }
    void engineRun(Runnable call) { engine(()->{call.run();return null;}); }

    int seat(UUID playerId) {
        int seat=record.players.indexOf(playerId);
        if(seat<0) throw new IllegalStateException("Player is not seated in this record");
        return seat;
    }

    // ---- Writing ---------------------------------------------------------------------------

    void append(int seat,char op,String args) {
        if(record.broken!=null) return;
        String entry=seat+String.valueOf(op)+(args==null || args.isEmpty()?"":" "+args);
        synchronized(record) {
            int index=record.entries.size();
            mark(index);
            record.entries.add(entry);
        }
        concedeChecks=0;
    }
    /** Encodes lazily, so a value the record cannot express stops recording without touching the game. */
    void append(int seat,char op,Supplier<String> args) {
        if(record.broken!=null) return;
        String text;
        try { text=args.get(); }
        catch(RuntimeException e) { fail(op+": "+e.getMessage());return; }
        append(seat,op,text);
    }
    void fail(String reason) {
        synchronized(record) { if(record.broken==null) record.broken=reason; }
    }
    /** At the first entry of each turn: the turn, the entry index and a state digest. */
    private void mark(int index) {
        Game game=live;
        if(game==null) return;
        if(trace) digests.add(digestText(game)+" || "+hiddenText(game));
        int turn=game.getTurnNum();
        if(turn==lastMarkTurn) return;
        lastMarkTurn=turn;
        String mark=turn+" "+index+" "+digest(game);
        if(replaying) {
            String[] expected=replay.marks.get(index);
            if(expected==null || !mark.equals(String.join(" ",expected)))
                throw diverged("turn mark "+(expected==null?"missing":String.join(" ",expected))+", replay has "+mark);
        } else record.marks.add(mark);
    }
    /** Called after a restore: the replay re-creates the save and resume at this point. */
    void resumed() { if(record.broken==null) synchronized(record) { record.entries.add("-R"); } concedeChecks=0; }
    void finish(Game game,List<String> seatIds) {
        if(replaying) return;
        String end=endJson(game,seatIds,true);
        synchronized(record) { record.end=end; }
    }
    Map<String,Object> export(Game game,List<String> seatIds) {
        synchronized(record) { return record.export(record.end!=null?null:endJson(game,seatIds,false)); }
    }
    String endJson(Game game,List<String> seatIds,boolean ended) {
        List<Object> winners=new ArrayList<>(),seats=new ArrayList<>();
        for(int i=0;i<record.players.size();i++) {
            Player player=game.getPlayer(record.players.get(i));
            if(player==null) continue;
            if(player.hasWon()) winners.add(seatIds.get(i));
            seats.add(Json.map("seatId",seatIds.get(i),"life",player.getLife(),"lost",player.hasLost(),"left",player.hasLeft()));
        }
        return Json.write(Json.map("state",ended?"ended":"running","turn",game.getTurnNum(),"winners",winners,
            "seats",seats,"entries",record.entries.size(),"digest",digest(game)));
    }

    // ---- Reading (replay) ------------------------------------------------------------------

    /** Thrown on the replay's GAME thread to stop it: the record ran out, did not fit, or resumes here. */
    static final class Stop extends Error {
        private static final long serialVersionUID=1L;
        final String kind; final int index;
        Stop(String kind,int index,String message) { super(message,null,false,false);this.kind=kind;this.index=index; }
    }
    Stop diverged(String message) {
        return new Stop("diverged",cursor,"Entry "+cursor+" (turn "+(live==null?"?":live.getTurnNum())+"): "+message);
    }
    int cursor() { return cursor; }
    int recordSize() { synchronized(record) { return record.entries.size(); } }
    int size() { return replay.entries.size(); }
    String peek() { return cursor<replay.entries.size()?replay.entries.get(cursor):null; }
    /** Takes the next entry, which must be this seat's op; returns its arguments. */
    String take(int seat,char op) {
        String entry=peek();
        if(entry==null) throw new Stop("exhausted",cursor,"The record ends here");
        if(entry.length()<2 || entry.charAt(0)!=(char)('0'+seat) || entry.charAt(1)!=op)
            throw diverged("expected seat "+seat+" op "+op+", record has "+entry);
        mark(cursor);
        cursor++;concedeChecks=0;
        return entry.length()>3?entry.substring(3):"";
    }
    /** The next entry's op when it is one of this seat's {@code ops}, else 0. */
    char next(int seat,String ops) {
        String entry=peek();
        if(entry==null || entry.length()<2 || entry.charAt(0)!=(char)('0'+seat) || ops.indexOf(entry.charAt(1))<0) return 0;
        return entry.charAt(1);
    }
    /** The args of this seat's first entry with op from the cursor on, without consuming anything. */
    String lookAhead(int seat,char op) {
        for(int i=cursor;i<replay.entries.size();i++) {
            String entry=replay.entries.get(i);
            if(entry.length()>=2 && entry.charAt(0)==(char)('0'+seat) && entry.charAt(1)==op) return entry.length()>3?entry.substring(3):"";
        }
        throw new Stop("exhausted",cursor,"The record ends before this decision");
    }
    boolean resumeNext() { return "-R".equals(peek()); }
    /** Set by GameReplay: saves the parked game as a checkpoint would and stops this GAME thread. */
    volatile Runnable resumeHook;
    /** Replay, at the human question the recorded game was saved at and later restored from. */
    void resumeHere() {
        Runnable hook=resumeHook;
        if(hook==null) throw diverged("the record resumes from a save here");
        cursor++;concedeChecks=0;
        hook.run();
        throw new IllegalStateException("resume hook returned");
    }

    // ---- Concedes ----------------------------------------------------------------------------

    /** Every live checkConcede call; a concede entry says after how many calls since the previous entry. */
    void concedeCheck() { concedeChecks++; }
    void conceded(UUID playerId) { append(seat(playerId),'c',Integer.toString(concedeChecks)); }
    /** Replay: the player whose recorded concede happens at this checkConcede call, or null. */
    UUID replayConcede() {
        String entry=peek();
        if(entry==null || entry.length()<4 || entry.charAt(1)!='c' || Integer.parseInt(entry.substring(3))!=concedeChecks) return null;
        int seat=entry.charAt(0)-'0';
        take(seat,'c');
        return record.players.get(seat);
    }
    /** Replay: a concede is due at the next checkConcede call (the human's wait processes it). */
    boolean concedeDue() {
        String entry=peek();
        return entry!=null && entry.length()>=4 && entry.charAt(1)=='c' && Integer.parseInt(entry.substring(3))==concedeChecks+1;
    }

    // ---- Names -------------------------------------------------------------------------------

    String name(UUID id,Game game) {
        if(id==null) return "-";
        int seat=record.players.indexOf(id);
        if(seat>=0) return "p"+seat;
        if(cardIndex==null) {
            cardIndex=new HashMap<>();
            for(int i=0;i<record.cards.size();i++) cardIndex.put(record.cards.get(i),i);
        }
        Integer card=cardIndex.get(id);
        if(card!=null) return "c"+card;
        int k=0;
        for(Permanent permanent:game.getBattlefield().getAllPermanents()) { if(permanent.getId().equals(id)) return "b"+k; k++; }
        k=0;
        for(StackObject item:game.getStack()) { if(item.getId().equals(id)) return "s"+k; k++; }
        k=0;
        for(CommandObject object:game.getState().getCommand()) { if(object.getId().equals(id)) return "o"+k; k++; }
        k=0;
        for(SpecialAction action:game.getState().getSpecialActions()) { if(action.getId().equals(id)) return "x"+k; k++; }
        String ability=abilityName(id,game);
        if(ability!=null) return ability;
        if(game.getObject(id)==null && game.getPlayer(id)==null) return "?";
        throw new IllegalArgumentException("unnamed object "+id);
    }
    /** An ability ID a human may send at priority: {@code a<object>/<i>} for the i-th ability of a visible object. */
    private String abilityName(UUID id,Game game) {
        List<UUID> owners=new ArrayList<>();
        for(Permanent permanent:game.getBattlefield().getAllPermanents()) owners.add(permanent.getId());
        for(UUID playerId:record.players) {
            Player player=game.getPlayer(playerId);
            if(player==null) continue;
            owners.addAll(player.getHand());owners.addAll(player.getGraveyard());
        }
        for(CommandObject object:game.getState().getCommand()) owners.add(object.getId());
        for(StackObject item:game.getStack()) owners.add(item.getId());
        for(UUID owner:owners) {
            List<Ability> abilities=abilitiesOf(owner,game);
            if(abilities!=null) for(int i=0;i<abilities.size();i++)
                if(abilities.get(i).getId().equals(id)) return "a"+name(owner,game)+"/"+i;
        }
        return null;
    }
    UUID resolve(String name,Game game) {
        if(name.equals("-")) return null;
        if(name.equals("?")) return UUID.randomUUID(); // unknown to the game in both runs
        if(name.startsWith("a")) {
            int slash=name.lastIndexOf('/');
            List<Ability> abilities=abilitiesOf(resolve(name.substring(1,slash),game),game);
            int i=Integer.parseInt(name.substring(slash+1));
            if(abilities==null || i>=abilities.size()) throw diverged("no ability "+name);
            return abilities.get(i).getId();
        }
        int index=Integer.parseInt(name.substring(1));
        switch(name.charAt(0)) {
            case 'p': return record.players.get(index);
            case 'c': return record.cards.get(index);
            case 'b': return nth(game.getBattlefield().getAllPermanents(),index,name).getId();
            case 's': return nth(game.getStack(),index,name).getId();
            case 'o': return nth(game.getState().getCommand(),index,name).getId();
            case 'x': return nth(game.getState().getSpecialActions(),index,name).getId();
            default: throw diverged("unknown name "+name);
        }
    }
    private <T> T nth(Iterable<T> items,int index,String name) {
        int k=0;
        for(T item:items) if(k++==index) return item;
        throw diverged("no object "+name);
    }

    /** An ability by its source object and position in that object's abilities: {@code <source>/<i>}. */
    String abilityRef(Ability ability,Game game,UUID controllerId) {
        // The search's own "pass" action (SimulatedPlayer2), which PlayerImpl.activateAbility turns into a pass.
        if(ability instanceof mage.abilities.common.PassAbility) return "!p";
        // A commander cast from the command zone uses the command object's copy of its spell ability
        // (same ID as the card's, but with commander tax): {@code @<command object>/<i>}.
        if(ability.getZone()==mage.constants.Zone.COMMAND) {
            int k=0;
            for(CommandObject object:game.getState().getCommand()) {
                List<Ability> own=new ArrayList<>(object.getAbilities());
                for(int i=0;i<own.size();i++) if(own.get(i).getId().equals(ability.getId())) return "@"+k+"/"+i;
                k++;
            }
        }
        List<Ability> abilities=abilitiesOf(ability.getSourceId(),game);
        if(abilities!=null) {
            for(int i=0;i<abilities.size();i++) if(abilities.get(i).getId().equals(ability.getId())) return name(ability.getSourceId(),game)+"/"+i;
            for(int i=0;i<abilities.size();i++) if(abilities.get(i).getOriginalId().equals(ability.getOriginalId())) return name(ability.getSourceId(),game)+"/"+i;
        }
        if(ability instanceof SpecialAction) {
            int k=0;
            for(SpecialAction action:game.getState().getSpecialActions().getControlledBy(controllerId,true).values()) {
                if(action.getId().equals(ability.getId())) return "!m"+k;
                k++;
            }
            k=0;
            for(SpecialAction action:game.getState().getSpecialActions().getControlledBy(controllerId,false).values()) {
                if(action.getId().equals(ability.getId())) return "!a"+k;
                k++;
            }
        }
        throw new IllegalArgumentException("ability not found on its source: "+ability.getRule());
    }
    Ability resolveAbility(String ref,Game game,UUID controllerId) {
        if(ref.equals("!p")) return new mage.abilities.common.PassAbility();
        if(ref.startsWith("@")) {
            int slash=ref.indexOf('/');
            List<Ability> own=new ArrayList<>(nth(game.getState().getCommand(),Integer.parseInt(ref.substring(1,slash)),ref).getAbilities());
            int index=Integer.parseInt(ref.substring(slash+1));
            if(index>=own.size()) throw diverged("no ability "+ref);
            return own.get(index);
        }
        if(ref.startsWith("!")) {
            int index=Integer.parseInt(ref.substring(2));
            return nth(game.getState().getSpecialActions().getControlledBy(controllerId,ref.charAt(1)=='m').values(),index,ref);
        }
        int slash=ref.lastIndexOf('/');
        List<Ability> abilities=abilitiesOf(resolve(ref.substring(0,slash),game),game);
        int index=Integer.parseInt(ref.substring(slash+1));
        if(abilities==null || index>=abilities.size()) throw diverged("no ability "+ref);
        return abilities.get(index);
    }
    private static List<Ability> abilitiesOf(UUID sourceId,Game game) {
        if(sourceId==null) return null;
        Permanent permanent=game.getPermanent(sourceId);
        if(permanent!=null) return new ArrayList<>(permanent.getAbilities(game));
        Card card=game.getCard(sourceId);
        if(card!=null) return new ArrayList<>(card.getAbilities(game));
        MageObject object=game.getObject(sourceId);
        return object==null?null:new ArrayList<>(object.getAbilities());
    }

    /** Selected modes, chosen targets (with amounts), cost targets and the X payment of an ability about to be activated. */
    String describe(Ability ability,Game game) {
        StringBuilder text=new StringBuilder();
        Modes modes=ability.getModes();
        List<UUID> keys=new ArrayList<>(modes.keySet());
        List<UUID> selected=modes.getSelectedModes();
        if(modes.isPreselected()) text.append('P');
        if(modes.size()>1) {
            text.append('m');
            for(UUID id:selected) { int i=keys.indexOf(id);text.append(i<0?"?":Integer.toString(i)).append(','); }
        }
        List<UUID> described=selected.isEmpty() && modes.getMode()!=null?List.of(modes.getMode().getId()):selected;
        for(UUID id:described) {
            Mode mode=modes.get(id);
            if(mode==null) continue;
            for(Target target:mode.getTargets()) { text.append(";t");targets(text,target,game); }
        }
        for(Target target:ability.getCosts().getTargets()) { text.append(";c");targets(text,target,game); }
        if(ability.getManaCosts().containsX()) text.append(";x").append(ability.getManaCostsToPay().getText().replace(' ','_'));
        return text.length()==0?".":text.toString();
    }
    /** Sorted: upstream's option generator lists a target's combinations in hash order, so only the set is compared. */
    private void targets(StringBuilder text,Target target,Game game) {
        List<String> items=new ArrayList<>();
        for(UUID id:target.getTargets()) items.add(name(id,game)+(target instanceof TargetAmount?"*"+target.getTargetAmount(id):""));
        Collections.sort(items);
        for(String item:items) text.append(item).append(',');
        if(target.isSkipChoice()) text.append('k');
    }

    /** Targets chosen by a decision: the ones it added, or {@code =} and the whole list when it removed any. */
    String targetChange(List<UUID> before,Target target,Game game) {
        List<UUID> after=target.getTargets();
        StringBuilder text=new StringBuilder();
        List<UUID> added=new ArrayList<>();
        if(after.containsAll(before)) { for(UUID id:after) if(!before.contains(id)) added.add(id); }
        else { text.append('=');added.addAll(after); }
        for(UUID id:added) {
            text.append(name(id,game));
            if(target instanceof TargetAmount) text.append('*').append(target.getTargetAmount(id));
            text.append(',');
        }
        return text.length()==0?".":text.toString();
    }
    void applyTargets(String change,Target target,Ability source,Game game) {
        if(change.equals(".")) return;
        if(change.startsWith("=")) { target.clearChosen();change=change.substring(1); }
        for(String item:change.split(",")) {
            if(item.isEmpty()) continue;
            int star=item.indexOf('*');
            UUID id=resolve(star<0?item:item.substring(0,star),game);
            if(star>=0) target.addTarget(id,Integer.parseInt(item.substring(star+1)),source,game);
            else if(target.isNotTarget()) target.add(id,game);
            else target.addTarget(id,source,game);
        }
    }

    // ---- Human answers ----------------------------------------------------------------------

    /** The ordered options of the latest question to each player, for {@code #k} names and remembered answers. */
    private static final class Prompt {
        final List<String> options; final Object originalId,autoAnswerMessage;
        Prompt(List<String> options,Object originalId,Object autoAnswerMessage) {
            this.options=options;this.originalId=originalId;this.autoAnswerMessage=autoAnswerMessage;
        }
    }
    // Named: upstream Listener is Serializable (see XmageEngine's listeners); never written to a checkpoint.
    private static final class PromptListener implements Listener<PlayerQueryEvent> {
        private final transient GameRecorder recorder;
        PromptListener(GameRecorder recorder) { this.recorder=recorder; }
        @Override public void event(PlayerQueryEvent event) { recorder.prompted(event); }
    }
    private void prompted(PlayerQueryEvent event) {
        if(event.getQueryType()==PlayerQueryEvent.QueryType.PERSONAL_MESSAGE || !active(live)) return;
        List<String> options=new ArrayList<>();
        switch(event.getQueryType()) {
            case CHOOSE_CHOICE:
                if(event.getChoice()!=null) options.addAll(event.getChoice().isKeyChoice()?event.getChoice().getKeyChoices().keySet():event.getChoice().getChoices());
                break;
            case CHOOSE_MODE:
                if(event.getModes()!=null) for(UUID id:event.getModes().keySet()) options.add(id.toString());
                break;
            case CHOOSE_ABILITY: case PICK_ABILITY:
                if(event.getAbilities()!=null) for(Ability ability:event.getAbilities()) options.add(ability.getId().toString());
                break;
            default:
        }
        Map<String,?> eventOptions=event.getOptions()==null?Map.of():event.getOptions();
        prompts.put(event.getPlayerId(),new Prompt(options,eventOptions.get("originalId"),eventOptions.get("autoAnswerMessage")));
    }
    private Prompt prompt(UUID actingId) { Prompt p=prompts.get(actingId);return p==null?new Prompt(List.of(),null,null):p; }

    private static final Pattern UUID_TEXT=Pattern.compile("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");

    /** One human answer, as {@code <seat>h <value>[ <action>...]}. */
    void human(int seat,UUID actingId,Map<String,Object> answer,Game game) {
        append(seat,'h',()->encodeAnswer(actingId,answer,game));
    }
    private String encodeAnswer(UUID actingId,Map<String,Object> answer,Game game) {
        Prompt prompt=prompt(actingId);
        String kind=Json.requiredString(answer,"kind");Object value=answer.get("value");
        StringBuilder text=new StringBuilder();
        switch(kind) {
            case "boolean": text.append('b').append(Json.bool(value)?1:0);break;
            case "uuid": text.append('u').append(uuidName(Json.string(value),prompt,game));break;
            case "integer": text.append('i').append(Json.integer(value));break;
            case "integers": {
                text.append('n');
                for(Object n:Json.array(value)) text.append(Json.integer(n)).append(',');
                break;
            }
            case "mana": {
                Map<String,Object> mana=Json.object(value);
                text.append('m').append(Json.requiredString(mana,"manaType")).append(',')
                    .append(name(UUID.fromString(Json.requiredString(mana,"playerId")),game));
                break;
            }
            case "string": {
                if(value==null) { text.append('z');break; }
                String s=Json.string(value);
                if(!UUID_TEXT.matcher(s).find()) { text.append('s').append(encode(s));break; }
                int option=prompt.options.indexOf(s);
                if(option>=0) { text.append('k').append(option);break; }
                boolean special=s.startsWith("#");
                text.append(special?"S#":"S").append(name(UUID.fromString(special?s.substring(1):s),game));
                break;
            }
            default: throw new IllegalArgumentException("unknown answer kind "+kind);
        }
        if(answer.containsKey("actions")) for(Object item:Json.array(answer.get("actions"))) {
            Map<String,Object> action=Json.object(item);
            switch(Json.requiredString(action,"type")) {
                case "rememberAnswer": text.append(" ra").append(Json.requiredString(action,"scope").charAt(0)).append(Json.bool(action.get("answer"))?1:0);break;
                case "rememberTriggerFirst": text.append(" rt");break;
                case "passUntilStackResolved": text.append(" pu");break;
                case "autoPassAfterCast": text.append(" ac").append(Json.bool(action.get("enabled"))?1:0);break;
                case "resetRememberedAnswers": text.append(" xa");break;
                case "resetTriggerOrder": text.append(" xt");break;
                default: throw new IllegalArgumentException("unknown answer action");
            }
        }
        return text.toString();
    }
    private String uuidName(String value,Prompt prompt,Game game) {
        UUID id=UUID.fromString(value);
        try { return name(id,game); }
        catch(IllegalArgumentException unnamed) {
            int option=prompt.options.indexOf(value);
            if(option<0) throw unnamed;
            return "#"+option;
        }
    }
    private UUID resolveUuid(String name,Prompt prompt,Game game) {
        if(name.startsWith("#")) {
            int option=Integer.parseInt(name.substring(1));
            if(option>=prompt.options.size()) throw diverged("question has no option "+name);
            return UUID.fromString(prompt.options.get(option));
        }
        return resolve(name,game);
    }
    /** Replay: the next answer for this seat, as the answer map MobileHumanPlayer takes from its channel. */
    Map<String,Object> humanAnswer(int seat,UUID actingId,Game game) {
        String[] parts=take(seat,'h').split(" ");
        Prompt prompt=prompt(actingId);
        String value=parts[0];
        Map<String,Object> answer=new LinkedHashMap<>();
        switch(value.charAt(0)) {
            case 'b': answer.put("kind","boolean");answer.put("value",value.charAt(1)=='1');break;
            case 'u': answer.put("kind","uuid");answer.put("value",resolveUuid(value.substring(1),prompt,game).toString());break;
            case 'i': answer.put("kind","integer");answer.put("value",Long.parseLong(value.substring(1)));break;
            case 'n': {
                List<Object> values=new ArrayList<>();
                for(String n:value.substring(1).split(",")) if(!n.isEmpty()) values.add(Long.parseLong(n));
                answer.put("kind","integers");answer.put("value",values);break;
            }
            case 'm': {
                String[] mana=value.substring(1).split(",");
                answer.put("kind","mana");
                answer.put("value",Json.map("manaType",ManaType.valueOf(mana[0]).name(),"playerId",resolve(mana[1],game).toString()));break;
            }
            case 'z': answer.put("kind","string");answer.put("value",null);break;
            case 's': answer.put("kind","string");answer.put("value",decode(value.substring(1)));break;
            case 'k': {
                int option=Integer.parseInt(value.substring(1));
                if(option>=prompt.options.size()) throw diverged("question has no option "+value);
                answer.put("kind","string");answer.put("value",prompt.options.get(option));break;
            }
            case 'S': {
                boolean special=value.startsWith("S#");
                answer.put("kind","string");answer.put("value",(special?"#":"")+resolve(value.substring(special?2:1),game));break;
            }
            default: throw diverged("unknown answer "+value);
        }
        List<Object> actions=new ArrayList<>();
        for(int i=1;i<parts.length;i++) {
            String action=parts[i];
            switch(action.substring(0,2)) {
                case "ra": {
                    boolean ability=action.charAt(2)=='a';
                    // AnswerActions keys a remembered answer by the question's own originalId and message.
                    String key=String.valueOf(prompt.autoAnswerMessage);
                    if(ability) key=prompt.originalId+"#"+key;
                    actions.add(Json.map("type","rememberAnswer","scope",ability?"ability":"text","key",key,"answer",action.charAt(3)=='1'));
                    break;
                }
                case "rt": actions.add(Json.map("type","rememberTriggerFirst","abilityId",answer.get("value")));break;
                case "pu": actions.add(Json.map("type","passUntilStackResolved"));break;
                case "ac": actions.add(Json.map("type","autoPassAfterCast","enabled",action.charAt(2)=='1'));break;
                case "xa": actions.add(Json.map("type","resetRememberedAnswers"));break;
                case "xt": actions.add(Json.map("type","resetTriggerOrder"));break;
                default: throw diverged("unknown answer action "+action);
            }
        }
        if(!actions.isEmpty()) answer.put("actions",actions);
        return answer;
    }
    static String encode(String text) { return URLEncoder.encode(text,StandardCharsets.UTF_8).replace("+","%20"); }
    static String decode(String text) { return URLDecoder.decode(text,StandardCharsets.UTF_8); }

    /** Tests: hand and library order by card name, which the exported digest leaves out. */
    String hiddenText(Game game) {
        StringBuilder text=new StringBuilder();
        for(UUID id:record.players) {
            Player player=game.getPlayer(id);
            if(player==null) continue;
            for(Card card:player.getLibrary().getCards(game)) text.append(card.getName()).append(',');
            text.append('|');
            for(Card card:player.getHand().getCards(game)) text.append(card.getName()).append(',');
            text.append('|');
        }
        return text.toString();
    }

    // ---- State digest ------------------------------------------------------------------------

    /**
     * Eight hex digits over state both runs must share and that has no UUID in it: turn, step, active and
     * priority seats, each seat's life, counters, hand, library and graveyard sizes and flags, the
     * battlefield (sorted name, controller, tapped, power and toughness), the stack and the exile size.
     */
    String digest(Game game) {
        CRC32 crc=new CRC32();
        crc.update(digestText(game).getBytes(StandardCharsets.UTF_8));
        return String.format("%08x",crc.getValue());
    }
    private String digestText(Game game) {
        StringBuilder text=new StringBuilder();
        text.append(game.getTurnNum()).append('|').append(game.getTurnStepType()).append('|')
            .append(record.players.indexOf(game.getActivePlayerId())).append('|')
            .append(record.players.indexOf(game.getState().getPriorityPlayerId()));
        for(UUID id:record.players) {
            Player player=game.getPlayer(id);
            if(player==null) { text.append("|-");continue; }
            text.append('|').append(player.getLife()).append(',').append(player.getCountersAsCopy().getTotalCount())
                .append(',').append(player.getHand().size()).append(',').append(player.getLibrary().size())
                .append(',').append(player.getGraveyard().size()).append(',').append(player.hasLost()?1:0).append(player.hasLeft()?1:0);
        }
        List<String> permanents=new ArrayList<>();
        for(Permanent permanent:game.getBattlefield().getAllPermanents())
            permanents.add(permanent.getName()+","+record.players.indexOf(permanent.getControllerId())+","+(permanent.isTapped()?1:0)
                +","+permanent.getPower().getValue()+"/"+permanent.getToughness().getValue());
        Collections.sort(permanents);
        text.append('|').append(String.join(";",permanents)).append('|').append(game.getStack().size())
            .append('|').append(game.getExile().getAllCards(game).size());
        return text.toString();
    }
}
