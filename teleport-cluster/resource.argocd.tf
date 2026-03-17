# ArgoCD SAML Login Architecture
#
# ArgoCD is exposed via Teleport's app proxy at argocd.peter.teleportdemo.com.
# Login flow: browser → ArgoCD UI → Dex (SAML SP) → Teleport SAML IDP → back to ArgoCD.
#
# Three pieces must be configured end-to-end:
#   1. Dex SAML connector (in ArgoCD Helm values below) — configures Dex as a SAML SP
#      pointing at Teleport as the IDP.
#   2. SAML SP registration in Teleport — tells Teleport which entityID/ACS URL belongs
#      to this SP. Done via `tctl create -f /etc/teleport-sp/saml-sp.yaml` (see ConfigMap
#      resource below for why this can't be automated via the operator).
#   3. ConfigMap + volume mount (in teleport.cluster.tf) — gets the SP definition YAML
#      into the auth pods so tctl can read it from inside the distroless container.

resource "kubernetes_namespace_v1" "argocd" {
  metadata { name = "psh-argocd" }
}

# Fetches Teleport's SAML IDP metadata XML so we can extract the signing certificate.
# Dex needs this cert (as caData) to validate the SAML responses Teleport sends back.
data "http" "teleport_saml_idp_metadata" {
  url = "https://${local.teleport_cluster_fqdn}/enterprise/saml-idp/metadata"

  request_timeout_ms = 10000

  retry {
    attempts     = 30
    min_delay_ms = 10000
  }

  depends_on = [
    helm_release.teleport_cluster
  ]
}

locals {
  # Extract the first (signing) X509Certificate from SAML IDP metadata XML,
  # then wrap it as PEM and base64-encode for Dex's caData field.
  saml_idp_cert_der_b64 = regex(
    "<X509Certificate[^>]*>([^<]+)</X509Certificate>",
    data.http.teleport_saml_idp_metadata.response_body
  )[0]
  saml_idp_cert_pem   = "-----BEGIN CERTIFICATE-----\n${local.saml_idp_cert_der_b64}\n-----END CERTIFICATE-----\n"
  saml_idp_ca_data    = base64encode(local.saml_idp_cert_pem)
  argocd_url          = "https://argocd.${local.teleport_cluster_fqdn}"
  argocd_dex_callback = "${local.argocd_url}/api/dex/callback"
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  wait    = false
  version = "9.4.10"

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
    }
    configs = {
      cm = {
        "url"                           = local.argocd_url
        "admin.enabled"                 = "false"
        "oidc.tls.insecure.skip.verify" = "true"
        # Dex SAML connector — Dex acts as the SAML SP, Teleport is the IDP.
        "dex.config" = <<-DEXCONFIG
          connectors:
          - type: saml
            id: teleport
            name: Teleport
            config:
              # Teleport's SAML SSO endpoint — where Dex sends AuthnRequests.
              ssoURL: "https://${local.teleport_cluster_fqdn}/enterprise/saml-idp/sso"
              # Base64-encoded PEM of Teleport's SAML signing cert (extracted from IDP
              # metadata above). Dex uses this to verify the signature on SAML responses.
              caData: "${local.saml_idp_ca_data}"
              # redirectURI and entityIssuer MUST match the ACS URL and entityID in the
              # SP registration (saml-sp.yaml ConfigMap below). Any mismatch causes
              # Teleport to reject the AuthnRequest with an "unknown service provider" error.
              redirectURI: "${local.argocd_dex_callback}"
              entityIssuer: "${local.argocd_dex_callback}"
              # Teleport sends attributes in OID format, not plain names:
              #   0.9.2342.19200300.100.1.1  = uid (username)
              #   1.3.6.1.4.1.5923.1.1.1.1  = eduPersonAffiliation (maps to Teleport roles)
              # Using plain names like "username" or "groups" here will not work.
              usernameAttr: "urn:oid:0.9.2342.19200300.100.1.1"
              emailAttr: "urn:oid:0.9.2342.19200300.100.1.1"
              groupsAttr: "urn:oid:1.3.6.1.4.1.5923.1.1.1.1"
              # transient = Teleport generates a fresh random NameID each session (no
              # persistent identifier is needed since group membership drives authz).
              nameIDPolicyFormat: transient
        DEXCONFIG
      }
      rbac = {
        "policy.default" = "role:readonly"
        # Maps Teleport's "access" role (sent as a group attribute) to ArgoCD's admin role.
        # Any Teleport user with the "access" role gets full ArgoCD admin access.
        "policy.csv" = "g, access, role:admin"
        "scopes"     = "[groups]"
      }
    }
  })]
}

# This ConfigMap is mounted into the Teleport auth pods at /etc/teleport-sp/saml-sp.yaml
# (see teleport.cluster.tf auth.extraVolumes). It defines the SAML SP metadata that tells
# Teleport about ArgoCD's Dex connector — the entityID, ACS URL, and NameID format.
#
# IMPORTANT: Mounting this file does NOT register the SP automatically. After the mount
# is in place, run from inside an auth pod:
#   tctl create -f /etc/teleport-sp/saml-sp.yaml
# The SP is then persisted in Teleport's backend (DynamoDB) and survives pod restarts,
# so this only needs to be done once (or again if the SP is ever deleted).
#
# Why not the Teleport operator? The operator (v18.7.3) does not have a reconciler for
# TeleportSAMLIdPServiceProviderV1 CRDs, so the ConfigMap+tctl approach is the only
# available option for IaC management of SAML SPs.
#
# The entityID here MUST match entityIssuer in the Dex connector config above.
resource "kubernetes_config_map" "argocd_saml_sp" {
  metadata {
    name      = "argocd-saml-sp"
    namespace = kubernetes_namespace_v1.teleport_cluster.metadata[0].name
  }
  data = {
    "saml-sp.yaml" = <<-EOF
kind: saml_idp_service_provider
version: v1
metadata:
  name: argocd
spec:
  entity_descriptor: |
    <?xml version="1.0" encoding="UTF-8"?>
    <md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
        entityID="${local.argocd_dex_callback}">
      <md:SPSSODescriptor AuthnRequestsSigned="false"
          WantAssertionsSigned="true"
          protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
        <md:NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:transient</md:NameIDFormat>
        <md:AssertionConsumerService
            Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
            Location="${local.argocd_dex_callback}"
            index="1" />
      </md:SPSSODescriptor>
    </md:EntityDescriptor>
EOF
  }
}
