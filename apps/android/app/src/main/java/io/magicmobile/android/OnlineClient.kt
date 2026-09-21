package io.magicmobile.android

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.magicmobile.android.core.*
import java.net.HttpURLConnection
import java.net.URI
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class OnlinePlayer(val userId:String,val name:String,val seatId:String,val ready:Boolean,val deckSubmitted:Boolean)
data class OnlineLobby(val id:String,val code:String,val status:String,val hostUserId:String,val players:List<OnlinePlayer>,val matchId:String?,val seatId:String?,val playerCount:Int) {
    companion object {
        fun parse(value:Obj):OnlineLobby {
            val id=Wire.string(value["id"]);require(Wire.uuid(id))
            val players=value.array("players").map { raw->val p=Wire.objectValue(raw);val user=Wire.string(p["userId"]);val seat=Wire.string(p["seatId"]);require(Wire.uuid(user)&&seat==user);OnlinePlayer(user,Wire.string(p["name"]),seat,p.flag("ready"),p.flag("deckSubmitted")) }
            require(players.size<=4 && players.map {it.userId}.distinct().size==players.size)
            val count=Wire.integer(value["playerCount"]).toInt();require(count in 2..4)
            return OnlineLobby(id,Wire.string(value["code"]),Wire.string(value["status"]),Wire.string(value["hostUserId"]),players,value.text("matchId"),value.text("seatId"),count)
        }
    }
}
data class OnlineState(val configured:Boolean=BuildConfig.ONLINE_SERVER_URL.isNotBlank(),val connected:Boolean=false,val busy:Boolean=false,val userId:String?=null,val email:String?=null,val lobby:OnlineLobby?=null,val message:String?=null,val reconnecting:Boolean=false,val locatingLobby:Boolean=false)

internal fun onlinePollDelayMillis(failures:Int):Long = if(failures<=0)1000L else (2000L*failures.coerceAtMost(15))
internal fun decodeOnlineResponse(bytes:ByteArray):Obj? = if(bytes.toString(Charsets.UTF_8).trim()=="null")null else Wire.decode(bytes)

internal fun onlineServiceError(status:Int,value:Obj):EngineFault {
    val error=(value["error"] as? Map<*,*>)?.let(Wire::objectValue)
    return EngineFault(error?.text("code") ?: value.text("code") ?: value.text("error") ?: "online_error",(error?.text("message") ?: value.text("msg") ?: value.text("error_description") ?: value.text("message") ?: "Online request failed ($status). Please try again.").take(500))
}

/** Refresh credentials are encrypted with a non-exportable Android Keystore key. */
private class OnlineCredentials(context:Context) {
    private val preferences=context.getSharedPreferences("magicmobile.online",Context.MODE_PRIVATE)
    private val alias="magicmobile.online.credentials"
    private fun key():SecretKey {
        val store=KeyStore.getInstance("AndroidKeyStore").apply {load(null)}
        (store.getKey(alias,null) as? SecretKey)?.let {return it}
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read():Obj? {
        val value=preferences.getString("session",null) ?: return null
        return try {
            val bytes=Base64.decode(value,Base64.NO_WRAP);require(bytes.size>28)
            val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,bytes.copyOfRange(0,12)))
            Wire.decode(cipher.doFinal(bytes.copyOfRange(12,bytes.size)))
        } catch(_:Exception) {clear();null}
    }
    fun write(value:Obj) {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key())
        check(preferences.edit().putString("session",Base64.encodeToString(cipher.iv+cipher.doFinal(Wire.encode(value)),Base64.NO_WRAP)).commit()) {"Could not securely save your sign-in."}
    }
    var lobbyId:String?
        get()=preferences.getString("lobby",null)
        set(value){preferences.edit().putString("lobby",value).apply()}
    fun clear(){preferences.edit().remove("session").remove("lobby").commit()}
    fun expire(){preferences.edit().remove("session").commit()}
}

/** Called only on AppModel's serial executor; credentials never enter UI state. */
class OnlineClient(context:Context) {
    private val storage=OnlineCredentials(context)
    private var credentials=storage.read()
    private var config:Obj?=null
    val userId:String? get()=credentials?.obj("user")?.text("id")
    val email:String? get()=credentials?.obj("user")?.text("email")
    var lobbyId:String? get()=storage.lobbyId
        set(value){storage.lobbyId=value}
    private fun endpoint(base:String,path:String):String {
        val uri=URI(base);require(uri.scheme=="https" && !uri.host.isNullOrBlank() && uri.userInfo==null && uri.query==null && uri.fragment==null) {"Online service configuration is unavailable."}
        return base.trimEnd('/')+path
    }
    private fun request(url:String,method:String,body:Obj?=null,headers:Map<String,String> = emptyMap()):Pair<Int,Obj?> {
        val connection=URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod=method;connection.connectTimeout=15_000;connection.readTimeout=25_000;connection.instanceFollowRedirects=false
            connection.setRequestProperty("Accept","application/json")
            headers.forEach { (name,value)->connection.setRequestProperty(name,value) }
            if(body!=null){connection.doOutput=true;connection.setRequestProperty("Content-Type","application/json");connection.outputStream.use {it.write(Wire.encode(body))}}
            val status=connection.responseCode
            val bytes=(if(status in 200..299)connection.inputStream else connection.errorStream)?.use {readBounded(it,Wire.LIMIT)} ?: byteArrayOf()
            val parsed=if(bytes.isEmpty())emptyMap() else runCatching {decodeOnlineResponse(bytes)}.getOrElse {throw IllegalStateException("The online service returned an unreadable response. Try again.")}
            return status to parsed
        } finally {connection.disconnect()}
    }
    private fun checked(response:Pair<Int,Obj?>):Obj? {
        val (status,value)=response
        if(status !in 200..299)throw onlineServiceError(status,value.orEmpty())
        return value
    }
    fun connect(identity:Obj) {
        val loaded=checkNotNull(checked(request(endpoint(BuildConfig.ONLINE_SERVER_URL,"/v1/config"),"GET"))){"Online configuration is unavailable."}
        val remote=loaded.obj("identity") ?: error("The online service did not provide a compatible engine identity.")
        require(identity.all {(key,value)->remote[key]==value}) {"This app and the online server use different game data. Install the latest MagicMobile update."}
        endpoint(Wire.string(loaded["supabaseUrl"]),"/auth/v1")
        require(!loaded.text("publishableKey").isNullOrBlank())
        config=loaded
        if(credentials!=null)try {refresh()}catch(e:EngineFault){if(credentials!=null)throw e}
    }
    private fun auth(path:String,body:Obj):Obj {
        val settings=checkNotNull(config){"Connect to the online service first."}
        return checkNotNull(checked(request(endpoint(Wire.string(settings["supabaseUrl"]),"/auth/v1$path"),"POST",body,mapOf("apikey" to Wire.string(settings["publishableKey"]))))){"Sign-in returned an empty response."}
    }
    private fun save(value:Obj) {
        require(!value.text("access_token").isNullOrBlank() && !value.text("refresh_token").isNullOrBlank() && Wire.uuid(value.obj("user")?.text("id").orEmpty())) {"Sign-in did not return a valid session."}
        storage.write(value);credentials=value
    }
    fun signIn(email:String,password:String){save(auth("/token?grant_type=password",mapOf("email" to email.trim(),"password" to password)))}
    fun signUp(email:String,password:String):Boolean {
        val value=auth("/signup",mapOf("email" to email.trim(),"password" to password))
        if(value.text("access_token")==null)return false
        save(value);return true
    }
    private fun refresh() {
        val token=credentials?.text("refresh_token") ?: error("Sign in to continue.")
        try {save(auth("/token?grant_type=refresh_token",mapOf("refresh_token" to token)))}
        catch(e:EngineFault){if(e.code in setOf("refresh_token_not_found","refresh_token_already_used","session_not_found","invalid_grant")){credentials=null;storage.expire()};throw e}
    }
    fun signOut(){credentials=null;storage.clear()}
    private fun serverNullable(path:String,method:String="POST",body:Obj?=emptyMap()):Obj? {
        if(credentials==null)error("Sign in to play online.")
        val expires=credentials?.number("expires_at")
        if(expires!=null && expires<=System.currentTimeMillis()/1000+60)refresh()
        fun send()=request(endpoint(BuildConfig.ONLINE_SERVER_URL,path),method,if(method=="GET")null else body,mapOf("Authorization" to "Bearer ${credentials!!.text("access_token")}"))
        var result=send();if(result.first==401){refresh();result=send()}
        return checked(result)
    }
    fun server(path:String,method:String="POST",body:Obj?=emptyMap()):Obj=checkNotNull(serverNullable(path,method,body)){"The online service returned an empty response."}
    fun currentLobby():OnlineLobby? = serverNullable("/v1/lobbies/current","GET")?.let(OnlineLobby::parse).also {lobbyId=it?.id}
    fun lobby(path:String,method:String="POST",body:Obj=emptyMap()):OnlineLobby = OnlineLobby.parse(server(path,method,body)).also {lobbyId=it.id}
    fun engine(match:String,op:String,vararg fields:Pair<String,Any?>):Obj {
        require(Wire.uuid(match))
        val envelope=server("/v1/matches/$match/engine",body=linkedMapOf("protocol" to 1,"op" to op,"matchId" to match,"viewerId" to checkNotNull(userId),*fields))
        return Wire.result(Wire.encode(envelope))
    }
}
