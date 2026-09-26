package io.magicmobile.android.game

import kotlinx.serialization.json.JsonNull

/**
 * Port of apps/ios/MagicMobile/OnDeviceMessageLog.swift. Retains only this seat's explicit
 * informational events in memory. Not a complete action log or a source of hidden details.
 */
class OnDeviceMessageLog {
    private var matchID: String? = null
    private var seatID: String? = null
    private var processedThrough = -1L
    var entries: List<GameLogEntry> = emptyList(); private set
    private var messageBytes = 0

    fun copy(): OnDeviceMessageLog = OnDeviceMessageLog().also {
        it.matchID = matchID; it.seatID = seatID; it.processedThrough = processedThrough
        it.entries = entries; it.messageBytes = messageBytes
    }

    /** Validate the whole batch before changing state. Older polls never duplicate notices. */
    fun ingest(poll: MatchPoll) {
        if (poll.matchID.isEmpty() || poll.seatID.isEmpty() || (matchID != null && matchID != poll.matchID) ||
            (seatID != null && seatID != poll.seatID)) throw EngineError.UnboundPeer
        if (poll.revision < processedThrough) return
        val supplied = poll.raw["events"]
        val events = if (supplied != null) {
            val values = supplied.array
            if (values == null || values.size > 128) throw EngineError.InvalidMessage("Malformed engine event history")
            values
        } else emptyList()
        val next = entries.toMutableList()
        var bytes = messageBytes
        var previous = -1L
        for (event in events) {
            val revision = event["revision"].integer
            val kind = event["kind"].string
            if (revision == null || revision < 0 || revision > poll.revision || revision <= previous || kind == null) {
                throw EngineError.InvalidMessage("Malformed engine event revision")
            }
            previous = revision
            if (revision <= processedThrough || kind != "message") continue
            val body = event["body"].obj ?: throw EngineError.InvalidMessage("Malformed private engine notice")
            // Upstream can emit an empty informational message. Do not invent text.
            if (body["message"] is JsonNull) continue
            val message = body["message"].string ?: throw EngineError.InvalidMessage("Private engine notice has no text")
            if (message.isEmpty()) continue
            next += GameLogEntry("xmage:${poll.matchID}:${poll.seatID}:$revision", message, null)
            bytes += message.toByteArray().size
            // Keep the latest message intact, even when it alone exceeds the history budget.
            while (next.size > retainedMessages || (bytes > retainedBytes && next.size > 1)) {
                bytes -= next.removeAt(0).message.toByteArray().size
            }
        }
        matchID = poll.matchID; seatID = poll.seatID
        processedThrough = poll.revision; entries = next; messageBytes = bytes
    }

    companion object {
        private const val retainedMessages = 64
        private const val retainedBytes = 1024 * 1024
    }
}
