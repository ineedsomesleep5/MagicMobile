# MagicPath Board Handoff

Use MagicPath project `420728834988597248` and main component `eager-tower-7952` as the visual source of truth.

This handoff is for a future Codex session connected to the MagicMobile repo. It should implement the approved MagicPath design in SwiftUI while preserving the existing XMage command, prompt, stack, and zone functionality.

## MagicPath References

- Project: `MagicMobile iPhone 16 Pro Max Landscape Board`
- Project ID: `420728834988597248`
- Project URL: `https://www.magicpath.ai/files/420728834988597248`
- Main frame: `Normal Battlefield`
- Main frame/component ID: `420728860716449792`
- Main generated name: `eager-tower-7952`
- Current edited frame: `Dragging Card / Drop Zones Visible`
- Current edited frame ID: `420729376641007616`
- Current edited frame generated name: `sweet-week-7067`

## Other State Frames

| Frame | Component ID | Generated name | Export |
| --- | --- | --- | --- |
| Normal Battlefield | `420728860716449792` | `eager-tower-7952` | `exports/normal-battlefield.png` |
| Dragging Card / Drop Zones Visible | `420729376641007616` | `sweet-week-7067` | `exports/dragging-drop-zones.png` |
| Selected Card | `420729389609795584` | `cleverly-tide-3424` | `exports/selected-card.png` |
| Mana Payment Prompt | `420729401509023744` | `safely-garden-7226` | `exports/mana-payment-prompt.png` |
| Search Library Prompt | `420729414448467968` | `steady-river-7644` | `exports/search-library-prompt.png` |
| Stack Response Prompt | `420729424338628608` | `eagerly-river-8898` | `exports/stack-response-prompt.png` |
| Commander Replacement Prompt | `420729435940089856` | `cleverly-autumn-9282` | `exports/commander-replacement-prompt.png` |
| Damage Assignment Prompt | `420729447843528704` | `lively-sand-1892` | `exports/damage-assignment-prompt.png` |
| AI Thinking / Waiting | `420729460581601280` | `clear-week-6056` | `exports/ai-thinking-waiting.png` |
| Bridge Unavailable / Reconnect | `420729482081615872` | `kind-forest-2398` | `exports/bridge-unavailable-reconnect.png` |

Additional export metadata:

- `exports/magicpath-frame-data.json`
- `exports/magicpath-dragging-inspect.json`
- `exports/magicpath-preview-exports.json`
- `exports/magicpath-layer-data.json`

MagicPath CLI did not expose a dedicated SVG export or raw canvas JSON export command. The saved PNGs are preview exports only; the editable MagicPath project remains the source of truth.

## Design Intent

MagicMobile is an iPhone landscape digital Commander game powered by XMage. The board should feel like a polished mobile fantasy card game table: rustic medieval magic, dark stone battlefield, carved wood and dark leather accents, aged parchment details, warm gold trim, and restrained blue/green magical glows for priority, selected, target, stack, and valid-drop states.

The design should be readable before decorative. Cards are the focus.

## Layout Rules

- Use iPhone 16 Pro Max landscape at roughly `956 x 440` points.
- Keep safe-area padding visible in layout decisions.
- Opponent info is a narrow vertical HUD in the top-left, never a horizontal top bar.
- Opponent permanents sit naturally in the upper half.
- Player permanents sit naturally in the lower half, with creatures closer to center and lands/mana sources lower.
- Do not show large idle battlefield boxes.
- Drop zones are hidden in normal gameplay and visible only in the dragging state.
- Phase/step/priority is a compact right-side rail.
- Game log is a compact transparent right-side glass panel.
- Stack is compact but visible, with an expanded sheet only when requested.
- Hand is a bottom rail with slight fan/curve and tappable cards.
- Prompt overlays appear only when XMage asks for input.

## Interaction Rules

- Cast or play by dragging a card from hand.
- Play lands by dragging from hand to the battlefield/land area.
- Tap permanents directly to tap/use.
- Open compact contextual actions only when a selected permanent has multiple legal actions.
- Use one primary flow button for `Pass`, `Next`, `Resolve`, `Done`, `Continue`, or `Submit`.
- Do not add big `Cast` or `Tap` buttons.
- Tap glowing cards or players during target prompts.
- Tap chips for stack, command, graveyard, exile, library, log, and settings/debug sheets.
- Long press opens the card inspector.

## Prompt Safety Rules

Fail closed:

- submit disabled until valid
- no default yes
- no default colorless
- no default amount `0`
- no default pile `1`
- no default command zone
- no auto-pick first option
- unknown prompt fallback must be visible and safe

## SwiftUI Mapping Notes

Use `layout-map.json` for layer-to-component mapping. Preserve the separation between decorative styling and functional zones. The future SwiftUI implementation should build separate live views for board root, battlefield surface, HUD, battlefield cards, hand rail, stack indicator, phase rail, game log, prompt overlays, zone chips, card inspector, bridge status, and debug sheet.

## Remaining Manual Design Tasks

- Confirm exact Caleb-approved card rail overlap and curve.
- Tune safe-area offsets on physical iPhone 16 Pro Max.
- Replace placeholder card names/art treatments with final original fantasy placeholders if desired.
- Adjust glass opacity so the right log remains readable over busy board states.
- Confirm drag ghost/drop-zone position against real touch ergonomics.

## Future Implementation Instructions

Refactor the SwiftUI board zones to match MagicPath. Keep the existing real XMage data flow, prompt handling, command submission, stack behavior, and zone state. Do not flatten the design into PNGs. Use the PNG exports only as review aids.
