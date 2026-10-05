# ci — what the deploy pipeline may do: manage the app's secrets, but never read other
# teams' paths or touch policies and auth methods.

path "secret/data/app/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "secret/metadata/app/*" {
  capabilities = ["list", "read", "delete"]
}

path "secret/delete/app/*" {
  capabilities = ["update"]
}

path "secret/undelete/app/*" {
  capabilities = ["update"]
}
