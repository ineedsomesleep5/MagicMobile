# Forge Architectural Lessons & Licensing Constraints

This document outlines the architectural patterns used by the Forge mobile/desktop codebase and notes key lessons learned for the design of MagicMobile.

> [!WARNING]
> **Licensing Warning (GPL-3.0)**:
> Forge is licensed under the GNU General Public License v3.0 (GPL-3.0). **No code, assets, or specific translation structures from Forge may be copied, adapted, or integrated into MagicMobile** unless the GPL-3.0 license implications are intentionally accepted for the entire MagicMobile project. MagicMobile remains a clean-room implementation of its client, using XMage's client protocol.

## Core Architectural Lessons

### 1. Engine & UI Separation
* **Forge Pattern**: Forge enforces a strict separation between the rules engine (`forge-game`), the AI opponent module (`forge-ai`), and the user interface. The engine runs on a separate thread, firing events to the UI thread.
* **MagicMobile Alignment**: We maintain a strict boundary where the XMage rules engine is the source of truth, and MagicMobile acts solely as a client displaying snapshots, rendering options, and submitting commands. We do not attempt to evaluate rules locally.

### 2. Prompt & Action Abstraction
* **Forge Pattern**: Forge represents user choices through generalized "input states" (e.g., InputSelectTargets, InputPayMana) rather than hardcoded screens.
* **MagicMobile Alignment**: Our `PromptEnvelopeV2` and `LegalAction` contracts mirror this abstraction. The client renders universal picker views (card, target, player, ability, piles) driven dynamically by server-sent options and limits.

### 3. Mobile Performance and Memory
* **Forge Pattern**: Running a full MTG rules engine, card database, and assets locally on a mobile device is highly resource-intensive and leads to high battery drain and memory overhead.
* **MagicMobile Alignment**: Rather than running the Java bridge inside the iOS/Android app, our architecture keeps the heavy engine (Java/XMage) on a remote server/gateway. The mobile client remains extremely lightweight, communicating via JSON over HTTP and WebSockets.

### 4. Deterministic Test Fixtures
* **Forge Pattern**: Forge uses scripted test games to walk complex card interactions deterministically.
* **MagicMobile Alignment**: Our gateway test suite (`server.test.mjs`) and live smoke script (`smoke-create-commander-game.ts`) automate full games through setup, mulligan, land, mana, and casting sequences to regression test prompt matching and cycle progressions.
