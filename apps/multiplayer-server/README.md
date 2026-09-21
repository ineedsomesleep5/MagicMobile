# Dedicated multiplayer server

JDK 17 HTTP adapter for the real current XMage engine, with Supabase Auth and existing lobby RPCs. Clients use HTTPS through Caddy. No service-role key is used. Each match owns an independent engine, and each authenticated Supabase user is bound to exactly their seat. Remote clients can only poll or respond; all other engine operations remain private.

Build the real JVM engine with `bash packages/ondevice-engine/scripts/build_jvm.sh`, then `bash apps/multiplayer-server/build.sh`. The engine build needs its documented pinned upstream/toolchain. Unit tests compile only the core and use an explicitly synthetic test port; they do not prove real engine or device gameplay.

Set `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and `MAGICMOBILE_BUILD_IDENTITY` (JSON with protocolVersion, upstreamCommit, catalogueHash, adapterVersion). `MAX_MATCHES` defaults to 1 and is capped at 4. Increase it only after profiling actual games on the host. Main checks upstream/catalogue/protocol against the compiled engine before listening. Run with `bash apps/multiplayer-server/run.sh`.

For Oracle Always Free, provision an eligible Linux ARM VM only after verifying the tenancy free allowance. The conservative launch configuration targets 1 CPU and 6 GB RAM: one match, a 3 GB JVM heap, and a 4 GB service memory limit. This is a resource budget, not a verified host-capacity claim; profile a real four-player game before release. Do not enable paid upgrades. Install JDK 17 and Caddy, build engine/runtime paths on the destination machine, create an unprivileged `magicmobile` user, place checkout in `/opt/magicmobile`, and configure `/etc/magicmobile/multiplayer.env`. Use the supplied systemd and Caddy templates. Permit only SSH as needed and HTTPS/HTTP for certificate issuance; port 8088 remains loopback. Do not put JWTs in URLs, access logs, or environment files. A public DNS name and successful HTTPS check are required before shipping the endpoint in clients.

The service has a small bounded request pool, body/time limits, per-user quotas, and 30-minute inactive game expiry. A server restart loses games. Foreground interruption can reconnect while the server session survives; it is not persistent save/resume. Explicit leave ends the whole active game. Supabase status `active` without a local engine returns a lobby with `status: interrupted` and null match/seat IDs so clients can leave and recreate. Requests to a lost engine return HTTP 410 `session_lost`. There is no quick matchmaking yet.

`GET /v1/lobbies/current` returns the authenticated user's plain lobby or JSON `null` when none exists. Call it when restoring the app and after an uncertain create/join response; do not repeat the create/join mutation to discover its outcome. `POST /v1/lobbies/{id}/leave` returns `{left:true}` when already absent/ended and rejects a different current lobby. The lobby ID remains available in `interrupted` responses even after engine memory was lost.

A waiting/ready lobby whose caller deck submission was lost also returns `interrupted`, allowing leave/recreate. Create/join commits membership and installs the submitted deck under the same server monitor used for lobby reads; a concurrent recovery read cannot observe the intermediate state as an interruption.

The database must provide `matchmaking_leave_match(p_match_id uuid)`, checking the caller's current match against the expected ID atomically before leaving. The old parameterless leave RPC is intentionally unsupported by this adapter because a status-check/leave race could leave a newly joined lobby.

Deployment is not complete until real engine two-player and four-player tests, cross-platform device play, hidden-information isolation, reconnect, and public TLS checks pass. Free VM capacity/availability is not guaranteed.

## Manual GitHub runtime package

After the pinned engine and matching app catalogue are reviewed and committed, choose **Actions → Package verified multiplayer runtime (manual) → Run workflow** on that exact ref. The public-repository standard `macos-26-intel` job builds fresh, exports all five precons through the Swift resolver, checks bridge regressions, and runs real two-/four-seat opening HTTP checks on the exact portable payload with a 256 MB heap. Download its candidate archive, checksum, provenance, and logs from Actions artifacts; publication and updating the self-host launcher's pinned URL/checksum remain separate reviewed steps. It never deploys or accesses Supabase. A passing macOS probe does not establish Windows/Linux execution, sustained games, mobile parity, or fit within a 512 MB host. Java 17 and matching committed catalogue are hard gates; an upstream change requiring a different toolchain must be reviewed rather than bypassed. Local receipt helper: `node apps/multiplayer-server/resolved-deck-proof.mjs /path/to/fresh-swift-export`.

## Portable Render trial

`Main` defaults to `BIND_ADDRESS=127.0.0.1` and port 8088 for the VM proxy route. Render must explicitly set `BIND_ADDRESS=0.0.0.0` and use its `PORT` (normally 10000). The launch script accepts `JAVA_HEAP_INITIAL`, `JAVA_HEAP_MAX`, and `JAVA_PROCESSORS`; existing VM defaults remain 256m/3g/1. The Docker template uses a **trial** 64m/256m/1 budget and one match. A 256 MB Java heap is not a 256 MB process limit: metaspace, native memory, threads and the OS still consume memory. This does not establish acceptance within Render Free's 512 MB instance.

Prepare exact runtime bytes without building XMage again:

```sh
JAVA_HOME=/path/to/jdk17 node apps/multiplayer-server/package-runtime.mjs \
  --name render-trial-unique \
  --decks packages/ondevice-engine/build/included-smoke-decks
```

The command compiles only the small Java HTTP adapter and optional diagnostic class, preserves the existing runtime classpath order/resources and complete dependency JARs, and writes an ignored `build/render-trial-unique/` directory plus `.tar.gz`. It refuses an existing output directory. The result includes SHA256SUMS, relative classpaths, exact file hashes, source labels, dependency inventory, XMage license/project notices, and original dependency-JAR license/notice resources. It includes no signing files, environment configuration or application credentials. Diagnostic deck provenance is checked and sanitized to repository-relative paths. A final release artifact should be packaged from reviewed committed source; a dirty-source artifact is explicitly labeled for trials.

Root can publish the tarball as an immutable GitHub prerelease asset and use `deploy/Dockerfile` in Render with build arguments `RUNTIME_URL` (the exact release asset URL) and `RUNTIME_SHA256`. The Docker build checks both the archive digest and all packaged file hashes. It does not compile the engine, run Docker locally, or copy a local repository/build cache. Pin `JRE_IMAGE` to the reviewed base-image digest for a repeatable production image. Supabase URL/publishable key/build identity are runtime environment values; never include a service-role key.

For a first free-host acceptance trial, set `RUN_STARTUP_SMOKE=1`. `start.sh` runs the included real-XMage two-/four-seat HTTP smoke with five included resolved decks, using synthetic Auth/lobby data and no Supabase writes. It has a 150-second bound and uses the configured heap. Diagnostic classes are confined to a separate classpath; they are never reachable through production HTTP and are absent from the normal server classpath. Only after the probe exits successfully does production Main start. Failed probe logs are an honest host-capacity failure, not a reason to upgrade/pay automatically. Free-host spin-down/restarts lose active games; app endpoints must stay unconfigured until hosted acceptance and cross-platform device play pass.

These files prepare a deployment candidate. They do not publish an artifact, create a Render service, configure Supabase, or demonstrate 512 MB acceptance.
