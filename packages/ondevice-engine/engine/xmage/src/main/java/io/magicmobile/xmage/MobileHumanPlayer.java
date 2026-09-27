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
 * Requires the single visibility change applied by scripts/prepare_upstream.py.
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
    }
    private final Channel channel;
    private final UUID proxyControllerId;
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
    @Override public MobileHumanPlayer copy() { return new MobileHumanPlayer(this); }
    public void onConsumed(Runnable callback) { channel.onConsumed=Objects.requireNonNull(callback); }
    /** Runs on the GAME thread when a question to this seat ends unanswered because a player left. */
    public void onRetracted(Runnable callback) { channel.onRetracted=Objects.requireNonNull(callback); }
    /** Runs on the GAME thread when another player's concede changed the board during this wait. */
    public void onBoardChanged(Runnable callback) { channel.onBoardChanged=Objects.requireNonNull(callback); }
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
                        response.clear();
                        input.onRetracted.run();
                        return;
                    }
                    input.onBoardChanged.run();
                }
            }
        } catch(InterruptedException e) {
            Thread.currentThread().interrupt();throw new CancellationException("Mobile match interrupted");
        }
        response.clear();
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
    @Override public Player prepareControllableProxy(Player playerUnderControl) {
        if(playerUnderControl==null || !getId().equals(playerUnderControl.getTurnControlledBy()))
            throw new IllegalArgumentException("Controllable proxy must be controlled by "+getId());
        if(!(playerUnderControl instanceof PlayerImpl))
            throw new BridgeException("turn_control_unavailable","The controlled player cannot provide upstream proxy state");
        return new MobileHumanPlayer((PlayerImpl)playerUnderControl,this);
    }
}
