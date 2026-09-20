package io.magicmobile.android

import io.magicmobile.android.core.*

/** Persist the user's exact scope and quality, never the transient screen's current selection. */
internal data class ArtworkDownloadRequest(val names:List<String>,val quality:ArtworkQuality,val tokens:Boolean,val catalogue:Boolean) {
    fun encode():ByteArray=Wire.encode(mapOf("schema" to 1,"names" to names,"quality" to quality.id,"tokens" to tokens,"catalogue" to catalogue))
    companion object {
        fun decode(bytes:ByteArray):ArtworkDownloadRequest {
            val value=Wire.decode(bytes)
            require(value.number("schema")==1L){"Download request version is unsupported."}
            val raw=value["names"] as? List<*> ?: error("Download card list is unavailable.")
            require(raw.size in 1..100000&&raw.all{it is String&&it.isNotBlank()&&it.length<=512&&it.none(Char::isISOControl)}){"Download card list is invalid."}
            val names=raw.filterIsInstance<String>()
            require(names.distinct().size==names.size){"Download card list contains duplicate entries."}
            val quality=ArtworkQuality.entries.firstOrNull{it.id==value.text("quality")} ?: error("Download quality is unavailable.")
            val tokens=value["tokens"] as? Boolean ?: error("Token download preference is unavailable.")
            val catalogue=value["catalogue"] as? Boolean ?: error("Download scope is unavailable.")
            return ArtworkDownloadRequest(names,quality,tokens,catalogue)
        }
    }
}
