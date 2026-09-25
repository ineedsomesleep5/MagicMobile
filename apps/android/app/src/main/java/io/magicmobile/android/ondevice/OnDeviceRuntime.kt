package io.magicmobile.android.ondevice

import io.magicmobile.android.BuildConfig
import io.magicmobile.android.NativeBridge
import io.magicmobile.android.game.BuildIdentity
import io.magicmobile.android.game.EngineClient
import io.magicmobile.android.game.EngineError
import io.magicmobile.android.game.EngineTransport
import io.magicmobile.android.game.J
import io.magicmobile.android.game.get
import io.magicmobile.android.game.integer
import io.magicmobile.android.game.string
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executors

/** Converts the deck catalogue's plain maps (core `Obj`) into engine JSON. */
fun anyToJson(value: Any?): J = when (value) {
    null -> JsonNull
    is J -> value
    is String -> JsonPrimitive(value)
    is Boolean -> JsonPrimitive(value)
    is Int -> JsonPrimitive(value)
    is Long -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is Map<*, *> -> JsonObject(value.entries.associate { (key, item) -> key.toString() to anyToJson(item) })
    is Iterable<*> -> JsonArray(value.map(::anyToJson))
    else -> throw EngineError.InvalidMessage("Unsupported engine value")
}

/**
 * The packaged XMage library over JNI. Every native call runs on one engine thread, and the
 * handle stays owned until the engine confirms that all of its workers have stopped.
 */
class NativeEngineTransport private constructor(private val token: Long) : EngineTransport {
    @Volatile private var closed = false

    override suspend fun request(data: ByteArray): ByteArray = withContext(dispatcher) {
        if (closed) throw EngineError.InvalidMessage("The native runtime is closed")
        NativeBridge.request(token, data)
    }

    suspend fun close() = withContext(dispatcher) {
        if (closed) return@withContext
        val status = NativeBridge.close(token)
        if (status != 0) throw EngineError.RuntimeFailure(status)
        closed = true
    }

    companion object {
        private val dispatcher = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "MagicMobileEngine").apply { isDaemon = true }
        }.asCoroutineDispatcher()

        suspend fun open(): NativeEngineTransport = withContext(dispatcher) {
            if (!BuildConfig.NATIVE_ENGINE) throw EngineError.NativeEngineNotLinked
            val token = NativeBridge.open()
            if (token == 0L) throw EngineError.InvalidMessage("Could not start the compiled XMage library")
            NativeEngineTransport(token)
        }
    }
}

/** Port of OnDeviceRuntimeManager.swift: one native engine at a time, released only after confirmed closure. */
class OnDeviceRuntimeManager {
    private val ownerID = UUID.randomUUID()
    private var transport: NativeEngineTransport? = null
    private var recording: io.magicmobile.android.studio.DeckStudioRecordingTransport? = null
    private var changing = false
    private var destroyedMatchID: String? = null
    private var startupDiagnostic: String? = null
    var capabilities: J? = null; private set
    val isOpen: Boolean get() = transport != null

    suspend fun diagnosticReport(): String? {
        startupDiagnostic?.let { return it }
        val transport = transport ?: return null
        if (changing) return startupDiagnostic
        return EngineClient(transport).call("diagnostics")["report"].string ?: startupDiagnostic
    }

    suspend fun clearDiagnostics() {
        if (changing) throw EngineError.InvalidMessage("Wait for the native operation to finish")
        transport?.let { EngineClient(it).call("clearDiagnostics") }
        startupDiagnostic = null
    }

    suspend fun makeClient(identity: BuildIdentity, observePlaytests: Boolean = true): EngineClient {
        if (changing || transport != null) throw EngineError.InvalidMessage("Close the previous native runtime first")
        if (owner != null) throw EngineError.InvalidMessage("Finish the active game or retry pending validation cleanup before opening another engine")
        changing = true
        try {
            startupDiagnostic = null
            owner = ownerID
            val native = try { NativeEngineTransport.open() } catch (error: Throwable) { if (owner == ownerID) owner = null; throw error }
            transport = native
            // Local AI games feed the opt-in Deck Studio history, as on iOS; validation does not.
            val client = if (observePlaytests) {
                val observer = io.magicmobile.android.studio.DeckStudioRecordingTransport(native)
                recording = observer
                EngineClient(observer)
            } else EngineClient(native)
            try {
                val capabilities = client.capabilities()
                validate(capabilities, identity)
                this.capabilities = capabilities
                return client
            } catch (error: Throwable) {
                runCatching { client.call("diagnostics")["report"].string }.getOrNull()?.let { startupDiagnostic = it.take(16_384) }
                try { native.close(); transport = null; recording = null; if (owner == ownerID) owner = null } catch (_: Throwable) { /* Retain ownership for retry. */ }
                throw error
            }
        } finally { changing = false }
    }

    suspend fun create(client: EngineClient, configuration: J): J {
        if (changing) throw EngineError.InvalidMessage("Native runtime is still processing an operation")
        changing = true
        try { return client.create(configuration) }
        catch (error: Throwable) {
            startupDiagnostic = runCatching { client.call("diagnostics")["report"].string }.getOrNull()?.take(16_384)
                ?: "[local-engine-incident] create\nOccurred: ${Instant.now()}\n${(error.message ?: error.javaClass.simpleName).take(12_000)}"
            runCatching { closeTransport() }
            throw error
        } finally { changing = false }
    }

    suspend fun close() {
        if (changing) throw EngineError.InvalidMessage("Native runtime is still processing an operation")
        changing = true
        try { closeTransport() } finally { changing = false }
    }

    private suspend fun closeTransport() {
        val transport = transport ?: return
        transport.close()
        recording?.runtimeClosed()
        this.transport = null; recording = null; capabilities = null; destroyedMatchID = null
        if (owner == ownerID) owner = null
    }

    suspend fun closeMatch(client: EngineClient, matchID: String) {
        if (changing) throw EngineError.InvalidMessage("Native runtime is still processing an operation")
        if (!isOpen) return
        if (destroyedMatchID != null && destroyedMatchID != matchID) throw EngineError.IncompatibleBuild
        changing = true
        try {
            if (destroyedMatchID == null) { client.destroy(matchID); destroyedMatchID = matchID }
            closeTransport()
        } finally { changing = false }
    }

    companion object {
        // Validation and gameplay must not allocate competing full native engines.
        @Volatile private var owner: UUID? = null

        fun validate(value: J, identity: BuildIdentity) {
            if (value["engine"].string != "xmage" || value["execution"].string != "native-aot" ||
                value["protocol"].integer != identity.protocolVersion.toLong() ||
                value["upstream"].string != identity.upstreamCommit ||
                value["catalogueHash"].string != identity.catalogueHash ||
                value["maxPlayers"].integer != 4L) throw EngineError.IncompatibleBuild
        }
    }
}
