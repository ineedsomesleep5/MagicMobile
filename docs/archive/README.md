# Archived web-era docs

These documents describe the earlier web stack: the Next.js web app, Expo scaffold,
hosted XMage gateway and Java bridge, Docker Compose deployment and the shared
TypeScript packages. That code was removed from the tree and is preserved at the
[`archive/legacy-web`](https://github.com/ineedsomesleep5/MagicMobile/tree/archive/legacy-web)
tag. Paths such as `apps/web`, `apps/xmage-gateway` or `scripts/deploy-hosted.sh`
mentioned below exist only at that tag. The hosted server they describe is offline.

The current product is the native iOS and Android apps with the on-device XMage engine;
start from the [repository guide](../../README.md).

| Document | Topic |
| --- | --- |
| [DEPLOY.md](DEPLOY.md) | Hosted web/gateway/bridge deployment |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Initial web/Expo monorepo plan |
| [COMMANDER_ALPHA_READINESS.md](COMMANDER_ALPHA_READINESS.md) | Web/gateway CI, Docker and latency readiness |
| [PLAYER_SCOPED_SNAPSHOTS_PLAN.md](PLAYER_SCOPED_SNAPSHOTS_PLAN.md) | Gateway snapshot obfuscation plan |
| [REMOTE_DOCKER_WORKFLOW.md](REMOTE_DOCKER_WORKFLOW.md) | Remote Docker checks on the hosted server |
| [xmage-integration.md](xmage-integration.md) | Engine adapter and gateway integration |
| [XMAGE_BRIDGE_STATUS.md](XMAGE_BRIDGE_STATUS.md) | Java bridge status |
| [XMAGE_COMMANDER_STATE.md](XMAGE_COMMANDER_STATE.md) | Commander state mapping in the bridge |
| [XMAGE_FIXTURE_SERVICE.md](XMAGE_FIXTURE_SERVICE.md) | Bridge fixture service |
| [XMAGE_MOBILE_GAP_ANALYSIS.md](XMAGE_MOBILE_GAP_ANALYSIS.md) | Gateway-era gap analysis |
| [XMAGE_MOBILE_NEXT_STEPS.md](XMAGE_MOBILE_NEXT_STEPS.md) | Gateway-era roadmap |
| [XMAGE_MOBILE_PLAYTEST_CHECKLIST.md](XMAGE_MOBILE_PLAYTEST_CHECKLIST.md) | Gateway playtest checklist |
| [XMAGE_MOBILE_ROUTE_COVERAGE.md](XMAGE_MOBILE_ROUTE_COVERAGE.md) | Gateway route coverage |
| [XMAGE_PROMPT_COVERAGE.md](XMAGE_PROMPT_COVERAGE.md) | Prompt coverage for the gateway and web client |
| [XMAGE_UPDATE_STRATEGY.md](XMAGE_UPDATE_STRATEGY.md) | Bridge image update policy |
