import io.magicmobile.xmage.MobileHumanPlayer;
import java.util.Map;

/**
 * The web build's MobileHumanPlayer (web_sources.py "ended copy"): an AI simulation's game copy that ends aborts its
 * players, and that must leave the live seat answerable (Caleb, 2026-10-26: "Mobile match stopped" until XMage ended
 * his game). Run against build/web-jvm by the CI workflow; it fails on the phone tree's MobileHumanPlayer.
 */
public final class CopyAbortCheck {
    private static boolean answerable(MobileHumanPlayer player) {
        try { player.offer(Map.of("kind","boolean","value",true)); return true; }
        catch(RuntimeException closed) { return false; }
    }
    public static void main(String[] args) {
        MobileHumanPlayer live=new MobileHumanPlayer("Live");
        live.copy().abort(); // GameImpl.end on an ended game copy
        if(!answerable(live)) { System.out.println("FAIL a copy's abort closed the live seat's channel");System.exit(1); }
        MobileHumanPlayer seat=new MobileHumanPlayer("Seat");
        seat.abort();
        if(answerable(seat)) { System.out.println("FAIL the live seat's own abort left its channel open");System.exit(1); }
        System.out.println("PASS an ended copy keeps the live seat answerable; the live seat's own abort closes it");
    }
}
