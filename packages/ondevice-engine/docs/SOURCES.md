# Inspected primary sources

Baseline inspected September 11, 2026. The lock is authoritative for build inputs.

- MagicMobile repository baseline: https://github.com/ineedsomesleep5/MagicMobile/tree/058478f690b713332c13d0a8369e98f5b792a282
- XMage selected commit: https://github.com/magefree/mage/tree/8aea65ae9ae3c89970fe865e1316105539e097ca
- Card factory: `Mage/src/main/java/mage/cards/CardImpl.java`
- Set discovery and printing metadata: `Mage/src/main/java/mage/cards/Sets.java`, `ExpansionSet.java`, `CardSetInfo.java`
- Human response implementation: `Mage.Server.Plugins/Mage.Player.Human/src/mage/player/human/HumanPlayer.java`, `PlayerResponse.java`
- Query model: `Mage/src/main/java/mage/game/events/PlayerQueryEvent.java`
- Multi-amount wire parsing: `Mage/src/main/java/mage/constants/MultiAmountType.java` (space-separated integers)
- Projection: `Mage.Common/src/main/java/mage/view/GameView.java`, `CardView.java`
- Commander variant: `Mage.Server.Plugins/Mage.Game.CommanderFreeForAll/src/mage/game/CommanderFreeForAll.java`
- Deck validation: `Mage.Server.Plugins/Mage.Deck.Constructed/src/mage/deck/AbstractCommander.java`, `Commander.java`
- Human settings: `Mage/src/main/java/mage/players/net/UserData.java`
- Graal shared-library guide: https://www.graalvm.org/latest/reference-manual/native-image/guides/build-native-shared-library/
- Gluon toolchain docs to validate during the actual iOS build: https://docs.gluonhq.com/
- J2ObjC alternative: https://developers.google.com/j2objc
- XcodeGen specification (to verify against installed generator): https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

Reading these APIs is not equivalent to compiling or running the complete project. See the status/evidence files for actual verification.
