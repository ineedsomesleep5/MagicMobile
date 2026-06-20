# Data Policy

MagicMobile recommendations must be explicit about where data comes from and what the app is allowed to do with it.

## EDHREC

MagicMobile does not scrape EDHREC by default.

The current EDHREC support is limited to user-facing link-outs, such as a commander page URL. No crawler, scraper, private API, or undocumented endpoint is part of the default recommendation system.

An EDHREC-backed recommendation provider may only be enabled later after MagicMobile has a licensed, approved, or otherwise documented integration path. Until that exists, the EDHREC provider must remain disabled and must fail closed.

## Local Recommendations

The local recommendation provider is a placeholder for future recommendations based on approved data sources only.

Allowed future sources include:

- The user's own saved decks and game history.
- Public card metadata from approved sources.
- Licensed or explicitly permitted public deck data.

The local provider should not imply EDHREC-derived confidence, popularity, or synergy scores unless those values come from an approved integration.

## Defaults

The app may use mock recommendations for development and UI wiring. Mock recommendations must identify themselves as mock-sourced data.

Production recommendation behavior should prefer empty states over unapproved data collection.
