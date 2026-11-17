package io.magicmobile.android.game

/**
 * A note a player sends from Send feedback (mm_send_feedback). The message and an optional contact,
 * nothing else they saved: the payload keys are fixed, and a deck list is not one of them.
 * parity/feedback-cases.json checks this against iOS and the web.
 */
object FeedbackDraft {
    const val MAX_MESSAGE = 4000
    const val MAX_CONTACT = 120
    const val MAX_VERSION = 40
    const val MAX_DEVICE = 80

    /** What the player reads after a send, including the offline and success lines the screen shows. */
    fun notice(code: String): String = when (code) {
        "sent" -> "Thanks. Your note was sent."
        "offline" -> "You're offline, so this note stayed here. Try again when you're back online."
        "invalid_feedback" -> "Write a note first, up to 4,000 characters."
        "invalid_contact" -> "Keep an email or handle to 120 characters."
        "too_many_feedback" -> "You've sent a few notes already. Try again in a little while."
        "not_signed_in" -> "This app isn't signed in yet. Open it online and try again."
        "feature_unavailable" -> "Feedback isn't on the server yet. Try again after the next update."
        else -> "This note couldn't be sent. Try again."
    }

    fun chars(text: String): Int = text.codePointCount(0, text.length)

    /** The field as the player types it: controls dropped (a line break stays in the note), then the cap. */
    fun cleanMessage(raw: String): String = clip(raw.filter { allowed(it, newlines = true) }, MAX_MESSAGE)

    fun cleanContact(raw: String): String = clip(raw.filter { allowed(it, newlines = false) }, MAX_CONTACT)

    /** Trimmed note, or null when it is blank, too long, or still has a control character. */
    fun message(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || chars(trimmed) > MAX_MESSAGE || forbidden(trimmed, newlines = true)) return null
        return trimmed
    }

    /** Blank contact is left out. A contact that is too long or has a control character is refused. */
    data class Contact(val value: String?, val ok: Boolean)

    fun contact(raw: String): Contact {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return Contact(null, true)
        if (chars(trimmed) > MAX_CONTACT || forbidden(trimmed, newlines = false)) return Contact(null, false)
        return Contact(trimmed, true)
    }

    /**
     * The RPC body, or null when it should not be sent. Keys are only the note, the contact, and the
     * app/device lines. Version, build and device are clipped to the server's caps.
     */
    fun params(kind: String, message: String, contact: String, platform: String, version: String, build: String, device: String): Map<String, String?>? {
        if (kind != "bug" && kind != "feature") return null
        if (platform != "ios" && platform != "android" && platform != "web") return null
        val body = message(message) ?: return null
        val who = contact(contact)
        if (!who.ok) return null
        val appVersion = meta(version, MAX_VERSION) ?: return null
        val appBuild = meta(build, MAX_VERSION) ?: return null
        val model = meta(device, MAX_DEVICE) ?: return null
        return linkedMapOf(
            "p_kind" to kind,
            "p_message" to body,
            "p_contact" to who.value,
            "p_platform" to platform,
            "p_app_version" to appVersion,
            "p_build" to appBuild,
            "p_device" to model,
        )
    }

    private fun meta(raw: String, max: Int): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || forbidden(trimmed, newlines = false)) return null
        val clipped = clip(trimmed, max)
        return clipped.ifEmpty { null }
    }

    private fun clip(text: String, max: Int): String {
        if (chars(text) <= max) return text
        val out = StringBuilder()
        var count = 0
        var index = 0
        while (index < text.length && count < max) {
            val point = text.codePointAt(index)
            out.appendCodePoint(point)
            index += Character.charCount(point)
            count += 1
        }
        return out.toString()
    }

    private fun allowed(char: Char, newlines: Boolean): Boolean {
        val value = char.code
        if (value == 10 || value == 9) return newlines
        return value >= 32 && value != 127
    }

    private fun forbidden(text: String, newlines: Boolean): Boolean = text.any { !allowed(it, newlines) }
}
