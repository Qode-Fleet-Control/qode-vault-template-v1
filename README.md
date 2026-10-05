# Vault template

Provisioned from [`Qode-Fleet-Control/fleet-template-v1`](https://github.com/Qode-Fleet-Control/fleet-template-v1) — the fleet
lifecycle contract (`bin/`, `fleet.conf`, `compose.yaml`, deploy workflows) with a [Vault](https://developer.hashicorp.com/vault) server configuration and ACL policies
laid on top.

**This repo is a job, not a service.** Its container checks the configuration and the
policies against real Vault servers it starts and stops itself (127.0.0.1 inside the
container), then exits — 0 when all of it passes. Nothing is published and nothing
listens on `$PORT`.

## What is in it

| file | |
|---|---|
| `config/vault.hcl` | server config: integrated (raft) storage, TCP listener, UI, api/cluster addresses, lease TTLs |
| `policies/app.hcl` | an application: read its own KV v2 secrets under `secret/app/`, renew/look up its token |
| `policies/ci.hcl` | the deploy pipeline: manage `secret/app/` (incl. delete/undelete), nothing else |
| `policies/admin.hcl` | operators: mounts, auth methods, ACL policies, all of `secret/` — not seal/rekey/raft |
| `scripts/check.sh` | the job (below) |

What `scripts/check.sh` does:

1. every policy is canonically formatted (`vault policy fmt` on a copy, then `diff`);
2. `vault operator diagnose -config=config/vault.hcl` reports no failure (warnings, such as
   TLS being disabled, are allowed), and a real `vault server -config=config/vault.hcl`
   boots and answers `vault status` as sealed and uninitialised;
3. a dev-mode server accepts `vault policy write` for every policy, and tokens holding each
   policy get exactly the capabilities promised (e.g. `app` can read
   `secret/data/app/config` but is denied `secret/data/other/x`; `admin` is denied
   `sys/seal`); an `app` token then reads a real secret.

## Run it

**On the fleet:** `bin/run` builds the image (`docker compose build`) and stops there —
`DOCKER_START_CMD` is empty because there is no server. Run the job with
`docker compose run --rm app`.

**With docker:**

    docker compose build
    docker compose run --rm app        # exit 0 = "vault: config and policies valid"

**Without docker** (needs `vault` on `PATH`, `/vault/data` writable and 127.0.0.1 ports
8200, 8201 and 8210 free):

    sh scripts/check.sh

To run the server for real: `vault server -config=config/vault.hcl`, then
`vault operator init` and unseal; load policies with `vault policy write app policies/app.hcl`.

## Origin

    hand-written — Vault ships no project generator

Config follows the server configuration reference (raft storage + tcp listener); policies
follow the policy docs (one file per policy, path + capabilities).

## Deviations, and why

- `Dockerfile` is a job image on `hashicorp/vault:2.1.1`: its `ENTRYPOINT` (which starts a
  server) is cleared and the default command is `scripts/check.sh`. Runs as the image's own
  non-root `vault` user; `/vault/data` is created for it (mode 700). `SKIP_SETCAP=1`: the
  config sets `disable_mlock`, so no `IPC_LOCK` capability is needed.
- `tls_disable = true` on the listener and `127.0.0.1` api/cluster addresses keep the config
  runnable on a laptop and in CI; the comments mark what to change for production (TLS,
  reachable addresses, `retry_join`, auto-unseal).
- No `telemetry` stanza: with a Prometheus-only stanza (`prometheus_retention_time`,
  `disable_hostname`) Vault 2.1's `operator diagnose` reports a *failure* ("incomplete
  Stackdriver telemetry configuration"), which would fail the job. Add yours once you know
  the sink, and keep the job green.

## Verified

**The docker job has NOT been verified yet.** On 2026-10-05 the build host's docker disk
stayed below the 6 GB floor (0-3 GB free) for over three hours, so `docker compose build`
was never run for this repo. Build and run it once before trusting it:

    docker compose build && docker compose run --rm app; docker compose down --rmi local -v

What WAS checked, with the real CLIs outside docker (same `scripts/check.sh` the image runs):

    vault 2.1.1: sh scripts/check.sh        # on a copy with ports/data path shifted for the host:
                                            # policy fmt ok, diagnose (warnings only), config server sealed (exit 2),
                                            # 3 policies written, 6 capability checks ok, app token read its secret -> exit 0

## Serving over HTTP

There is no HTTP surface. If you add one, listen on `0.0.0.0:$PORT`, serve at `/`, set
`PORT`, `HEALTH_PATH`, `START_CMD` and `DOCKER_START_CMD` in `fleet.conf`, and publish
`"${PORT}:${PORT}"` in `compose.yaml`. See `docs/fleet-lifecycle.md`.
