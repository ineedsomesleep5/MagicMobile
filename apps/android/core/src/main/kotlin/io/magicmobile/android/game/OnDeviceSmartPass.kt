package io.magicmobile.android.game

/**
 * Port of `OnDeviceSmartPass` in apps/ios/MagicMobile/OnDeviceYieldPolicy.swift. Arena-style smart pass
 * (Caleb, 2026-10-11): when this seat has priority and nothing it could do, or nothing it asked to stop
 * for, the session passes on its behalf. Local scheduling of the same ordinary pass a tap sends; XMage
 * stays the authority for what is playable.
 */
object OnDeviceSmartPass {
    /** The steps where a player can receive priority, in turn order. `key` matches iOS's raw values. */
    enum class Step(val key: String, val title: String) {
        UPKEEP("upkeep", "Upkeep"), DRAW("draw", "Draw"), MAIN1("main1", "Main 1"),
        BEGIN_COMBAT("beginCombat", "Beginning of combat"), DECLARE_ATTACKERS("declareAttackers", "Declare attackers"),
        DECLARE_BLOCKERS("declareBlockers", "Declare blockers"), COMBAT_DAMAGE("combatDamage", "Combat damage"),
        END_COMBAT("endCombat", "End of combat"), MAIN2("main2", "Main 2"), END("end", "End step");

        companion object {
            /** The engine's step name (`PRECOMBAT_MAIN`, `precombat-main`, …); null for a step that is unknown. */
            fun fromEngine(raw: String?): Step? = when (raw?.lowercase()?.replace('_', '-')) {
                "upkeep" -> UPKEEP
                "draw" -> DRAW
                "precombat-main", "main1" -> MAIN1
                "begin-combat", "combat" -> BEGIN_COMBAT
                "declare-attackers" -> DECLARE_ATTACKERS
                "declare-blockers" -> DECLARE_BLOCKERS
                "first-combat-damage", "first-strike-damage", "combat-damage" -> COMBAT_DAMAGE
                "end-combat" -> END_COMBAT
                "postcombat-main", "main2" -> MAIN2
                "end-turn", "end", "ending", "cleanup" -> END
                else -> null
            }
        }
    }

    /** A stop on one step of your turns or of your opponents' turns, stored as "mine.main1" / "theirs.end". */
    fun stopKey(step: Step, myTurn: Boolean): String = (if (myTurn) "mine." else "theirs.") + step.key

    const val ENABLED_KEY = "magicmobile.smartAutoPass"
    const val STOPS_KEY = "magicmobile.phaseStops"
    /** Off by default: smart pass lets your own spells and triggers resolve (Arena's default; engine release A). */
    const val STOP_FOR_OWN_SPELLS_KEY = "magicmobile.stopForOwnSpells"
    /** On by default (Caleb, 2026-10-21: a board wipe that took his commander went by unread): stop when an opponent's spell
     *  or ability would destroy, exile, bounce or take what you control, even with nothing to answer it (Stop for Removal). */
    const val STOP_FOR_THREATS_KEY = "magicmobile.stopForThreats"
    /** Your main phases, and your opponents' attacks and end step: where instants usually matter. */
    val defaultStops: Set<String> = setOf(stopKey(Step.MAIN1, true), stopKey(Step.MAIN2, true),
        stopKey(Step.DECLARE_ATTACKERS, false), stopKey(Step.END, false))

    data class Settings(val enabled: Boolean = true, val stops: Set<String> = defaultStops,
                        /** Stop for your own spells and triggers on the stack when you could respond to them. */
                        val stopForOwnSpells: Boolean = false,
                        /** Stop for an opponent's spell or ability that threatens your permanents, response or not. */
                        val stopForThreats: Boolean = true) {
        companion object {
            fun encode(stops: Set<String>): String = stops.sorted().joinToString(",")
            fun decode(raw: String?): Set<String> =
                raw?.split(',')?.filter { it.isNotEmpty() }?.toSet() ?: defaultStops
        }
    }

    /** What the latest poll says beyond the yield context. */
    data class Situation(val context: OnDeviceYieldPolicy.Context, val step: String?,
                         /** A land, spell or non-mana ability XMage offers this seat right now. */
                         val hasPlay: Boolean,
                         /** Mana floating in this seat's pool: passing would empty it, so the player decides. */
                         val manaFloating: Boolean,
                         /** The top of the stack is this seat's own spell or ability (engine `stackControllers`); null
                          *  when the engine doesn't say (older engines), which keeps today's stop. */
                         val topStackIsMine: Boolean? = null,
                         /** Some non-mana play could answer the stack or a pending attack (engine `respondsToStack`; a row
                          *  without the field counts as a response, so older engines keep today's stops). */
                         val hasResponse: Boolean = true,
                         /** The top of the stack is an opponent's and threatens what you control ([threatensViewer]). */
                         val threatensMe: Boolean = false)

    /** The prompt to pass, or null when the player should decide. */
    fun passPrompt(value: Situation, settings: Settings): OnDeviceYieldPolicy.Prompt? {
        val context = value.context
        val active = context.activePlayerID
        val prompt = context.prompt
        if (!settings.enabled || !context.localHumanEnabled || !context.foreground || context.phase != "running" ||
            context.turn <= 0 || !context.selfAuthority || context.resyncRequired || active.isNullOrEmpty() ||
            prompt == null || prompt.submitted || !OnDeviceYieldPolicy.ordinaryPriority(prompt, context.viewerID) ||
            value.manaFloating) return null
        // An opponent's removal or sweeper waits for you to read it and let it resolve, answer or not.
        if (!context.emptyStack && value.threatensMe && settings.stopForThreats && value.topStackIsMine != true) return null
        if (!value.hasPlay) return prompt
        // Something on the stack: your own spell or trigger resolves (unless you asked to stop for those);
        // otherwise stop only when you hold a play that actually answers it.
        if (!context.emptyStack) {
            if (value.topStackIsMine == true && !settings.stopForOwnSpells) return prompt
            return if (value.hasResponse) null else prompt
        }
        val step = Step.fromEngine(value.step) ?: return null
        // During an attack, a stop is worth making only with a play that answers it (a trick, a flash blocker).
        if (step in setOf(Step.DECLARE_ATTACKERS, Step.DECLARE_BLOCKERS, Step.COMBAT_DAMAGE) && !value.hasResponse) return prompt
        return if (stopKey(step, active == context.viewerID) in settings.stops) null else prompt
    }

    private val sweeps = listOf("destroy all", "exile all", "destroy each", "exile each", "return all", "all creatures",
        "each creature", "all nonland permanents", "each nonland permanent", "all other creatures", "sacrifices",
        "gain control of all", "gains control of all")

    /**
     * Whether the top of the stack is an opponent's spell or ability that would destroy, exile, bounce, damage or take what
     * you control: it targets one of your permanents (or you, when it is a spell), or it is an untargeted sweeper, edict or
     * steal by its rules text. A hint for when to stop and let you read, never a rules decision.
     */
    fun threatensViewer(snapshot: GameSnapshot): Boolean {
        val top = snapshot.stackTopFirst.firstOrNull() ?: return false
        val controller = top.controllerId ?: return false
        if (snapshot.isViewer(controller)) return false
        val viewer = snapshot.players.firstOrNull { snapshot.isViewer(it.playerId) } ?: return false
        val mine = viewer.zones.battlefield.flatMap { listOf(it.instanceId, it.id) }.toSet()
        val targets = (top.targetIds ?: emptyList()).toSet()
        if (targets.any { it in mine }) return true
        val isSpell = (top.objectType ?: "").uppercase() == "SPELL"
        if (isSpell && (viewer.playerId in targets || snapshot.viewerID in targets)) return true
        if (targets.isNotEmpty() || mine.isEmpty()) return false
        val text = (top.rulesText ?: "").lowercase()
        return sweeps.any { text.contains(it) }
    }

    /** Whether some non-mana play could answer what is pending (engine `respondsToStack`, missing means yes). */
    fun hasResponse(gameView: J?): Boolean {
        val objects = gameView["canPlayObjects"]["objects"].obj ?: return false
        return objects.values.any { stats ->
            stats.obj.orEmpty().any { (category, rows) ->
                rows.array.orEmpty().any { row ->
                    !(row["manaAbility"].bool ?: (category == "basicManaAbilities")) && row["respondsToStack"].bool != false
                }
            }
        }
    }

    /** Whether the top stack object is the viewer's own (engine `stackControllers` and `stackOrder`, top first);
     *  null when the engine doesn't send controllers. */
    fun topStackIsMine(root: J?, viewer: String): Boolean? {
        val controllers = root["stackControllers"].obj ?: return null
        val top = root["stackOrder"].array?.firstOrNull()?.string ?: return null
        val controller = controllers[top]?.string ?: return null
        return controller == viewer
    }

    /** Reads the engine's own playable list: lands, spells and non-mana abilities count, mana abilities don't. */
    fun hasPlay(gameView: J?): Boolean {
        val objects = gameView["canPlayObjects"]["objects"].obj ?: return false
        return objects.values.any { stats ->
            stats.obj.orEmpty().any { (category, rows) ->
                rows.array.orEmpty().any { row -> !(row["manaAbility"].bool ?: (category == "basicManaAbilities")) }
            }
        }
    }

    /** Whether this seat's raw player view shows mana in its pool. */
    fun manaFloating(player: J?): Boolean = player["manaPool"].obj.orEmpty().values.any { (it.integer ?: 0) > 0 }
}
