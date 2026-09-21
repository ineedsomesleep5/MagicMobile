# Run the MagicMobile server on your own computer

This launcher uses the checksum-verified **0.1.1 build 5 server candidate** (`5c44fae`, XMage `4825513`). It passed 1,094 real-engine HTTP assertions for two- and four-player opening flows on macOS. It is a **self-hosting foundation**, not an already-live cross-platform service. The shipped apps still need an approved HTTPS server endpoint and matching release configuration before phones can use this computer.

[Download the launcher ZIP](https://github.com/ineedsomesleep5/MagicMobile/releases/download/server-build5-4825513/magicmobile-selfhost-0.1.1-build5.zip), then follow the first-time setup below. After setup, the launch file starts your server with one double-click.

## First-time setup

1. Install [Temurin Java 17](https://adoptium.net/temurin/releases/?version=17) for your computer. The launcher checks it and never installs software silently. Windows also needs its built-in `tar.exe` (Windows 10/11); macOS/Linux use `curl` and `tar`.
2. Extract the small launcher ZIP into a folder you can write to. Allow about 600 MB of disk space for its verified download and extracted runtime. Start with at least 2 GB available RAM for the default 1 GB heap; one game is allowed at a time. This is a suggested budget, not a guarantee for every deck.
3. Open `server.properties` in a text editor. It contains **public settings only**, including MagicMobile's public Supabase key and exact build identity. Never put a service-role key, password, access token, or signing key here.
4. The project owner must install and verify the reviewed matchmaking migration first. Only then set `DATABASE_MIGRATION_READY=true`. Its default `false` intentionally stops before downloading or starting a partially configured service.
5. Windows: double-click **Start-MagicMobile.cmd**. macOS: double-click **Start-MagicMobile.command**. Linux: run **Start-MagicMobile.sh** in a terminal. If macOS downloaded-file protection prompts, review the files and use the normal Finder Open flow; the launcher does not disable protection or change security policies.

The first start downloads the exact GitHub runtime asset and checks its pinned SHA-256 before extraction. Later starts use that verified local cache. Keep this folder private to trusted local users: cached files are not a tamper-proof installation. No administrator access, firewall changes, login items, background services, or automatic start are configured.

Keep the terminal and computer running while people play. Closing it, pressing **Ctrl+C**, shutting down, or sleeping the computer ends its active games. There is no durable game restore. To stop, press Ctrl+C and then close the launcher window. To start again, use the same launch file.

## Check it locally

After startup, open `http://127.0.0.1:8088/health` on that computer. It should return `{"ok":true}`. This checks the server process; it does not prove Supabase matchmaking, public connectivity, or phone gameplay.

`BIND_ADDRESS=127.0.0.1` is the safe default for a same-computer HTTPS reverse proxy. Do not expect a phone's `localhost` to reach this computer. Internet play additionally requires a reachable HTTPS hostname/reverse proxy, deliberate network access, the reviewed Supabase migration, and a matching endpoint configured in the iOS/Android release. Those are separate setup steps; the launcher does not change your router/firewall or add an app endpoint setting.

## Version and troubleshooting

The download URL, SHA-256, and cache directory are pinned in `runtime.properties`; do not replace them with a moving `latest` URL. Build identity must match both the compiled engine and the mobile build. A new app update may require a newly verified server package.

- **Setup pending:** the database migration is not ready. Leave the default gate closed until the project owner confirms it.
- **Java 17 required:** install/select Java 17; `JAVA_HOME` can point at that installation for this terminal.
- **Checksum failed:** no downloaded code was started. Preserve the message, remove only the indicated `.runtime/...tar.gz` download, and retry.
- **Port already in use:** stop the earlier server or choose another `PORT` and update your proxy configuration.
- **Window exits/errors:** it stays open so you can read the error. No secret credentials should appear in shared logs.

Windows launchers are source-reviewed but require actual Windows acceptance. The portable Java runtime has passed macOS opening-game checks; Linux/Windows and sustained real-player play are separate acceptance gates.
