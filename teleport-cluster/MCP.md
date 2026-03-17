# Teleport MCP Server

A custom MCP (Model Context Protocol) server that exposes Teleport cluster admin operations as tools for Claude Code and other MCP-compatible AI agents. Deployed in-cluster on EKS, accessible through Teleport's app proxy.

## Architecture

```
MCP client (Claude Code)
  → tsh mcp connect (stdio↔HTTP bridge, authenticated via tbot identity)
    → Teleport App Proxy (mcp+http, enforces MCP RBAC)
      → teleport-mcp K8s Service :8011
        → Python MCP server (FastMCP, stateless streamable-http)
          → tctl (using tbot machine identity from /opt/machine-id)
            → Teleport Auth Server
```

The server runs in the `psh-teleport-mcp` namespace as a 2-container pod:

| Container | Image | Role |
|-----------|-------|------|
| `tbot` | `public.ecr.aws/gravitational/teleport-distroless` | Authenticates via Kubernetes service account JWT, writes identity to shared volume |
| `mcp-server` | `python:3.12-slim` | Runs FastMCP server, shells out to `tctl` with tbot identity |

### Bot Identities

Two separate bots serve different purposes:

| Bot | Role | Join Method | Purpose |
|-----|------|-------------|---------|
| `mcp-admin` | `mcp-admin` | Kubernetes (in-cluster) | Server-side: tctl calls with full admin CRUD on all resource types |
| `mcp-client` | `mcp-client` | Token (local machine) | Client-side: tsh mcp connect with app access + MCP tool permissions |

## Available Tools (17)

### Read operations

| Tool | Description |
|------|-------------|
| `list_nodes` | List all SSH nodes |
| `list_apps` | List all applications |
| `list_databases` | List all databases |
| `list_kube_clusters` | List all Kubernetes clusters |
| `list_resources(kind)` | List any resource kind (role, user, token, bot, connector, access_list, lock) |
| `get_resource(kind, name)` | Get a specific resource by kind and name |
| `list_access_requests` | List pending access requests |
| `search_audit_events(since)` | Search audit events within a time window (e.g. '1h', '24h', '7d') |
| `list_active_sessions` | List active sessions |
| `cluster_info` | Get cluster status information |

### Write operations

| Tool | Description |
|------|-------------|
| `approve_access_request(id)` | Approve a pending access request |
| `deny_access_request(id)` | Deny a pending access request |
| `create_lock(target, target_type)` | Lock a user or resource to prevent access |
| `delete_lock(id)` | Remove a lock |
| `create_resource(yaml_content)` | Create a Teleport resource from YAML |
| `update_resource(yaml_content)` | Update (create or overwrite) a resource from YAML |
| `delete_resource(kind, name)` | Delete a resource by kind and name |

## Local Setup (Claude Code)

The MCP server is already configured for this project. To set it up on a new machine:

### 1. Get the join token

```bash
cd teleport-cluster
terraform output -raw mcp_client_join_token
```

### 2. Create tbot config

Create `~/.tbot-teleportdemo/tbot.yaml`:

```yaml
version: v2
proxy_server: peter.teleportdemo.com:443

onboarding:
  join_method: token
  token: <token from step 1>

storage:
  type: directory
  path: ~/.tbot-teleportdemo/state

credential_ttl: 24h
renewal_interval: 1h

services:
  - type: identity
    allow_reissue: true    # Required for tsh mcp connect to request app certificates
    destination:
      type: directory
      path: ~/.tbot-teleportdemo/identity
```

> `allow_reissue: true` is critical. Without it, `tsh mcp connect` fails with "identity is not allowed to reissue certificates".

### 3. Start tbot

Create a launchd agent at `~/Library/LaunchAgents/com.teleportdemo.tbot.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.teleportdemo.tbot</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/tbot</string>
        <string>start</string>
        <string>--config</string>
        <string>/Users/YOUR_USER/.tbot-teleportdemo/tbot.yaml</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USER/.tbot-teleportdemo/logs/tbot.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USER/.tbot-teleportdemo/logs/tbot.err.log</string>
</dict>
</plist>
```

```bash
mkdir -p ~/.tbot-teleportdemo/{state,identity,logs}
launchctl load ~/Library/LaunchAgents/com.teleportdemo.tbot.plist
```

### 4. Add MCP server to Claude Code

```bash
claude mcp add --transport stdio teleport -- \
  tsh mcp connect \
    -i ~/.tbot-teleportdemo/identity/identity \
    --proxy peter.teleportdemo.com:443 \
    teleport-mcp
```

### 5. Restart Claude Code

The `mcp__teleport__*` tools will be available in all sessions.

## RBAC Requirements

Teleport v18.7+ enforces MCP-specific RBAC. The client role needs **both** `app_labels` (to access the app) **and** `mcp.tools` (to use MCP tools):

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

Without `mcp.tools`, Teleport's MCP proxy returns `null` for `tools/list` and denies all `tools/call` requests with "RBAC is enforced by your Teleport roles".

## Server Configuration

The Python MCP server (`files/teleport-mcp-server.py`) uses FastMCP with these settings:

| Setting | Value | Why |
|---------|-------|-----|
| `stateless_http` | `True` | Teleport's mcp+http proxy doesn't preserve session IDs across requests |
| `json_response` | `True` | Teleport's mcp+http proxy expects application/json responses |
| `transport_security` | DNS rebinding disabled | Server runs behind Teleport's auth layer, receives requests via k8s service hostname |
| Transport | `streamable-http` | Required by Teleport's `mcp+http://` URI scheme |

## Terraform Resources

All defined in `teleport.mcp-bot.tf`:

### In-cluster (server-side)

| Resource | Name | Purpose |
|----------|------|---------|
| `kubernetes_namespace_v1` | `psh-teleport-mcp` | Dedicated namespace |
| `kubernetes_service_account_v1` | `teleport-mcp-tbot` | Service account for Kubernetes join |
| `kubectl_manifest` (TeleportRoleV7) | `mcp-admin` | Admin CRUD on all Teleport resource types |
| `kubectl_manifest` (TeleportProvisionToken) | `mcp-bot` | Kubernetes join token for tbot sidecar |
| `kubectl_manifest` (TeleportBotV1) | `mcp-admin` | Bot identity with mcp-admin role |
| `kubectl_manifest` (TeleportAppV3) | `teleport-mcp` | App registration (auto-discovered by kube-agent) |
| `kubernetes_config_map` | `teleport-mcp-tbot` | tbot configuration |
| `kubernetes_config_map` | `teleport-mcp-server` | Python MCP server script |
| `kubernetes_deployment_v1` | `teleport-mcp` | 2-container pod (tbot + MCP server) |
| `kubernetes_service_v1` | `teleport-mcp` | ClusterIP service on port 8011 |

### Local client (developer machine)

| Resource | Name | Purpose |
|----------|------|---------|
| `kubectl_manifest` (TeleportRoleV7) | `mcp-client` | App access + MCP tool permissions |
| `random_password` | `mcp_client_token` | Join token value (lowercase, RFC 1123) |
| `kubectl_manifest` (TeleportProvisionToken) | *(random)* | Token join for local tbot |
| `kubectl_manifest` (TeleportBotV1) | `mcp-client` | Bot identity with mcp-client role |
| `output` | `mcp_client_join_token` | Sensitive output for local tbot config |
