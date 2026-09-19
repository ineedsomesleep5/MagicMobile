package io.magicmobile.android

import io.magicmobile.android.core.*
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.net.URL
import java.util.Locale

/** A printing is never selected from a generic token name alone. */
data class ArtworkTokenIdentity(val name: String, val typeLine: String, val oracleText: String,
    val power: String?, val toughness: String?, val colors: Set<String>) {
    internal fun normalized() = copy(name=normalize(name), typeLine=normalize(typeLine).replace("token ", "").replace("—", "-"), oracleText=normalize(oracleText))
    companion object { private fun normalize(value:String)=Decisions.plain(value).lowercase(Locale.ROOT).trim().split(Regex("\\s+")).joinToString(" ") }
}
internal data class ArtworkRecord(val id:String, val name:String, val images:Map<String,String>,
    val faces:List<ArtworkRecord> = emptyList(), val related:List<String> = emptyList(), val token:ArtworkTokenIdentity? = null) {
    fun json():Obj = mapOf("id" to id,"name" to (token?.name ?: name),"image_uris" to images,"type_line" to token?.typeLine,
        "oracle_text" to token?.oracleText,"power" to token?.power,"toughness" to token?.toughness,"colors" to token?.colors?.toList(),"layout" to "token")
}

internal class ArtworkCatalogue {
    private val names=mutableMapOf<String,ArtworkRecord>()
    private val ambiguous=mutableSetOf<String>()
    val tokens=linkedMapOf<String,ArtworkRecord>()
    val unavailableTokens=linkedSetOf<String>()
    fun card(name:String)=names[name.lowercase(Locale.ROOT)]
    fun add(root:Obj) {
        if(root.text("layout")=="art_series") return
        val record=decode(root) ?: return
        val tokenLike=root.text("layout") in setOf("token","double_faced_token","emblem") ||
            root.text("type_line").orEmpty().contains(Regex("Token|Emblem",RegexOption.IGNORE_CASE))
        if(tokenLike) {
            if(record.token!=null)tokens[record.id]=record else unavailableTokens+=record.name
            // A second token face needs its own independently matched identity, not its front's UUID key.
            record.faces.drop(1).filter{it.images.isNotEmpty()}.forEach{unavailableTokens+="${it.name} (alternate token face)"}
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
            val id=root.text("id")?.takeIf(Wire::uuid) ?: return null
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
            val identity=if(tokenLike&&type!=null&&rules!=null&&colors!=null&&colors.all{it is String&&it in setOf("W","U","B","R","G")})
                ArtworkTokenIdentity(if(root.obj("image_uris")==null)face.text("name") ?: name else name,type,rules,primary.text("power") ?: root.text("power") ?: face.text("power"),primary.text("toughness") ?: root.text("toughness") ?: face.text("toughness"),colors.filterIsInstance<String>().toSet()) else null
            val related=root.array("all_parts").take(100).map(Wire::objectValue).filter{it.text("component")=="token"}.mapNotNull{it.text("id")?.takeIf(Wire::uuid)}
            return ArtworkRecord(id,name,images(root.obj("image_uris")).ifEmpty{faces.firstOrNull()?.images.orEmpty()},faces,related,identity)
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
