package io.magicmobile.android.game

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors BoardCardPresentationTests.swift case for case. */
class BoardCardPresentationTest {
    private fun card(isToken: Boolean?, source: String?) = ZoneCard("token",
        CardIdentity("Sun Titan", "Creature — Giant", "Vigilance", isToken = isToken, copySourceArtworkName = source),
        tapped = false, summoningSickness = false, counters = mapOf("+1/+1" to 1), power = 7, toughness = 7, isCreaturePermanent = true)

    private fun BoardRect.containsLoosely(other: BoardRect) = other.minX >= minX - 0.001f && other.maxX <= maxX + 0.001f &&
        other.minY >= minY - 0.001f && other.maxY <= maxY + 0.001f

    @Test fun onlyAnExplicitTokenCopyGetsTheCopyFrame() {
        assertEquals("Sun Titan", card(true, "Sun Titan").tokenCopySourceName)
        assertNull("a plain token keeps its token art", card(true, null).tokenCopySourceName)
        assertNull(card(true, "  ").tokenCopySourceName)
        assertNull("a nontoken copy is its own printed card", card(false, "Sun Titan").tokenCopySourceName)
        assertNull(card(null, "Sun Titan").tokenCopySourceName)
    }

    @Test fun tagNamesTheSourceWhenThereIsRoomToReadIt() {
        assertEquals("Token copy", TokenCopyPresentation.tag("Sun Titan", 82f))
        assertEquals("Token copy · Sun Titan", TokenCopyPresentation.tag("Sun Titan", 120f))
        assertEquals("Token copy · Sun Titan", TokenCopyPresentation.tag("Sun Titan", 300f))
    }

    @Test fun tokenCopyFrameRegionsStackWithoutOverlapAndKeepTheArtInTheCompactCrop() {
        for (size in listOf(BoardSize(40f, 56f), BoardSize(82f, 112f), BoardSize(150f, 210f), BoardSize(300f, 419f))) {
            val frame = TokenCopyFrameLayout(size)
            val bounds = BoardRect(0f, 0f, size.width, size.height)
            val context = size.toString()
            for (region in listOf(frame.nameBar, frame.art, frame.typeBar, frame.textBox, frame.powerToughnessBox, frame.tagSlot)) {
                assertTrue(context, bounds.containsLoosely(region))
                assertTrue(context, region.height > 0)
            }
            assertTrue(context, frame.nameBar.maxY <= frame.art.minY)
            assertTrue(context, frame.art.maxY <= frame.typeBar.minY)
            assertTrue(context, frame.typeBar.maxY <= frame.textBox.minY)
            assertTrue(context, frame.textBox.containsLoosely(frame.powerToughnessBox))
            assertTrue(context, frame.rulesArea(true).maxY <= frame.powerToughnessBox.minY)
            assertTrue(context, frame.art.containsLoosely(frame.tagSlot))
            val lines = frame.rulesLineLimit(true)
            assertTrue(context, lines == 1 || lines * frame.rulesFontSize * 1.25f <= frame.rulesArea(true).height)
            assertEquals(context, size.width >= 60f, frame.showsRules)
            if (size.width < 82f) continue
            // ArenaBattlefieldCard shows the tile from 0.19 w of a 1.51 w tall tile, about 12.6% down.
            assertTrue(context, frame.art.minY / size.height <= 0.15f)
            assertTrue(context, frame.art.maxY / size.height >= 0.5f)
        }
        // Same numbers as iOS for the inspector-sized frame.
        val inspector = TokenCopyFrameLayout(BoardSize(300f, 419f))
        assertEquals(13.5f, inspector.border, 0.001f)
        assertEquals(232.545f, inspector.art.maxY, 0.001f)
        assertEquals(4, inspector.rulesLineLimit(true))
    }

    @Test fun portraitInspectorGivesRulesTheirRoomAndShrinksTheCardInstead() {
        val available = BoardSize(342f, 582f)
        var previous = Float.POSITIVE_INFINITY
        var needed = 40f
        while (needed <= 700f) {
            val fit = CardInspectorFit.plan(available, hasFooter = true) { needed }
            assertFalse(fit.horizontal)
            assertTrue("the card only shrinks as the text grows", fit.cardSize.height <= previous)
            previous = fit.cardSize.height
            assertTrue(fit.cardSize.height + CardInspectorFit.SPACING + fit.footerSize.height <= available.height + 0.001f)
            assertTrue(fit.cardSize.width <= available.width + 0.001f)
            assertTrue(fit.cardSize.height >= available.height * CardInspectorFit.MINIMUM_CARD_FRACTION - 0.001f)
            assertEquals(88f / 63f, fit.cardSize.height / fit.cardSize.width, 0.001f)
            if (fit.footerFits) assertEquals(needed, fit.footerSize.height, 0.001f)
            needed += 30f
        }
        // The old footer capped rules at min(200, 38%) behind a scroll; 300 points now fit unscaled.
        val long = CardInspectorFit.plan(available, hasFooter = true) { 300f }
        assertTrue(long.footerFits)
        assertEquals(300f, long.footerSize.height, 0.001f)
        assertEquals(582f - 8f - 300f, long.cardSize.height, 0.001f)
        // Only past the card's floor does the text have to shrink.
        val huge = CardInspectorFit.plan(available, hasFooter = true) { 900f }
        assertFalse(huge.footerFits)
        assertEquals(582f * CardInspectorFit.MINIMUM_CARD_FRACTION, huge.cardSize.height, 0.001f)
        assertEquals(582f - 8f - 582f * CardInspectorFit.MINIMUM_CARD_FRACTION, huge.footerSize.height, 0.001f)
        // Short text leaves the card at full width.
        assertEquals(342f, CardInspectorFit.plan(available, hasFooter = true) { 40f }.cardSize.width, 0.001f)
        val bare = CardInspectorFit.plan(available, hasFooter = false) { error("not measured") }
        assertEquals(BoardSize(0f, 0f), bare.footerSize)
        assertEquals(342f, bare.cardSize.width, 0.001f)
    }

    @Test fun landscapeInspectorNarrowsTheCardBeforeShrinkingText() {
        val available = BoardSize(500f, 360f)
        val largest = minOf(500f * CardInspectorFit.LANDSCAPE_CARD_FRACTION, 360f * 63f / 88f)
        val roomy = CardInspectorFit.plan(available, hasFooter = true) { 200f }
        assertTrue(roomy.horizontal)
        assertEquals(largest, roomy.cardSize.width, 0.001f)
        assertEquals(500f - largest - 16f, roomy.footerSize.width, 0.001f)
        // Text that only fits a wider column narrows the card.
        val wide = CardInspectorFit.plan(available, hasFooter = true) { width -> if (width >= 290f) 340f else 420f }
        assertTrue(wide.footerFits)
        assertEquals(largest * 0.74f, wide.cardSize.width, 0.001f)
        assertTrue(wide.footerSize.width >= 290f)
        val never = CardInspectorFit.plan(available, hasFooter = true) { 999f }
        assertFalse(never.footerFits)
        assertEquals(largest * 0.64f, never.cardSize.width, 0.001f)
        assertEquals(360f, never.footerSize.height, 0.001f)
    }

    @Test fun textScaleIsTheLargestThatFits() {
        assertEquals(1f, CardInspectorFit.textScale(500f) { 400f * it }, 0f)
        assertEquals(0.8f, CardInspectorFit.textScale(330f) { 400f * it }, 0f)
        assertEquals("the smallest when nothing fits", 0.6f, CardInspectorFit.textScale(100f) { 400f * it }, 0f)
    }

    @Test fun abilityBannerSitsBelowItsShowcaseCardAndNamesTheSource() {
        val ability = 106f
        val bannerHalfHeight = 17.5f // 16 pt heavy serif line plus 14 pt padding
        assertTrue(BoardFXBannerPlan.offset(ability, true) - bannerHalfHeight > ability / 2 * 1.05f)
        assertEquals("spell banners keep their place", 127f, BoardFXBannerPlan.offset(210f, true), 0f)
        assertEquals("no card without motion", 54f, BoardFXBannerPlan.offset(ability, false), 0f)
        assertEquals("Prodigal Pyromancer · ability", BoardFXBannerPlan.title("Ability", true, "Prodigal Pyromancer"))
        assertEquals("Ability", BoardFXBannerPlan.title("Ability", true, null))
        assertEquals("Deal 1 damage · ability", BoardFXBannerPlan.title("Deal 1 damage", true, " "))
        assertEquals("Lightning Bolt", BoardFXBannerPlan.title("Lightning Bolt", false, "Lightning Bolt"))
    }
}
