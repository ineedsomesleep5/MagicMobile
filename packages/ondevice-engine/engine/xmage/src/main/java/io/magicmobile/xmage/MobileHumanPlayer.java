package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.constants.*;
import mage.game.Game;
import mage.player.human.HumanPlayer;
import mage.player.human.PlayerResponse;
import mage.players.Player;
import mage.players.PlayerImpl;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Consumer;

/**
 * Retains HumanPlayer's rule/choice logic. Replaces only the desktop wait/notify transport.
 * Requires the response hook applied by scripts/prepare_upstream.py.
 * No response mutates XMage off its GAME thread. Copies share the input channel, as
 * vanilla HumanPlayer copies share PlayerResponse. Interrupted/closed games abort,
 * never auto-answer a choice or fall back to a simulator.
 */
public final class MobileHumanPlayer extends HumanPlayer {
    private static final class Channel {
        final BlockingQueue<Map<String,Object>> answers=new ArrayBlockingQueue<>(1);
        volatile boolean closed;
        volatile Runnable onConsumed=() -> {};
        volatile Runnable onRetracted=() -> {};
        volatile Runnable onBoardChanged=() -> {};
        volatile Runnable onIdle=() -> {};
    }
    private static final long serialVersionUID=1L;
    // Transient: a checkpoint keeps the rules state only; a restored seat gets a new channel.
    private transient Channel channel;
    private final UUID proxyControllerId;
    /** GAME thread: set on entering priority(), consumed by the first question it publishes. */
    private transient boolean firstPriorityQuestion;
    public MobileHumanPlayer(String name) {
        super(name,RangeOfInfluence.ALL,1);
        channel=new Channel();
        proxyControllerId=null;
        userData=mage.players.net.UserData.getDefaultUserDataView();
    }
    private MobileHumanPlayer(MobileHumanPlayer source) {
        super(source);channel=source.channel;proxyControllerId=source.proxyControllerId;
    }
    private MobileHumanPlayer(PlayerImpl controlled,MobileHumanPlayer controller) {
        // Upstream copies the acted player's rules state but retains the controller's response.
        super(controlled,controller.response);
        channel=controller.channel;proxyControllerId=controller.getId();
    }
    private void readObject(java.io.ObjectInputStream in) throws java.io.IOException, ClassNotFoundException {
        in.defaultReadObject();
        channel=new Channel(); // HumanPlayer.readObject (prepare_upstream.py) recreates the response.
    }
    @Override public MobileHumanPlayer copy() { return new MobileHumanPlayer(this); }
    @Override public boolean priority(Game game) {
        firstPriorityQuestion=true;
        try { return super.priority(game); }
        finally { firstPriorityQuestion=false; }
    }
    /**
     * True once per priority() call, for the first question it publishes: the save/resume safe
     * point, between actions. Later questions in the same call are not safe points.
     */
    boolean takeFirstPriorityQuestion() {
        boolean first=firstPriorityQuestion;
        firstPriorityQuestion=false;
        return first;
    }
    public void onConsumed(Runnable callback) { channel.onConsumed=Objects.requireNonNull(callback); }
    /** Runs on the GAME thread when a question to this seat ends unanswered because a player left. */
    public void onRetracted(Runnable callback) { channel.onRetracted=Objects.requireNonNull(callback); }
    /** Runs on the GAME thread when another player's concede changed the board during this wait. */
    public void onBoardChanged(Runnable callback) { channel.onBoardChanged=Objects.requireNonNull(callback); }
    /**
     * Runs on the GAME thread about every 250 ms while this seat's question waits for an answer,
     * with the game parked where the question was published (after onBoardChanged, if a concede
     * changed it). Save requests are written here (docs/PROTOCOL.md), never on another thread.
     */
    public void onIdle(Runnable callback) { channel.onIdle=Objects.requireNonNull(callback); }
    public void offer(Map<String,Object> answer) {
        if(channel.closed || !channel.answers.offer(Json.object(Json.freeze(answer))))
            throw new BridgeException("response_channel_unavailable","Player response channel is closed or full");
    }
    @Override public void abort() { closeChannel();super.abort(); }
    public void closeChannel() { channel.closed=true;channel.answers.clear(); }
    @Override protected void waitForResponse(Game game) {
        if(isExecutingMacro()) throw new BridgeException("unsupported_macro","Desktop input macros are not enabled on mobile");
        Player acting=game.getPlayer(getId());
        if(acting==null) throw new BridgeException("unbound_player","The acting player is not in this game");
        UUID controllerId=acting.getTurnControlledBy();
        if(proxyControllerId!=null && !proxyControllerId.equals(controllerId))
            throw new BridgeException("stale_control_proxy","Turn control changed; this proxy can no longer answer");
        Player controller=game.getPlayer(controllerId);
        if(!(controller instanceof MobileHumanPlayer))
            throw new BridgeException("turn_control_unavailable","The controlling player has no mobile input channel");
        if(!controller.getId().equals(controller.getTurnControlledBy()))
            throw new BridgeException("nested_turn_control_not_supported","A controlled player cannot supply another player's mobile answers");
        // Ordinary HumanPlayer-under-HumanPlayer calls do not create proxies upstream.
        // Resolve the current controller on each wait, so reset restores the original seat's channel.
        Channel input=((MobileHumanPlayer)controller).channel;
        Map<String,Object> answer=null;
        try {
            while(answer==null) {
                if(input.closed || Thread.currentThread().isInterrupted())
                    throw new CancellationException("Mobile match stopped");
                answer=input.answers.poll(250,TimeUnit.MILLISECONDS);
                if(answer==null && game instanceof MobileCommanderGame mobile && mobile.hasConcedeRequest()) {
                    // As upstream's async concede: process it on this GAME thread, then keep
                    // waiting unless the asked player (or its controller) left or the game ended.
                    mobile.checkConcede();
                    Player asked=game.getPlayer(getId());
                    if(game.hasEnded() || asked==null || !asked.isInGame() || !controller.isInGame()) {
                        response.resetAnswers();
                        input.onRetracted.run();
                        return;
                    }
                    input.onBoardChanged.run();
                }
                if(answer==null) input.onIdle.run();
            }
        } catch(InterruptedException e) {
            Thread.currentThread().interrupt();throw new CancellationException("Mobile match interrupted");
        }
        response.resetAnswers();
        // Standing instructions validated against this prompt (AnswerActions), applied on the GAME thread before the
        // answer itself. A pass action's own skip() marks the response; the answer below is the same pass.
        if(answer.containsKey("actions")) applyActions(Json.array(answer.get("actions")),game,(MobileHumanPlayer)controller);
        String kind=Json.requiredString(answer,"kind");Object value=answer.get("value");
        switch(kind) {
            case "boolean": response.setBoolean(Json.bool(value));break;
            case "uuid": response.setUUID(UUID.fromString(Json.string(value)));break;
            case "string": response.setString(value==null ? null : Json.string(value));break;
            case "integer": response.setInteger(Math.toIntExact(Json.integer(value)));break;
            case "integers":
                // MultiAmountType.parseAnswer consumes SPACE-separated integers, not an array.
                List<String> values=new ArrayList<>();
                for(Object n:Json.array(value)) values.add(Long.toString(Json.integer(n)));
                response.setString(String.join(" ",values));break;
            case "mana":
                Map<String,Object> mana=Json.object(value);
                response.setManaType(ManaType.valueOf(Json.requiredString(mana,"manaType")));
                response.setResponseManaPlayerId(UUID.fromString(Json.requiredString(mana,"playerId")));break;
            default: throw new BridgeException("unsupported_response","Unknown response type");
        }
        input.onConsumed.run();
    }
    /**
     * XMage desktop player actions, already validated and keyed by AnswerActions. Remembered answers and trigger order
     * belong to the player answering this question; passing after a cast is the controlling user's preference, as
     * HumanPlayer.priority reads it through getControllingPlayersUserData.
     */
    private void applyActions(List<Object> actions,Game game,MobileHumanPlayer controller) {
        for(Object item:actions) {
            Map<String,Object> action=Json.object(item);
            switch(Json.requiredString(action,"type")) {
                case "resetRememberedAnswers": sendPlayerAction(PlayerAction.REQUEST_AUTO_ANSWER_RESET_ALL,game,null);break;
                case "resetTriggerOrder": sendPlayerAction(PlayerAction.TRIGGER_AUTO_ORDER_RESET_ALL,game,null);break;
                case "rememberAnswer": {
                    boolean ability=Json.requiredString(action,"scope").equals("ability"), yes=Json.bool(action.get("answer"));
                    PlayerAction remember=ability
                        ? (yes?PlayerAction.REQUEST_AUTO_ANSWER_ID_YES:PlayerAction.REQUEST_AUTO_ANSWER_ID_NO)
                        : (yes?PlayerAction.REQUEST_AUTO_ANSWER_TEXT_YES:PlayerAction.REQUEST_AUTO_ANSWER_TEXT_NO);
                    sendPlayerAction(remember,game,Json.requiredString(action,"key"));break;
                }
                case "rememberTriggerFirst":
                    sendPlayerAction(PlayerAction.TRIGGER_AUTO_ORDER_ABILITY_FIRST,game,UUID.fromString(Json.requiredString(action,"abilityId")));break;
                case "passUntilStackResolved": sendPlayerAction(PlayerAction.PASS_PRIORITY_UNTIL_STACK_RESOLVED,game,null);break;
                case "autoPassAfterCast": controller.userData.setPassPriorityCast(Json.bool(action.get("enabled")));break;
                default: throw new BridgeException("unsupported_response","Unknown answer action");
            }
        }
    }
    @Override public Player prepareControllableProxy(Player playerUnderControl) {
        if(playerUnderControl==null || !getId().equals(playerUnderControl.getTurnControlledBy()))
            throw new IllegalArgumentException("Controllable proxy must be controlled by "+getId());
        if(!(playerUnderControl instanceof PlayerImpl))
            throw new BridgeException("turn_control_unavailable","The controlled player cannot provide upstream proxy state");
        return new MobileHumanPlayer((PlayerImpl)playerUnderControl,this);
    }
}
