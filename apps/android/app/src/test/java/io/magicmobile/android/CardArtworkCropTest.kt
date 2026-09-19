package io.magicmobile.android

import org.junit.Assert.assertEquals
import org.junit.Test

class CardArtworkCropTest {
    @Test fun usesIosIllustrationWindowBeforeFillingTheDeckCover() {
        assertEquals(ArtworkCrop(115,145,770,385),artworkIllustrationCrop(1000,1000,200,100))
        assertEquals(ArtworkCrop(404,145,192,385),artworkIllustrationCrop(1000,1000,100,200))
    }
}
