# Built by .github/workflows/deploy.yml (context ., file Dockerfile) and pushed
# to Artifact Registry.
#
# A job image, not a server: the default command runs scripts/check.sh, which
# checks policy formatting, runs `vault operator diagnose` on config/vault.hcl,
# boots a server from that config (it must come up sealed), then loads every
# policy into a throwaway dev-mode server and checks the access each grants.
# Every server it starts listens on 127.0.0.1 inside the container and is
# stopped before exit; nothing is published and nothing listens on $PORT.

FROM hashicorp/vault:2.1.1 AS runtime
ARG BUILD_ID=""
ENV BUILD_ID=$BUILD_ID HOME=/home/vault SKIP_SETCAP=1
USER root
# raft storage path from config/vault.hcl, owned by the image's non-root `vault` user
RUN mkdir -p /vault/data /app /home/vault \
 && chown vault:vault /vault/data /app /home/vault && chmod 700 /vault/data
WORKDIR /app
COPY --chown=vault:vault . .
USER vault
# the base image's ENTRYPOINT starts a server; the job is a script
ENTRYPOINT []
CMD ["sh", "scripts/check.sh"]
