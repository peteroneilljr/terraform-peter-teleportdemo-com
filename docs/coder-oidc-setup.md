# Coder OIDC Setup

## Background

Coder supports **OIDC** for SSO but does **not** support SAML. Teleport can act as a SAML IdP but cannot act as an OIDC provider. This means Teleport cannot be Coder's identity provider directly.

To add SSO to both Coder and Teleport, use a shared upstream OIDC provider (Google Workspace, Okta, Entra ID, etc.) and configure each system independently:

- **Teleport** — configure a SAML connector pointing at the upstream IdP
- **Coder** — configure OIDC pointing at the same upstream IdP

## Prerequisites

- An OIDC-capable identity provider with an OAuth 2.0 client created for Coder
- The following values from your IdP:
  - **Issuer URL** (e.g. `https://accounts.google.com`)
  - **Client ID**
  - **Client Secret**

## Setup Steps

### 1. Create an OAuth Client in Your IdP

Create a new OAuth 2.0 / OIDC application in your identity provider with:

- **Redirect URI**: `https://coder.<cluster-fqdn>/api/v2/users/oidc/callback`
  - For this cluster: `https://coder.peter.teleportdemo.com/api/v2/users/oidc/callback`
- **Scopes**: `openid`, `profile`, `email`
- **Grant type**: Authorization Code

Save the client ID and client secret.

### 2. Add OIDC Environment Variables to the Helm Release

In `teleport-cluster/resource.coder.tf`, add the OIDC env vars to the `coder.env` block:

```hcl
values = [yamlencode({
  coder = {
    resources = {
      requests = { cpu = "1000m", memory = "2Gi" }
    }
    service = { type = "ClusterIP" }
    env = [
      { name = "CODER_PG_CONNECTION_URL", valueFrom = { secretKeyRef = { name = kubernetes_secret_v1.coder_db_url.metadata[0].name, key = "url" } } },
      { name = "CODER_ACCESS_URL", value = "https://coder.${local.teleport_cluster_fqdn}" },
      { name = "CODER_WILDCARD_ACCESS_URL", value = "*.coder.${local.teleport_cluster_fqdn}" },

      # OIDC SSO
      { name = "CODER_OIDC_ISSUER_URL",    value = "https://accounts.google.com" },
      { name = "CODER_OIDC_CLIENT_ID",      value = "<your-client-id>" },
      { name = "CODER_OIDC_CLIENT_SECRET",  value = "<your-client-secret>" },
      { name = "CODER_OIDC_ALLOW_SIGNUPS",  value = "true" },
    ]
  }
})]
```

> **Tip**: For production, store `CODER_OIDC_CLIENT_SECRET` in a Kubernetes secret and reference it via `valueFrom.secretKeyRef` instead of a plaintext `value`.

### 3. Apply

```bash
terraform apply
```

Coder will restart with OIDC enabled. The login page will show an OIDC sign-in button.

## Provider Examples

### Google Workspace

| Variable | Value |
|---|---|
| `CODER_OIDC_ISSUER_URL` | `https://accounts.google.com` |
| `CODER_OIDC_CLIENT_ID` | From Google Cloud Console > APIs & Services > Credentials |
| `CODER_OIDC_CLIENT_SECRET` | From the same OAuth 2.0 client |

Set the authorized redirect URI in Google Cloud Console to:
`https://coder.peter.teleportdemo.com/api/v2/users/oidc/callback`

### Okta

| Variable | Value |
|---|---|
| `CODER_OIDC_ISSUER_URL` | `https://<your-org>.okta.com` |
| `CODER_OIDC_CLIENT_ID` | From Okta application settings |
| `CODER_OIDC_CLIENT_SECRET` | From Okta application settings |

### Microsoft Entra ID (Azure AD)

| Variable | Value |
|---|---|
| `CODER_OIDC_ISSUER_URL` | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| `CODER_OIDC_CLIENT_ID` | Application (client) ID from App Registration |
| `CODER_OIDC_CLIENT_SECRET` | Client secret from Certificates & Secrets |

## Auto User Creation

Setting `CODER_OIDC_ALLOW_SIGNUPS=true` lets any user who authenticates via OIDC automatically get a Coder account. Set to `false` to require an admin to pre-create accounts.

Additional env vars for controlling user provisioning:

| Variable | Description |
|---|---|
| `CODER_OIDC_EMAIL_DOMAIN` | Restrict signups to specific email domains (comma-separated) |
| `CODER_OIDC_EMAIL_FIELD` | OIDC claim for the user's email (default: `email`) |
| `CODER_OIDC_USERNAME_FIELD` | OIDC claim for the username (default: `preferred_username`) |

## References

- [Coder OIDC Authentication Docs](https://coder.com/docs/admin/users/oidc-auth)
- [Teleport SAML IdP Guide](https://goteleport.com/docs/application-access/guides/saml-idp/)
