package mage.player.ai;

import mage.game.Game;
import mage.game.GameImpl;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;

/**
 * MagicMobile adapter, not upstream: the parts of an AI search tree the adapter's memory accounting reads and frees
 * (io.magicmobile.xmage.AISearchMemory). Continuing a plan reads a node's abilities, combat, player and state hash,
 * never its game copy, so a finished search's nodes can drop their copies.
 */
public final class MobileSearchNodes {
    private MobileSearchNodes() {}

    /**
     * Nodes reachable from these through children lists that still hold a game copy (each holds its own): how many,
     * and how many of those hold their own copy of every card (a deep copy, such as the live game's or one made while
     * a trigger is handled; GameImpl.mobileOwnsAllCards), which is larger than a copy that shares unused cards.
     */
    public static int[] liveGames(Iterable<SimulationNode2> from) {
        Set<SimulationNode2> seen=Collections.newSetFromMap(new IdentityHashMap<>());
        ArrayDeque<SimulationNode2> todo=new ArrayDeque<>();
        int games=0,deep=0;
        for(SimulationNode2 node:from) if(node!=null) todo.push(node);
        while(!todo.isEmpty()) {
            SimulationNode2 node=todo.pop();
            if(!seen.add(node)) continue;
            Game game=node.game;
            if(game!=null) {
                games++;
                if(!(game instanceof GameImpl) || ((GameImpl)game).mobileOwnsAllCards()) deep++;
            }
            for(SimulationNode2 child:node.children) todo.push(child);
        }
        return new int[]{games,deep};
    }

    /** Drops the game copy of every node reachable from these, and of their ancestors. */
    public static void releaseGames(Iterable<SimulationNode2> from) {
        Set<SimulationNode2> seen=Collections.newSetFromMap(new IdentityHashMap<>());
        ArrayDeque<SimulationNode2> todo=new ArrayDeque<>();
        for(SimulationNode2 node:from)
            for(SimulationNode2 up=node;up!=null;up=up.parent) todo.push(up);
        while(!todo.isEmpty()) {
            SimulationNode2 node=todo.pop();
            if(!seen.add(node)) continue;
            node.game=null;
            for(SimulationNode2 child:node.children) todo.push(child);
        }
    }
}
