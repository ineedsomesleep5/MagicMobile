import XCTest
@testable import MagicMobile

final class MagicMobileTests: XCTestCase {
    
    func testDeckImporter() {
        let deckText = """
        Commander
        1 Sol Ring
        Deck
        4 Island
        4 Forest
        """
        let list = DeckImporter.parse(text: deckText, source: "Test source")
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.commander?.cardName, "Sol Ring")
        XCTAssertEqual(list?.entries.count, 2)
    }
    
    func testCardIdentityHelpers() {
        let landCard = CardIdentity(name: "Island", typeLine: "Basic Land — Island", oracleText: "{T}: Add {U}.")
        XCTAssertTrue(landCard.isLand)
        XCTAssertFalse(landCard.isCreature)
        
        let creatureCard = CardIdentity(name: "Grizzly Bears", typeLine: "Creature — Bear", oracleText: nil)
        XCTAssertFalse(creatureCard.isLand)
        XCTAssertTrue(creatureCard.isCreature)
    }
}
