version: v2
# Replace with your Teleport cluster's proxy address
proxy_server: YOUR_CLUSTER_FQDN:443

onboarding:
  join_method: token
  # Token value from: terraform output -raw mcp_client_join_token
  token: YOUR_JOIN_TOKEN

storage:
  type: directory
  # State directory — tbot stores its renewal state here
  path: ~/.tbot-YOUR_CLUSTER/state

credential_ttl: 24h
renewal_interval: 1h

services:
  - type: identity
    # REQUIRED: allow_reissue must be true.
    # Without it, `tsh mcp connect` fails with:
    #   "identity is not allowed to reissue certificates"
    allow_reissue: true
    destination:
      type: directory
      # Identity directory — tsh mcp connect reads the identity file here
      path: ~/.tbot-YOUR_CLUSTER/identity
