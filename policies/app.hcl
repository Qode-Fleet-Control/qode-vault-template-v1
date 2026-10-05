# app — what a running application may do: read its own secrets (KV v2 at secret/),
# and renew / look up its own token.

path "secret/data/app/*" {
  capabilities = ["read"]
}

path "secret/metadata/app/*" {
  capabilities = ["list", "read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
