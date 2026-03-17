# Teleport MCP Server

A self-hosted MCP (Model Context Protocol) server that exposes Teleport cluster administration as tools for Claude Code and other MCP-compatible AI agents. Deployed in-cluster on Kubernetes, accessible through Teleport's app proxy with full RBAC enforcement.

## What it is

The MCP server lets AI agents interact with your Teleport cluster directly — listing nodes, approving access requests, managing locks, inspecting roles, and running any `tctl` command — without requiring the agent to have `tsh`/`tctl` installed locally or a long-lived admin credential on disk.

Everything goes through Teleport's existing access controls. The AI agent authenticates as a low-privilege `mcp-client` bot (which only has app access + MCP tool permission), and the actual admin operations are executed server-side by a separate `mcp-admin` bot running inside the cluster.

### Architecture

```
MCP client (Claude Code, etc.)
  → tsh mcp connect  (stdio ↔ HTTP bridge, authenticated via tbot identity)
    → Teleport App Proxy  (mcp+http scheme, enforces MCP RBAC)
      → teleport-mcp K8s Service :8011
        → Python MCP server  (FastMCP, stateless streamable-http)
          → tctl  (using tbot machine identity from /opt/machine-id/identity)
            → Teleport Auth Server
```

### Two-bot design

| Bot | Role | Join Method | Purpose |
|-----|------|-------------|---------|
| `mcp-admin` | `mcp-admin` | Kubernetes (in-cluster) | Server-side: executes tctl commands with admin CRUD on all resource types |
| `mcp-client` | `mcp-client` | Token (local machine) | Client-side: authenticates the developer's tsh session with app access + MCP tool permissions |

### Available tools (17)

| Tool | Description |
|------|-------------|
| `list_nodes` | List all SSH nodes |
| `list_apps` | List all applications |
| `list_databases` | List all databases |
| `list_kube_clusters` | List all Kubernetes clusters |
| `list_resources(kind)` | List any resource kind (role, user, token, bot, connector, access_list, lock) |
| `get_resource(kind, name)` | Get a specific resource by kind and name |
| `list_access_requests` | List pending access requests |
| `search_audit_events(since)` | Search audit events within a time window |
| `list_active_sessions` | List active sessions |
| `cluster_info` | Get cluster status |
| `approve_access_request(id)` | Approve a pending access request |
| `deny_access_request(id)` | Deny a pending access request |
| `create_lock(target, target_type)` | Lock a user or resource |
| `delete_lock(id)` | Remove a lock |
| `create_resource(yaml_content)` | Create a Teleport resource from YAML |
| `update_resource(yaml_content)` | Update (create or overwrite) a resource from YAML |
| `delete_resource(kind, name)` | Delete a resource by kind and name |

---

## Prerequisites

- **Teleport v18.7+** — the `mcp.tools` RBAC field and `mcp+http` URI scheme are required
- **Kubernetes cluster** (EKS, GKE, AKS, etc.) with Teleport already running
- **Teleport Kubernetes operator** installed in your cluster (manages CRDs)
- **Teleport kube-agent** with `appResources` enabled — this allows the agent to auto-discover `TeleportAppV3` CRDs. Without it, the `teleport-mcp` app will not appear in Teleport.
- **Terraform providers**: `hashicorp/kubernetes`, `alekc/kubectl`, `hashicorp/random`
- **`tsh`** and **`tbot`** installed on developer machines

### Verify kube-agent appResources

In your kube-agent Helm values, confirm `appResources` is present:

```yaml
# teleport-kube-agent values
roles: kube,app
kubeClusterName: my-cluster
apps:
  - name: placeholder   # at least one static app or appResources must be set
appResources:
  - labels:
      "*": "*"
```

Without `appResources`, the operator can create `TeleportAppV3` CRDs but the kube-agent won't pick them up and register the app with the auth server.

---

## Deployment

### Step 1: Copy the Terraform files

Copy the contents of this directory into your Terraform project:

```
your-project/
  teleport-mcp/
    main.tf
    variables.tf
    outputs.tf
    files/
      server.py
```

Or include it directly if you prefer a flat layout — there are no module references, just plain resources.

### Step 2: Configure variables

Create a `terraform.tfvars` (or set variables in your root module):

```hcl
teleport_cluster_fqdn       = "teleport.example.com"
teleport_version            = "18.7.0"
namespace                   = "teleport-mcp"
teleport_operator_namespace = "teleport"   # namespace where Teleport Helm chart is installed
```

The `teleport_operator_namespace` must match the namespace where the Teleport operator is watching for CRDs. This is typically the same namespace as your `helm_release` for Teleport.

### Step 3: Apply

```bash
terraform init
terraform apply
```

The deployment takes a few minutes on first run while the `mcp-server` container downloads `tctl` from the Teleport CDN.

### Step 4: Retrieve the client join token

```bash
terraform output -raw mcp_client_join_token
```

Save this value — you'll use it in the tbot config on your local machine.

---

## Local Client Setup

The local setup runs a `tbot` daemon that maintains a short-lived identity, then uses `tsh mcp connect` to bridge stdio to the Teleport app proxy.

### Step 1: Create directories

```bash
mkdir -p ~/.tbot-YOUR_CLUSTER/{state,identity,logs}
```

### Step 2: Create tbot config

Copy `client/tbot.yaml.tpl` to `~/.tbot-YOUR_CLUSTER/tbot.yaml` and fill in the placeholders:

```yaml
version: v2
proxy_server: teleport.example.com:443

onboarding:
  join_method: token
  token: <token from terraform output>

storage:
  type: directory
  path: ~/.tbot-YOUR_CLUSTER/state

credential_ttl: 24h
renewal_interval: 1h

services:
  - type: identity
    allow_reissue: true    # REQUIRED — see Troubleshooting
    destination:
      type: directory
      path: ~/.tbot-YOUR_CLUSTER/identity
```

### Step 3: Start tbot as a background daemon (macOS)

Copy `client/launchd.plist.tpl` to `~/Library/LaunchAgents/com.YOUR_CLUSTER.tbot.plist`, fill in your username and paths, then:

```bash
launchctl load ~/Library/LaunchAgents/com.YOUR_CLUSTER.tbot.plist
```

Verify it started:

```bash
launchctl list | grep tbot
tail -f ~/.tbot-YOUR_CLUSTER/logs/tbot.log
```

For Linux, use a systemd user unit instead.

### Step 4: Add the MCP server to Claude Code

```bash
claude mcp add --transport stdio teleport -- \
  tsh mcp connect \
    -i ~/.tbot-YOUR_CLUSTER/identity/identity \
    --proxy teleport.example.com:443 \
    teleport-mcp
```

The `teleport-mcp` at the end is the app name as registered in Teleport (matches the `TeleportAppV3` metadata name in `main.tf`).

### Step 5: Restart Claude Code

The `mcp__teleport__*` tools will be available in all sessions.

---

## RBAC Requirements

Teleport v18.7+ enforces MCP-specific RBAC at the proxy layer. The `mcp-client` role needs **both** `app_labels` (to access the app) **and** `mcp.tools` (to use MCP tools through the proxy):

```yaml
kind: role
version: v7
metadata:
  name: mcp-client
spec:
  allow:
    app_labels:
      "*": "*"
    mcp:
      tools:
        - "*"
```

This is already configured in `main.tf`. The important thing to know is that if you add the MCP server to a different role or a role that already exists in your cluster, you must add the `mcp.tools` block — `app_labels` alone is not sufficient.

---

## Troubleshooting

### `tools/list` returns null / all tools show as unavailable

**Cause:** The `mcp-client` role is missing the `mcp.tools` permission block.

Teleport's MCP proxy performs a second RBAC check specifically for tool access, separate from the app access check. A role with only `app_labels` can reach the app but the proxy returns an empty tools list and denies all `tools/call` requests with "RBAC is enforced by your Teleport roles".

**Fix:** Ensure the role assigned to the client bot includes:

```yaml
mcp:
  tools:
    - "*"
```

---

### "identity is not allowed to reissue certificates"

**Cause:** The `allow_reissue: true` field is missing from the `identity` service in `tbot.yaml`.

`tsh mcp connect` needs to reissue a short-lived app certificate from the base identity. Without `allow_reissue`, tbot writes an identity that explicitly blocks certificate reissuance and `tsh` fails immediately with this error.

**Fix:** Add `allow_reissue: true` to the identity service in your local `tbot.yaml`:

```yaml
services:
  - type: identity
    allow_reissue: true
    destination:
      type: directory
      path: ~/.tbot-YOUR_CLUSTER/identity
```

---

### DNS rebinding / host validation errors

**Cause:** FastMCP's built-in DNS rebinding protection rejects requests where the `Host` header doesn't match the server's bind address. When Teleport proxies the app, the `Host` header reflects the Kubernetes service name, not `0.0.0.0`.

**Fix:** Already handled in `server.py` via:

```python
transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)
```

This is safe because the server sits behind Teleport's auth layer. Do not remove this setting.

---

### "session not found" / tools work once then fail

**Cause:** The MCP server is running in stateful mode (default FastMCP behavior), but Teleport's `mcp+http` proxy doesn't preserve session IDs across requests — each proxied request arrives without the session cookie or header that FastMCP expects.

**Fix:** Already handled in `server.py` via:

```python
stateless_http=True,
json_response=True,
```

Both settings are required. `stateless_http` makes each request independent. `json_response` makes the server return `application/json` instead of SSE streams, which Teleport's app proxy can forward correctly.

---

### tbot pod restarts / "token not found"

**Cause:** The `TeleportProvisionToken` CRD (`mcp-bot`) was created before the Teleport operator was ready, or the operator namespace is wrong.

**Fix:** Verify the provision token exists in Teleport:

```bash
tctl get tokens | grep mcp-bot
```

If it doesn't exist, check that `teleport_operator_namespace` matches the namespace where the Teleport operator is running, and that the operator pod is healthy. Then `terraform apply` again to re-create the CRD.

---

### App not appearing in `tsh apps ls`

**Cause:** The kube-agent doesn't have `appResources` configured, so it doesn't watch for `TeleportAppV3` CRDs.

**Fix:** Add `appResources` to your kube-agent Helm values (see Prerequisites above) and restart the kube-agent pod.

---

## Server Configuration Notes

The Python MCP server (`files/server.py`) uses FastMCP with settings that are specifically tuned for deployment behind Teleport's app proxy:

| Setting | Value | Why |
|---------|-------|-----|
| `stateless_http` | `True` | Teleport's mcp+http proxy doesn't preserve session IDs across requests |
| `json_response` | `True` | Teleport's mcp+http proxy expects `application/json`, not SSE streams |
| `transport_security` | DNS rebinding disabled | Server receives requests via K8s service hostname, not 0.0.0.0; behind Teleport auth |
| Transport | `streamable-http` | Required by Teleport's `mcp+http://` URI scheme |

Do not change these settings without testing — each one is required for the server to work correctly behind Teleport's proxy.

---

## Files

| File | Description |
|------|-------------|
| `main.tf` | All Terraform resources — namespace, CRDs, deployment, service, bots, roles, tokens |
| `variables.tf` | Input variables with descriptions and defaults |
| `outputs.tf` | Join token, namespace, service name, service FQDN |
| `files/server.py` | Python MCP server (FastMCP, stateless streamable-http) |
| `client/tbot.yaml.tpl` | Template tbot config for developer machines |
| `client/launchd.plist.tpl` | Template macOS launchd plist for running tbot as a background daemon |
