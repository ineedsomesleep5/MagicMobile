package io.magicmobile.android

import io.magicmobile.android.core.*
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.net.URL
import java.util.Locale

/** A printing is never selected from a generic token name alone. */
data class ArtworkTokenIdentity(val name: String, val typeLine: String, val oracleText: String,
    val power: String?, val toughness: String?, val colors: Set<String>) {
    /**
     * NativeAssetStore's token normalization: engine and Oracle self-references ("Sacrifice this
     * artifact", "this token", "Sacrifice Food Token:") read alike. A non-creature's P/T of "0"
     * or "" is no P/T: the engine reports 0/0 for a Food that Scryfall prints without one.
     */
    internal fun normalized():ArtworkTokenIdentity {
        val type=normalizedType(typeLine)
        val creature="creature" in type.split(" - ").first().split(" ")
        fun stat(value:String?)=value?.takeIf{it.isNotEmpty()&&(creature||it!="0")}
        return copy(name=normalize(tokenArtworkName(name)),typeLine=type,oracleText=normalizedRules(oracleText,type,name),power=stat(power),toughness=stat(toughness))
    }
    companion object {
        private fun normalize(value:String)=Decisions.plain(value).lowercase(Locale.ROOT).trim().split(Regex("\\s+")).joinToString(" ")
        /** "Food Token" and "Food" are one name; a token called just "Token" keeps it. */
        internal fun tokenArtworkName(name:String):String {
            val trimmed=name.trim()
            return if(trimmed.length>6&&trimmed.lowercase(Locale.ROOT).endsWith(" token"))trimmed.dropLast(6).trim() else trimmed
        }
        /** Case- and spacing-insensitive token name, without a trailing " Token". */
        internal fun tokenNameKey(name:String)=normalize(tokenArtworkName(name))
        /** A type line without its "Token" prefix, in lower case and plain spacing: "Token Creature — Soldier" is "creature - soldier". */
        internal fun tokenTypeKey(typeLine:String?)=normalizedType(typeLine.orEmpty())
        private fun normalizedType(value:String):String {
            val line=normalize(value).replace("—","-")
            return if(line.startsWith("token "))line.drop(6) else line
        }
        private fun normalizedRules(value:String,type:String,name:String):String {
            var rules=normalize(value).replace("this token","this permanent")
            // XMage and current Oracle word self-references differently. Abilities, reminder
            // text and unrelated token variants stay distinct.
            val kinds=type.split(" - ").first().split(" ")
            for(kind in listOf("artifact","creature","enchantment","land"))if(kind in kinds)rules=rules.replace("this $kind","this permanent")
            // Only a self-named sacrifice cost ("Sacrifice Food Token:", older "Sacrifice Food:").
            val self=normalize(tokenArtworkName(name))
            return Regex("(?<![a-z0-9])sacrifice ${Regex.escape(self)}(?: token)?(?=\\s*:)").replace(rules,"sacrifice this permanent")
        }
    }
}
/** A card a card points to (Scryfall's all_parts): a token, an emblem, or something else. */
internal data class ArtworkPart(val id:String, val name:String, val typeLine:String?)

/**
 * `id` is the Scryfall UUID, with ":back" added for a double-faced token's reverse face: each face has its own
 * identity, picture and saved key. `back` links a front to that reverse face (NativeAssetStore's face "back" on iOS).
 */
internal data class ArtworkRecord(val id:String, val name:String, val images:Map<String,String>,
    val faces:List<ArtworkRecord> = emptyList(), val related:List<ArtworkPart> = emptyList(), val token:ArtworkTokenIdentity? = null,
    val back:ArtworkRecord? = null) {
    fun json():Obj = mapOf("id" to id,"name" to (token?.name ?: name),"image_uris" to images,"type_line" to token?.typeLine,
        "oracle_text" to token?.oracleText,"power" to token?.power,"toughness" to token?.toughness,"colors" to token?.colors?.toList(),"layout" to "token")
}

/**
 * A related card that is a token or an emblem. Scryfall links a planeswalker's emblem to it as a combo piece, not as
 * a token, so the component alone would leave every emblem out of a download. Meld parts and real combo pieces have
 * neither type. NativeArtworkCatalogue.isTokenPart.
 */
internal fun isTokenPart(component:String?,typeLine:String?):Boolean =
    component=="token" || (typeLine!=null && (typeLine.startsWith("Emblem") || typeLine.startsWith("Token")))

internal class ArtworkCatalogue {
    private val names=mutableMapOf<String,ArtworkRecord>()
    private val ambiguous=mutableSetOf<String>()
    val tokens=linkedMapOf<String,ArtworkRecord>()
    val unavailableTokens=linkedSetOf<String>()
    /** Every token or emblem any card in this catalogue points to, by Scryfall ID. */
    private val referenced=linkedMapOf<String,ArtworkPart>()
    fun card(name:String)=names[name.lowercase(Locale.ROOT)]
    /**
     * Tokens and emblems that cards point to which this catalogue cannot download: not in it, and with no token of the
     * same name and type in it either (Oracle bulk keeps one printing per token, so another printing of the same token
     * is covered). A download resolves these by ID before it counts or queues. NativeArtworkCatalogue.referencedTokensWithoutDownload.
     */
    fun referencedTokensWithoutDownload():List<ArtworkPart> {
        fun key(name:String,typeLine:String?)=ArtworkTokenIdentity.tokenNameKey(name.substringBefore(" // "))+"\u0000"+ArtworkTokenIdentity.tokenTypeKey(typeLine?.substringBefore(" // "))
        val covered=tokens.values.mapNotNull{record->record.token?.let{key(it.name,it.typeLine)}}.toSet()
        return referenced.values.filter{it.id !in tokens&&key(it.name,it.typeLine) !in covered}.sortedBy{it.id}
    }
    fun add(root:Obj) {
        if(root.text("layout")=="art_series") return
        val record=decode(root) ?: return
        record.related.forEach{if(referenced.size<100_000)referenced.putIfAbsent(it.id,it)}
        val tokenLike=root.text("layout") in setOf("token","double_faced_token","emblem") ||
            root.text("type_line").orEmpty().contains(Regex("Token|Emblem",RegexOption.IGNORE_CASE))
        if(tokenLike) {
            if(record.token!=null)tokens[record.id]=record else unavailableTokens+=record.name
            // A double-faced token's reverse face has its own identity, picture and key; one that cannot be matched stays reported.
            record.back?.let{tokens[it.id]=it}
            if(record.back==null)record.faces.drop(1).filter{it.images.isNotEmpty()}.forEach{unavailableTokens+="${it.name} (alternate token face)"}
            return
        }
        fun index(name:String, value:ArtworkRecord) {
            val key=name.lowercase(Locale.ROOT)
            if(key in ambiguous)return
            val previous=names[key]
            if(previous!=null && previous.id!=value.id){names.remove(key);ambiguous+=key}else names[key]=value
        }
        index(record.name,record)
        record.faces.filter{it.images.isNotEmpty()}.forEachIndexed{position,face->index(face.name,if(position==0)record.copy(name=face.name,images=face.images)else face)}
        if(record.faces.isEmpty() && record.name.contains(" // "))index(record.name.substringBefore(" // "),record)
    }
    companion object {
        fun allowedImage(value:String):Boolean=runCatching{val url=URL(value);url.protocol=="https"&&url.host=="cards.scryfall.io"&&url.userInfo==null&&(url.port==-1||url.port==443)&&url.ref==null}.getOrDefault(false)
        fun decode(root:Obj):ArtworkRecord? {
            // A saved reverse face of a double-faced token keeps ":back" on its UUID.
            val id=root.text("id")?.takeIf{Wire.uuid(it.removeSuffix(":back"))} ?: return null
            val name=root.text("name")?.takeIf{it.isNotBlank()&&it.length<=512} ?: return null
            fun images(value:Obj?)=value.orEmpty().filter{(key,value)->key in setOf("small","normal","large")&&value is String&&allowedImage(value)}.mapValues{it.value as String}
            val faceObjects=root.array("card_faces").take(8).map(Wire::objectValue)
            val faces=faceObjects.mapNotNull { face->face.text("name")?.takeIf{it.isNotBlank()&&it.length<=512}?.let{ArtworkRecord(id,it,images(face.obj("image_uris")))}}
            val face=faceObjects.firstOrNull().orEmpty()
            val primary=if(root.text("layout")=="double_faced_token")face else root
            val type=primary.text("type_line") ?: root.text("type_line") ?: face.text("type_line")
            val rules=primary.text("oracle_text") ?: root.text("oracle_text") ?: face.text("oracle_text")
            val colors=(primary["colors"] ?: root["colors"] ?: face["colors"]) as? List<*>
            val tokenLike=root.text("layout") in setOf("token","double_faced_token","emblem") || type.orEmpty().contains(Regex("Token|Emblem",RegexOption.IGNORE_CASE))
            val identity=if(tokenLike&&type!=null&&colors!=null&&colors.all{it is String&&it in setOf("W","U","B","R","G")})
                ArtworkTokenIdentity(if(root.obj("image_uris")==null)face.text("name") ?: name else name,type,rules.orEmpty(),primary.text("power") ?: root.text("power") ?: face.text("power"),primary.text("toughness") ?: root.text("toughness") ?: face.text("toughness"),colors.filterIsInstance<String>().toSet()) else null
            val related=root.array("all_parts").take(100).map(Wire::objectValue).filter{isTokenPart(it.text("component"),it.text("type_line"))}.mapNotNull{part->
                part.text("id")?.takeIf(Wire::uuid)?.let{ArtworkPart(it,part.text("name").orEmpty().take(512),part.text("type_line")?.take(2048))}}
            // The reverse face of a double-faced token: its own name, type, rules, size, colors and picture.
            val back=if(root.text("layout")=="double_faced_token")faceObjects.getOrNull(1)?.let{reverse->
                val reverseName=reverse.text("name")?.takeIf{it.isNotBlank()&&it.length<=512}
                val reverseType=reverse.text("type_line");val reverseColors=reverse["colors"] as? List<*>
                val reverseImages=images(reverse.obj("image_uris"))
                if(reverseName!=null&&reverseType!=null&&reverseColors!=null&&reverseColors.all{it is String&&it in setOf("W","U","B","R","G")}&&reverseImages.isNotEmpty())
                    ArtworkRecord("$id:back",reverseName,reverseImages,token=ArtworkTokenIdentity(reverseName,reverseType,reverse.text("oracle_text").orEmpty(),
                        reverse.text("power"),reverse.text("toughness"),reverseColors.filterIsInstance<String>().toSet())) else null
            } else null
            return ArtworkRecord(id,name,images(root.obj("image_uris")).ifEmpty{faces.firstOrNull()?.images.orEmpty()},faces,related,identity,back)
        }
        /** Reads both JSON arrays and JSONL; only one bounded object is decoded at a time. */
        fun parse(input:InputStream, check:()->Unit = {}):ArtworkCatalogue {
            val catalogue=ArtworkCatalogue();val buffer=ByteArray(65536)
            var objectBytes:ByteArrayOutputStream?=null;var depth=0;var quoted=false;var escaped=false;var total=0L;var count=0
            var mode=0;var expectValue=true;var canClose=true;var closed=false;var separated=true
            while(true){check();val size=input.read(buffer);if(size<0)break;total+=size;require(total<=250L*1024*1024){"Artwork catalogue is too large."}
                for(index in 0 until size){val byte=buffer[index];val char=byte.toInt().toChar()
                    if(objectBytes==null){
                        if(char.isWhitespace()){separated=true;continue}
                        if(mode==0&&char=='['){mode=1;continue}
                        if(mode==0)mode=2
                        if(mode==1){
                            require(!closed){"Unexpected content after artwork catalogue."}
                            if(char==']'){require(!expectValue||canClose){"Incomplete artwork catalogue."};closed=true;continue}
                            if(char==','){require(!expectValue){"Invalid artwork separator."};expectValue=true;canClose=false;continue}
                            require(char=='{'&&expectValue){"Invalid artwork catalogue."};expectValue=false;canClose=false
                        }else{require(char=='{'&&separated){"Invalid artwork catalogue."};separated=false}
                        objectBytes=ByteArrayOutputStream();depth=1;objectBytes.write(byte.toInt());continue
                    }
                    objectBytes.write(byte.toInt());require(objectBytes.size()<=2*1024*1024){"Artwork record is too large."}
                    if(quoted){if(escaped)escaped=false else if(char=='\\')escaped=true else if(char=='"')quoted=false}
                    else when(char){'"'->quoted=true;'{'->depth++;'}'->{depth--;if(depth==0){require(++count<=100000);check();catalogue.add(Wire.objectValue(io.magicmobile.core.Json.parseObject(objectBytes.toString("UTF-8"))));objectBytes=null}}}
                }
            }
            require(objectBytes==null&&count>0&&(mode!=1||closed)){"Incomplete artwork catalogue."};return catalogue
        }
    }
}
