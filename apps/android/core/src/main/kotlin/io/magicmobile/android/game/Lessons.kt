package io.magicmobile.android.game

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The lessons (docs/LESSONS_TUTORIAL.md): short scripted games recorded from the real engine
 * (scripts/lessons/record.py), played back on the real board. [LessonTransport] stands where the
 * engine would: it answers the board's polls with the recorded views and accepts only the move the
 * recording made. Port of iOS Lessons.swift; the web's lessons.ts reads the same files.
 */
object LessonText {
    const val TITLE = "Lessons"
    const val COACH = "Maren"
    const val GOT_IT = "Got it"
    const val NEXT = "Next Lesson"
    const val DONE = "Done"
    const val COMPLETE = "Lesson complete"
    const val ALL_COMPLETE = "You know the basics. Play a guided game against an easy AI next, with tips as you go."
    const val NUDGE = "Not that one. Follow the glow."
    const val GUIDED = "Guided game"
}

/** What the coach says on a frame: a title, a sentence or two, and what it points at. */
data class LessonCoach(val title: String?, val text: String, val spot: String?, val gesture: String?) {
    companion object {
        fun from(value: J?): LessonCoach? {
            val text = value["text"].string ?: return null
            return LessonCoach(value["title"].string, text, value["spot"].string, value["gesture"].string)
        }
    }
}

data class LessonInfo(val id: String, val title: String)

object LessonCatalog {
    const val KEY = "magicmobile.lessons.completed"

    /** lessons.json: the lessons in order. */
    fun parse(bytes: ByteArray): List<LessonInfo> =
        (EngineJson.decode(bytes)["lessons"].array ?: emptyList()).mapNotNull { row ->
            LessonInfo(row["id"].string ?: return@mapNotNull null, row["title"].string ?: return@mapNotNull null)
        }

    fun next(after: String, all: List<LessonInfo>): LessonInfo? =
        all.indexOfFirst { it.id == after }.takeIf { it >= 0 && it + 1 < all.size }?.let { all[it + 1] }
}

class LessonFrame(
    var poll: J,
    var expect: J?,
    val note: Boolean,
    /** A note that waits for the board to show this player (by name) instead of for Got it. */
    val focus: String?,
    val complete: Boolean,
    val coach: LessonCoach?,
    /** How long the board shows a frame that moves on by itself, in milliseconds. */
    val hold: Long,
) {
    val ended: Boolean get() = poll["phase"].string == "ended"
}

/** One lesson file: the recorded learner's view after each change, and the moves it waits for. */
class LessonScript(value: J) {
    val id: String
    val title: String
    val capabilities: J
    val create: J
    val viewer: String
    val frames: List<LessonFrame>
    val matchID: String get() = create["matchId"].string ?: ""

    init {
        val rows = value["frames"].array
        if (value["format"].string != "magicmobile-lesson" || value["version"].integer != 1L || rows.isNullOrEmpty())
            throw EngineError.InvalidMessage("This lesson file can't be read.")
        id = value["id"].string ?: throw EngineError.InvalidMessage("This lesson file can't be read.")
        title = value["title"].string ?: id
        capabilities = value["capabilities"] ?: JsonObject(emptyMap())
        create = value["create"] ?: JsonObject(emptyMap())
        viewer = value["viewer"].string ?: throw EngineError.InvalidMessage("This lesson file can't be read.")
        var previous: J? = null
        frames = rows.mapNotNull { row ->
            val poll = row["poll"] ?: return@mapNotNull null
            LessonFrame(poll, row["expect"], row["note"].bool == true, row["focus"].string, row["complete"].bool == true,
                LessonCoach.from(row["coach"]), hold(poll, previous)).also { previous = poll }
        }
    }

    companion object {
        /** Something happened on the table (a spell, an attack, a life change): long enough to see it. A step passing: brief. */
        fun hold(poll: J, previous: J?): Long {
            if (previous == null || poll["phase"].string == "ended") return 400
            fun table(poll: J): List<J?> {
                val view = poll["snapshot"]["gameView"]
                val players = view["players"].array ?: emptyList()
                return listOf(view["stack"], view["combat"], JsonArray(players.map { it["life"] ?: JsonNull }),
                    JsonArray(players.map { it["battlefield"] ?: JsonNull }), JsonArray(players.map { it["graveyard"] ?: JsonNull }))
            }
            return if (table(poll) == table(previous)) 350 else 1100
        }
    }
}

/** What the coach's spot names on a frame: the expected card when it carries that name, else every card with it. */
object LessonSpot {
    val CONTROLS = setOf("primary", "medallion", "yes")

    data class Focus(val ids: Set<String> = emptySet(), val control: String? = null) {
        val isEmpty: Boolean get() = ids.isEmpty() && control == null
    }

    fun resolve(spot: String?, poll: J, expect: J?): Focus {
        if (spot == null) return Focus()
        if (spot in CONTROLS) return Focus(control = spot)
        val view = poll["snapshot"]["gameView"]
        val named = mutableListOf<String>()
        view["myHand"].obj?.forEach { (id, card) -> if (card["name"].string == spot) named += id }
        for (player in view["players"].array ?: emptyList()) {
            if (player["name"].string == spot) player["playerId"].string?.let { return Focus(setOf(it)) }
            player["battlefield"].obj?.forEach { (id, card) ->
                if (card["name"].string == spot && card["tapped"].bool != true) named += id
            }
        }
        val expected = expect["value"].string
        if (expected != null && expected in named) return Focus(setOf(expected))
        return Focus(named.toSet())
    }
}

/** What the board shows for the lesson: the transport tells it each frame and each wrong move. */
interface LessonListener {
    fun show(frame: LessonFrame)
    fun nudge()
}

/** The engine's place for a lesson: recorded polls out, only the recorded move in. */
class LessonTransport(
    private val script: LessonScript,
    private val listener: LessonListener,
    private val clock: () -> Long = System::currentTimeMillis,
) : EngineTransport {
    private val lock = Mutex()
    private var index = 0
    private var shownAt = clock()
    private var waitingForGotIt = script.frames[0].note
    private var conceded = false

    init { listener.show(script.frames[0]) }

    /** Where the lesson stands, for tests. */
    val position: Triple<Int, Boolean, J?> get() = Triple(index, waitingForGotIt, script.frames[index].expect)

    suspend fun release() = lock.withLock { waitingForGotIt = false; shownAt = Long.MIN_VALUE / 2 }

    override suspend fun request(data: ByteArray): ByteArray = lock.withLock {
        val request = EngineJson.decode(data)
        when (request["op"].string) {
            "capabilities" -> reply(script.capabilities)
            "create" -> reply(script.create)
            "poll" -> reply(poll(request["after"].integer ?: 0))
            "respond" -> respond(request["command"]["answer"])
            "concede" -> { conceded = true; reply(JsonObject(emptyMap())) }
            "destroy" -> reply(JsonObject(emptyMap()))
            else -> failure("unknown_operation", "Lessons don't support this.")
        }
    }

    /** The current frame, stepping past frames that move on by themselves once they've been seen. */
    private fun poll(after: Long): J {
        while (index + 1 < script.frames.size && !waitingForGotIt && script.frames[index].expect == null &&
            !script.frames[index].complete && clock() - shownAt >= script.frames[index].hold) advance()
        val frame = script.frames[index]
        val poll = frame.poll as? JsonObject ?: return frame.poll
        // Every message the board hasn't seen yet: the frames' own events since the cursor.
        val events = script.frames.subList(0, index + 1).flatMap { f ->
            (f.poll["events"].array ?: emptyList()).filter { (it["revision"].integer ?: 0) > after }
        }
        return JsonObject(poll + ("events" to JsonArray(events)))
    }

    private fun advance() {
        index += 1; shownAt = clock()
        val frame = script.frames[index]
        waitingForGotIt = frame.note
        listener.show(frame)
    }

    private fun respond(answer: J?): ByteArray {
        val frame = script.frames[index]
        val expected = frame.expect
        if (expected == null || answer == null || conceded) return failure("lesson_not_now", LessonText.NUDGE)
        val kind = answer["kind"]; val value = answer["value"]
        if (kind == expected["kind"] && value == expected["value"]) {
            advance(); return reply(jsonObject("accepted" to JsonPrimitive(true)))
        }
        // Two cards of the same name in the same place play the same: the recording follows the one the player chose.
        val chosen = value.string; val recorded = expected["value"].string
        if (kind == expected["kind"] && chosen != null && recorded != null && interchangeable(chosen, recorded, frame.poll)) {
            for (i in index until script.frames.size) {
                script.frames[i].poll = swap(script.frames[i].poll, chosen, recorded)
                script.frames[i].expect = script.frames[i].expect?.let { swap(it, chosen, recorded) }
            }
            advance(); return reply(jsonObject("accepted" to JsonPrimitive(true)))
        }
        listener.nudge()
        return failure("lesson_wrong_move", LessonText.NUDGE)
    }

    private fun reply(result: J): ByteArray =
        EngineJson.encode(jsonObject("protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(true), "result" to result))

    private fun failure(code: String, message: String): ByteArray = EngineJson.encode(jsonObject(
        "protocol" to JsonPrimitive(1), "ok" to JsonPrimitive(false),
        "error" to jsonObject("code" to JsonPrimitive(code), "message" to JsonPrimitive(message))))

    companion object {
        /** Same name, same zone, same tapped state: either card makes the same game. */
        fun interchangeable(a: String, b: String, poll: J): Boolean {
            fun find(id: String): Triple<String, String, Boolean>? {
                val view = poll["snapshot"]["gameView"]
                view["myHand"][id]?.let { return Triple(it["name"].string ?: "", "hand", false) }
                for (player in view["players"].array ?: emptyList()) {
                    player["battlefield"][id]?.let {
                        return Triple(it["name"].string ?: "", "battlefield:" + (player["playerId"].string ?: ""), it["tapped"].bool == true)
                    }
                }
                return null
            }
            val first = find(a) ?: return false
            return first == find(b)
        }

        /** Every use of one ID as the other and back, in keys and values alike. */
        fun swap(value: J, a: String, b: String): J {
            fun flip(s: String) = if (s == a) b else if (s == b) a else s
            return when (value) {
                is JsonObject -> JsonObject(value.entries.associate { (key, item) -> flip(key) to swap(item, a, b) })
                is JsonArray -> JsonArray(value.map { swap(it, a, b) })
                is JsonPrimitive -> if (value.isString) JsonPrimitive(flip(value.content)) else value
                else -> value
            }
        }
    }
}

