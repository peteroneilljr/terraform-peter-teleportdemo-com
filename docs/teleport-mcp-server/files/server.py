#!/usr/bin/env python3
"""Teleport MCP server — exposes Teleport admin operations as MCP tools via tctl."""

import os
import subprocess
import tempfile

from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings

PROXY = os.environ["TELEPORT_PROXY"]
IDENTITY = os.environ.get("TELEPORT_IDENTITY", "/opt/machine-id/identity")
TCTL = os.environ.get("TCTL_PATH", "/opt/teleport-bin/tctl")

mcp = FastMCP(
    "teleport",
    host="0.0.0.0",
    port=8011,
    # Stateless mode — each request is independent (no session tracking).
    # Required because Teleport's mcp+http proxy doesn't preserve session IDs.
    stateless_http=True,
    # Return plain JSON responses instead of SSE streams for tool results.
    # Required by Teleport's mcp+http app proxy.
    json_response=True,
    # Disable DNS rebinding protection — behind Teleport's own auth layer.
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)


def run_tctl(*args) -> str:
    cmd = [TCTL, "--identity", IDENTITY, "--auth-server", PROXY] + list(args)
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise Exception(f"tctl error: {result.stderr}")
    return result.stdout


# ---------------------------------------------------------------------------
# Read operations
# ---------------------------------------------------------------------------

@mcp.tool()
def list_nodes() -> str:
    """List all SSH nodes in the Teleport cluster."""
    return run_tctl("nodes", "ls", "--format", "json")


@mcp.tool()
def list_apps() -> str:
    """List all applications registered in Teleport."""
    return run_tctl("apps", "ls", "--format", "json")


@mcp.tool()
def list_databases() -> str:
    """List all databases registered in Teleport."""
    return run_tctl("db", "ls", "--format", "json")


@mcp.tool()
def list_kube_clusters() -> str:
    """List all Kubernetes clusters registered in Teleport."""
    return run_tctl("kube", "ls", "--format", "json")


@mcp.tool()
def list_resources(kind: str) -> str:
    """List resources of a given kind (e.g. role, user, token, bot, connector, access_list, lock)."""
    return run_tctl("get", kind, "--format", "json")


@mcp.tool()
def get_resource(kind: str, name: str) -> str:
    """Get a specific resource by kind and name."""
    return run_tctl("get", f"{kind}/{name}", "--format", "json")


@mcp.tool()
def list_access_requests() -> str:
    """List pending access requests."""
    return run_tctl("requests", "ls", "--format", "json")


@mcp.tool()
def search_audit_events(since: str = "1h") -> str:
    """Search audit events within a time window (e.g. '1h', '24h', '7d')."""
    return run_tctl("audit", "ls", "--format", "json", "--since", since)


@mcp.tool()
def list_active_sessions() -> str:
    """List active sessions."""
    return run_tctl("sessions", "ls", "--format", "json")


@mcp.tool()
def cluster_info() -> str:
    """Get Teleport cluster status information."""
    return run_tctl("status")


# ---------------------------------------------------------------------------
# Write operations
# ---------------------------------------------------------------------------

@mcp.tool()
def approve_access_request(id: str, reason: str = "") -> str:
    """Approve a pending access request."""
    args = ["requests", "approve", id]
    if reason:
        args += ["--reason", reason]
    return run_tctl(*args)


@mcp.tool()
def deny_access_request(id: str, reason: str = "") -> str:
    """Deny a pending access request."""
    args = ["requests", "deny", id]
    if reason:
        args += ["--reason", reason]
    return run_tctl(*args)


@mcp.tool()
def create_lock(target: str, target_type: str = "user", message: str = "", ttl: str = "") -> str:
    """Lock a user or resource to prevent access.

    Args:
        target: The name of the target to lock.
        target_type: The type of target (user, role, node, mfa_device, windows_desktop, access_request, device).
        message: Optional message explaining why the lock was created.
        ttl: Optional lock duration (e.g. '1h', '24h'). Omit for a permanent lock.
    """
    args = ["lock", f"--{target_type}={target}"]
    if message:
        args.append(f"--message={message}")
    if ttl:
        args.append(f"--ttl={ttl}")
    return run_tctl(*args)


@mcp.tool()
def delete_lock(id: str) -> str:
    """Remove a lock by its ID."""
    return run_tctl("rm", f"lock/{id}")


@mcp.tool()
def create_resource(yaml_content: str) -> str:
    """Create a Teleport resource from a YAML definition."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        f.write(yaml_content)
        tmpfile = f.name
    try:
        return run_tctl("create", "-f", tmpfile)
    finally:
        os.unlink(tmpfile)


@mcp.tool()
def update_resource(yaml_content: str) -> str:
    """Update a Teleport resource from a YAML definition (creates or overwrites)."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        f.write(yaml_content)
        tmpfile = f.name
    try:
        return run_tctl("create", "-f", tmpfile, "--force")
    finally:
        os.unlink(tmpfile)


@mcp.tool()
def delete_resource(kind: str, name: str) -> str:
    """Delete a Teleport resource by kind and name."""
    return run_tctl("rm", f"{kind}/{name}")


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
