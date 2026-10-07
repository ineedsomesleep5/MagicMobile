package io.magicmobile.android

import io.magicmobile.android.core.*

/**
 * Persist the user's exact scope and quality, never the transient screen's current selection.
 * `chosen` is the art the player picked in Deck Studio: each printing is saved as its own image beside the
 * card's default art.
 */
internal data class ArtworkDownloadRequest(val names:List<String>,val quality:ArtworkQuality,val tokens:Boolean,val catalogue:Boolean,
    val chosen:List<ChosenArt> = emptyList()) {
    fun encode():ByteArray=Wire.encode(mapOf("schema" to 1,"names" to names,"quality" to quality.id,"tokens" to tokens,"catalogue" to catalogue,
        "chosen" to chosen.map{mapOf("name" to it.name,"printing" to it.printing.key)}))
    companion object {
        fun decode(bytes:ByteArray):ArtworkDownloadRequest {
            val value=Wire.decode(bytes)
            require(value.number("schema")==1L){"Download request version is unsupported."}
            val raw=value["names"] as? List<*> ?: error("Download card list is unavailable.")
            require(raw.size<=100000&&raw.all{it is String&&it.isNotBlank()&&it.length<=512&&it.none(Char::isISOControl)}){"Download card list is invalid."}
            val names=raw.filterIsInstance<String>()
            require(names.distinct().size==names.size){"Download card list contains duplicate entries."}
            val quality=ArtworkQuality.entries.firstOrNull{it.id==value.text("quality")} ?: error("Download quality is unavailable.")
            val tokens=value["tokens"] as? Boolean ?: error("Token download preference is unavailable.")
            val catalogue=value["catalogue"] as? Boolean ?: error("Download scope is unavailable.")
            // A request saved before art choices has none.
            val rows=value["chosen"]?.let{it as? List<*> ?: error("Chosen art list is invalid.")}.orEmpty()
            require(rows.size<=100000){"Chosen art list is invalid."}
            val chosen=rows.map{row->
                val fields=row as? Map<*,*> ?: error("Chosen art list is invalid.")
                val name=fields["name"] as? String ?: error("Chosen art list is invalid.")
                val key=fields["printing"] as? String ?: error("Chosen art list is invalid.")
                val printing=CardPrinting.of(key.substringBefore('/'),key.substringAfter('/',""))?.takeIf{it.key==key} ?: error("Chosen art list is invalid.")
                require(name.length<=512&&name.none(Char::isISOControl)){"Chosen art list is invalid."}
                ChosenArt(name,printing)
            }
            require(chosen.map{it.printing}.distinct().size==chosen.size){"Chosen art list contains duplicate entries."}
            require(names.isNotEmpty() || chosen.isNotEmpty() || tokens && catalogue){"Empty card list requires token-only catalogue download."}
            return ArtworkDownloadRequest(names,quality,tokens,catalogue,chosen)
        }
    }
}
