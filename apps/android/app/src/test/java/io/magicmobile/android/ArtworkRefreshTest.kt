package io.magicmobile.android

import org.junit.Assert.*
import org.junit.Test

class ArtworkRefreshTest {
    private val soldier=ArtworkTokenIdentity("Soldier","Token Creature — Soldier","","1","1",setOf("W"))
    @Test fun savedImageRefreshesOnlyMatchingDisplayedCard() {
        assertTrue(artworkDownloadMatches("Island","Island",false,null,null))
        assertFalse(artworkDownloadMatches("Swamp","Island",false,null,null))
        assertFalse(artworkDownloadMatches("token:123","Soldier",false,null,null))
    }
    @Test fun tokenRefreshRequiresFullIdentityNotGenericName() {
        assertTrue(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,soldier,soldier.copy(power="2",toughness="2")))
        assertFalse(artworkDownloadMatches("token:123","Soldier",true,null,soldier))
        assertFalse(artworkDownloadMatches("Soldier","Soldier",true,soldier,soldier))
    }
}
