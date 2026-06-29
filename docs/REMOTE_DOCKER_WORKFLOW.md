# Remote Docker Workflow

MagicMobile should keep local Docker/Colima stopped by default to save Mac RAM.
Use the VPS for Docker-only verification and hosted deploys.

## Local Mac Policy

- Local Colima/Docker is not required for normal iOS, TypeScript, or gateway unit test work.
- Keep Colima stopped unless a task explicitly needs local Docker:

```sh
colima status || true
colima stop
```

- Prefer remote Docker checks for the XMage bridge image:

```sh
scripts/remote-docker-bridge-check.sh
```

## VPS Policy

The hosted MagicMobile stack runs through Docker Compose on the VPS. Do not stop
the VPS Docker daemon after production deploys if it is already running the live
services.

The remote bridge check helper follows this rule:

- If Docker is already running on the VPS, it leaves Docker running.
- If Docker is stopped, it starts Docker for the build check.
- It only stops Docker afterward when `STOP_REMOTE_DOCKER_AFTER=1` and the helper
  was the process that started Docker.

Use `STOP_REMOTE_DOCKER_AFTER=1` only for a dev-only VPS or a maintenance window.
For the production VPS, leave the default value unset.

## Defaults

- Deploy host: `root@100.107.89.62` through Tailscale
- Remote repo: `/root/MagicMobile`
- Remote ref for Docker checks: current remote checkout unless overridden by
  `MAGICMOBILE_REMOTE_REF`

## Related Commands

Hosted deploy stays in:

```sh
scripts/deploy-hosted.sh
```

The deploy script intentionally keeps production services running with
`docker compose up -d`.
