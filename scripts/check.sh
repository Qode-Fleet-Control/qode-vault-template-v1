#!/bin/sh
# The job, in three parts. Exits non-zero on the first failure.
#   1. policies/*.hcl are canonically formatted (`vault policy fmt` on a copy, then diff);
#   2. config/vault.hcl passes `vault operator diagnose`, and a real server boots from it
#      and answers `vault status` as sealed + uninitialised (exit code 2);
#   3. a throwaway dev-mode server (in memory, 127.0.0.1 only) accepts every policy, and
#      tokens holding them get exactly the access the policies promise.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
pids=""
cleanup() { for p in $pids; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT

wait_for_vault() { # $1 = address; up when `vault status` answers at all (0 unsealed, 2 sealed)
  i=0
  while :; do
    rc=0; VAULT_ADDR=$1 vault status >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 1 ] && return 0
    i=$((i + 1)); [ "$i" -gt 30 ] && { echo "vault at $1 did not come up" >&2; return 1; }
    sleep 1
  done
}

echo "==> vault version"; vault version

# --- 1. policy formatting ---------------------------------------------------------------
for p in policies/*.hcl; do
  echo "==> vault policy fmt (check) $p"
  cp "$p" "$work/fmt.hcl"
  vault policy fmt "$work/fmt.hcl" >/dev/null
  diff -u "$p" "$work/fmt.hcl"
done

# --- 2. server configuration ------------------------------------------------------------
echo "==> vault operator diagnose -config=config/vault.hcl"
# 0 = all checks passed, 2 = warnings only (TLS disabled, single raft voter ...), 1 = failure
rc=0; vault operator diagnose -config=config/vault.hcl || rc=$?
[ "$rc" -eq 1 ] && { echo "diagnose reported a failure" >&2; exit 1; }

echo "==> vault server -config=config/vault.hcl (background)"
vault server -config=config/vault.hcl >"$work/server.log" 2>&1 &
pids="$pids $!"
wait_for_vault http://127.0.0.1:8200 || { cat "$work/server.log" >&2; exit 1; }
rc=0; VAULT_ADDR=http://127.0.0.1:8200 vault status || rc=$?
[ "$rc" -eq 2 ] || { echo "expected a sealed, uninitialised server (exit 2), got $rc" >&2; exit 1; }
kill $pids; wait $pids 2>/dev/null || true; pids=""

# --- 3. policies against a dev server ---------------------------------------------------
export VAULT_ADDR=http://127.0.0.1:8210 VAULT_TOKEN=root
echo "==> vault server -dev (background, $VAULT_ADDR)"
vault server -dev -dev-root-token-id=root -dev-listen-address=127.0.0.1:8210 >"$work/dev.log" 2>&1 &
pids="$pids $!"
wait_for_vault "$VAULT_ADDR" || { cat "$work/dev.log" >&2; exit 1; }

for p in policies/*.hcl; do
  name=$(basename "$p" .hcl)
  echo "==> vault policy write $name $p"
  vault policy write "$name" "$p"
done

expect() { # expect <policy> <path> <capability-substring>
  tok=$(vault token create -policy="$1" -ttl=5m -field=token)
  caps=$(vault token capabilities "$tok" "$2")
  case " $caps " in
    *"$3"*) echo "    ok  $1 on $2: $caps" ;;
    *) echo "    FAIL $1 on $2: got [$caps], want $3" >&2; exit 1 ;;
  esac
}
echo "==> capability checks"
expect app   secret/data/app/config  read
expect app   secret/data/other/x     deny
expect ci    secret/data/app/config  update
expect ci    sys/policies/acl/app    deny
expect admin sys/policies/acl/app    update
expect admin sys/seal                deny

echo "==> app token reads its secret"
vault kv put secret/app/config greeting=hello >/dev/null
tok=$(vault token create -policy=app -ttl=5m -field=token)
[ "$(VAULT_TOKEN=$tok vault kv get -field=greeting secret/app/config)" = hello ]
echo "vault: config and policies valid"
