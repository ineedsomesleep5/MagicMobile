# XMage Commander State Mapping

This document details how Commander-specific rules and state metrics (tax, damage, command zone card states) are mapped from real XMage rules engine data.

## Commander Tax (Cast Counts)

XMage does not expose a raw `commanderTax` field in the client View data. However, the XMage server automatically appends formatting text to the commander card view's rules list.
The server method `addCardInfoToCommander` gets the plays count from the server's `CommanderPlaysCountWatcher` and formats it as:
`"<b>CommanderTypeName</b> playsCount time/times played from the command zone."`

### Derivation & Parsing
The Java bridge (`MagicMobileBridge.java`) scans the rules list of the commander cards (located in the command zone, battlefield, graveyard, or exile) and cleans the HTML markup to match:
`"played from the command zone"`

The bridge extracts the plays count integer from this string, including the observed XMage form
`"Commander 1 time played from the command zone."`, and calculates:
$$\text{Commander Tax} = \text{Plays Count} \times 2$$

This is mapped directly to the `commanderTax` property on each `PlayerGameState` object.

Live verification: on June 22, 2026, the real bridge smoke
`XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-state pnpm smoke:xmage`
cast `Isamaru, Hound of Konda` from the command zone and reported:
```json
"commanderTaxChanges": [
  { "playerId": "human", "tax": 2, "turn": 2 }
]
```

## Commander Damage Matrix

Similarly, commander combat damage is tracked by the server's `CommanderInfoWatcher` and added to the commander card's rules list:
`"<b>CommanderTypeName</b> did damage combat damage to player playerName."`

### Derivation & Parsing
The Java bridge parses this string using a regular expression:
`"did (\\d+) combat damage to player (.+)"`

It extracts the damage total and resolves the recipient player's name back to their player ID, populating the `commanderDamage` dictionary on the recipient's state:
```json
"commanderDamage": {
  "ai-1": 6,
  "human": 0
}
```

Live verification: the same real `commander-state` smoke attacked with Isamaru, reached combat damage, dropped the AI life total to 38, and reported:
```json
"commanderDamageChanges": [
  { "recipient": "ai-1", "attacker": "human", "damage": 2, "turn": 4 }
]
```

## Command Zone UI Representation

Commander cards in the command zone are serialized as full `ZoneCard` objects inside `zones.command` for each player. They include:
* Stable card instance IDs.
* Type lines and color identity fields.
* Tapped state and power/toughness stats.
* Badges indicating current tax level and damage history.
