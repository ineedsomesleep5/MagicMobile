package io.magicmobile.android

import io.magicmobile.android.core.*
import java.io.ByteArrayInputStream

/** Portable checks: compile alongside app ArtworkCatalogue.kt and the existing Android core. */
fun main() {
    val id="00000000-0000-0000-0000-000000000001"
    val other="00000000-0000-0000-0000-000000000002"
    fun image(label:String)=mapOf("normal" to "https://cards.scryfall.io/normal/$label.jpg")
    val front=mapOf("name" to "Delver of Secrets","image_uris" to image("front"))
    val back=mapOf("name" to "Insectile Aberration","image_uris" to image("back"))
    val transform:Obj=mapOf("id" to id,"name" to "Delver of Secrets // Insectile Aberration","layout" to "transform","card_faces" to listOf(front,back))
    val art:Obj=mapOf("id" to other,"name" to "Delver of Secrets // Delver of Secrets","layout" to "art_series","image_uris" to image("art"))
    fun parse(rows:List<Obj>,array:Boolean=false)=ArtworkCatalogue.parse(ByteArrayInputStream((if(array)"[" else "").toByteArray()+rows.map{Wire.encode(it)}.reduce{a,b->a+(if(array)","else"\n").toByteArray()+b}+(if(array)"]"else"").toByteArray()))
    for(rows in listOf(listOf(transform,art),listOf(art,transform))) {
        val catalogue=parse(rows)
        check(catalogue.card("Delver of Secrets")?.images?.get("normal")==image("front")["normal"])
        check(catalogue.card("Insectile Aberration")?.images?.get("normal")==image("back")["normal"])
        check(catalogue.card("Delver of Secrets")?.faces?.size==2)
    }
    check(parse(listOf(transform),true).card("Insectile Aberration")!=null)
    check(parse(listOf(transform,transform+("id" to other))).card("Delver of Secrets")==null)
    val token:Obj=mapOf("id" to id,"name" to "Sorin, Lord of Innistrad","layout" to "emblem","type_line" to "Emblem — Sorin","oracle_text" to "Creatures you control get +1/+0.","colors" to emptyList<String>(),"image_uris" to image("emblem"))
    val ordinary:Obj=mapOf("id" to other,"name" to "Sorin, Lord of Innistrad","layout" to "normal","image_uris" to image("sorin"))
    val catalogue=parse(listOf(token,ordinary))
    check(catalogue.tokens.size==1&&catalogue.card("Sorin, Lord of Innistrad")?.id==other)
    check(ArtworkCatalogue.decode(catalogue.tokens[id]!!.json())?.token==catalogue.tokens[id]!!.token)
    check(parse(listOf(token-("colors"))).unavailableTokens.size==1)
    check(!ArtworkCatalogue.allowedImage("https://cards.scryfall.io.evil.test/image.jpg"))
    check(!ArtworkCatalogue.allowedImage("https://user@cards.scryfall.io/image.jpg"))
    check(!ArtworkCatalogue.allowedImage("http://cards.scryfall.io/image.jpg"))
    check(!ArtworkCatalogue.allowedImage("https://cards.scryfall.io:444/image.jpg"))
    check(runCatching{ArtworkCatalogue.parse(ByteArrayInputStream("{\"name\":".toByteArray()))}.isFailure)
    check(runCatching{ArtworkCatalogue.parse(ByteArrayInputStream("[".toByteArray()+Wire.encode(transform)))}.isFailure)
    check(runCatching{ArtworkCatalogue.parse(ByteArrayInputStream("[".toByteArray()+Wire.encode(transform)+",]".toByteArray()))}.isFailure)
    check(runCatching{ArtworkCatalogue.parse(ByteArrayInputStream(Wire.encode(transform)+Wire.encode(transform)))}.isFailure)
    val doubleToken=token+("layout" to "double_faced_token")+("card_faces" to listOf(front,back))
    check(parse(listOf(doubleToken)).unavailableTokens.any{it.contains("Insectile Aberration")})
    var checks=0
    check(runCatching{ArtworkCatalogue.parse(ByteArrayInputStream(Wire.encode(transform))){if(++checks>1)error("cancelled")}}.isFailure)
    val fixture=System.getenv("MAGICMOBILE_BULK_FIXTURE")
    if(fixture!=null)java.util.zip.GZIPInputStream(java.io.File(fixture).inputStream()).use{input->
        val live=ArtworkCatalogue.parse(input)
        check(live.tokens.size>500)
        check(live.card("Delver of Secrets")?.faces?.any{it.name=="Insectile Aberration"}==true)
        check(live.card("Insectile Aberration")?.images?.get("normal")!=live.card("Delver of Secrets")?.images?.get("normal"))
        println("Live catalogue tokens: ${live.tokens.size}; unavailable: ${live.unavailableTokens.size}")
    }
    println("Artwork catalogue checks passed")
}
