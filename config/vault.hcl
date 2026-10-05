# Vault server configuration: integrated (raft) storage on local disk, one TCP listener,
# the UI on. Checked by scripts/check.sh: `vault operator diagnose`, then a real server
# boots from it and must answer `vault status` (sealed, not yet initialised).
#
# Before production: put real TLS material on the listener (remove tls_disable), set
# api_addr / cluster_addr to the node's reachable address, add retry_join stanzas for the
# other nodes, and configure auto-unseal (seal "awskms" / "gcpckms" / "transit" ...).

ui            = true
disable_mlock = true # raft storage: mlock is not recommended; containers rarely allow it

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true # local / CI only — terminate TLS here in production
}

api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

default_lease_ttl = "768h"
max_lease_ttl     = "8760h"
