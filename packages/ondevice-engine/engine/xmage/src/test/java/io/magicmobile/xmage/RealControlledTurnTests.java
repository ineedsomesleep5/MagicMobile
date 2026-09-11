package io.magicmobile.xmage;

import io.magicmobile.core.Json;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.g.GrizzlyBears;
import mage.constants.RangeOfInfluence;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.player.human.HumanPlayer;
import mage.players.Player;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Real-upstream proxy contract tests. The current turn_control_not_validated guard intentionally
 * makes the mobile cases fail until a mobile proxy is implemented; refusal is not a passing proxy.
 * These test the proxy seam and channels, not production seat routing or visibility projection.
 * After build_jvm.sh, from the package root:
 * CP=$(cat build/runtime-classpath.txt)
 * javac --release 17 -cp "$CP" -d build/test-real \
 *   engine/xmage/src/test/java/io/magicmobile/xmage/RealControlledTurnTests.java
 * java -Xmx512m -cp "$CP:build/test-real" io.magicmobile.xmage.RealControlledTurnTests
 */
public final class RealControlledTurnTests {
    private static int passed,failed;
    public static void main(String[] args) {
        run("upstream preserves controlled identity and checks binding",RealControlledTurnTests::upstreamReference);
        run("mobile proxy preserves controlled identity and state",RealControlledTurnTests::mobileIdentity);
        run("mobile proxy rejects mismatched controller",RealControlledTurnTests::wrongController);
        run("proxy consumes controller channel, restores target channel",RealControlledTurnTests::controllerChannel);
        run("proxy copy shares controller cancellation, not target closure",RealControlledTurnTests::copyAndCancellation);
        System.out.println("RealControlledTurnTests: "+passed+" passed, "+failed+" failed");
        if(failed!=0) throw new AssertionError("Controlled-turn proxy contract is not implemented");
    }

    private static void upstreamReference() {
        HumanPlayer controller=new HumanPlayer("Controller",RangeOfInfluence.ALL,1);
        HumanPlayer target=new HumanPlayer("Controlled",RangeOfInfluence.ALL,1);
        target.setTurnControlledBy(controller.getId());
        Player proxy=controller.prepareControllableProxy(target);
        eq(proxy.getId(),target.getId());eq(proxy.getName(),target.getName());
        eq(proxy.getTurnControlledBy(),controller.getId());check(proxy!=target,"proxy is a separate player object");
        target.setTurnControlledBy(UUID.randomUUID());
        try {controller.prepareControllableProxy(target);}
        catch(IllegalArgumentException expected) {return;}
        throw new AssertionError("Upstream must reject mismatched controller");
    }

    private static void mobileIdentity() {
        try(Fixture f=new Fixture()) {
            Card card=new GrizzlyBears(f.target.getId(),new CardSetInfo("Grizzly Bears","LEA","202",Rarity.COMMON));
            f.game.loadCards(new HashSet<>(List.of(card)),f.target.getId());
            card.setZone(Zone.HAND,f.game);f.target.getHand().add(card);
            Player proxy=f.controller.prepareControllableProxy(f.target);
            check(proxy instanceof MobileHumanPlayer,"proxy must retain mobile response transport");
            check(proxy!=f.target && proxy!=f.controller,"proxy must not mutate either original player");
            eq(proxy.getId(),f.target.getId());eq(proxy.getName(),f.target.getName());
            eq(proxy.getTurnControlledBy(),f.controller.getId());
            eq(new HashSet<>(proxy.getHand()),new HashSet<>(f.target.getHand()));
            proxy.getHand().clear();
            check(f.target.getHand().contains(card.getId()),"proxy state copy must not alias target hand");
            check(f.controller.getHand().isEmpty(),"controller must retain their own hand");
        }
    }

    private static void wrongController() {
        try(Fixture f=new Fixture()) {
            f.target.setTurnControlledBy(UUID.randomUUID());
            try {f.controller.prepareControllableProxy(f.target);}
            catch(IllegalArgumentException expected) {return;}
            throw new AssertionError("Expected the upstream controller-binding check");
        }
    }

    private static void controllerChannel() throws Exception {
        try(Fixture f=new Fixture()) {
            Player proxy=f.controller.prepareControllableProxy(f.target);
            AtomicInteger controllerConsumed=new AtomicInteger(),targetConsumed=new AtomicInteger();
            f.controller.onConsumed(controllerConsumed::incrementAndGet);
            f.target.onConsumed(targetConsumed::incrementAndGet);
            // Distinct answers expose accidental reuse of the controlled player's input channel.
            f.target.offer(Json.map("kind","integer","value",2));
            f.controller.offer(Json.map("kind","integer","value",7));
            eq(amount(proxy,f.game),7);eq(controllerConsumed.get(),1);eq(targetConsumed.get(),0);
            f.target.setGameUnderYourControl(f.game,true);
            eq(f.target.getTurnControlledBy(),f.target.getId());
            eq(amount(f.target,f.game),2);eq(targetConsumed.get(),1);
        }
    }

    private static void copyAndCancellation() throws Exception {
        try(Fixture f=new Fixture()) {
            Player proxy=f.controller.prepareControllableProxy(f.target);
            Player copy=proxy.copy();
            eq(copy.getId(),f.target.getId());eq(copy.getTurnControlledBy(),f.controller.getId());
            f.target.closeChannel();
            f.controller.offer(Json.map("kind","integer","value",6));
            eq(amount(copy,f.game),6);
            f.controller.closeChannel();
            try {amount(proxy,f.game);}
            catch(CancellationException expected) {return;}
            throw new AssertionError("Closing controller must cancel the proxy's shared channel");
        }
    }

    private static int amount(Player player,MobileCommanderGame game) throws Exception {
        ExecutorService worker=Executors.newSingleThreadExecutor(r->{
            Thread thread=new Thread(r,"GAME controlled-query-test");thread.setDaemon(true);return thread;
        });
        Future<Integer> task=worker.submit(()->player.getAmount(0,9,"Proxy channel test",null,game));
        try {return task.get(2,TimeUnit.SECONDS);}
        catch(ExecutionException e) {
            if(e.getCause() instanceof CancellationException) throw (CancellationException)e.getCause();
            throw e;
        } finally {
            task.cancel(true);worker.shutdownNow();
            check(worker.awaitTermination(1,TimeUnit.SECONDS),"proxy query worker terminated");
        }
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game=new MobileCommanderGame();
        final MobileHumanPlayer controller=new MobileHumanPlayer("Controller"),target=new MobileHumanPlayer("Controlled");
        Fixture() {
            game.getState().addPlayer(controller);game.getState().addPlayer(target);
            controller.updateRange(game);target.updateRange(game);
            target.setTurnControlledBy(controller.getId());
        }
        @Override public void close() {controller.closeChannel();target.closeChannel();}
    }
    private interface Test {void run() throws Exception;}
    private static void run(String name,Test test) {
        try {test.run();passed++;System.out.println("PASS "+name);}
        catch(Throwable e) {failed++;System.err.println("FAIL "+name+": "+e);}
    }
    private static void check(boolean condition,String message) {if(!condition) throw new AssertionError(message);}
    private static void eq(Object actual,Object expected) {if(!Objects.equals(actual,expected)) throw new AssertionError("Expected "+expected+", got "+actual);}
}
