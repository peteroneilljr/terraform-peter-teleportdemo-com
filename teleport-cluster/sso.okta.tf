resource "kubectl_manifest" "sso_okta" {
  yaml_body = yamlencode(
    {
      apiVersion = "resources.teleport.dev/v2"
      kind       = "TeleportSAMLConnector"

      metadata = {
        name      = "okta"
        namespace = helm_release.teleport_cluster.namespace
      }

      spec = {
        acs                 = "https://${local.teleport_cluster_fqdn}:443/v1/webapi/saml/acs/okta"
        allow_idp_initiated = true
        attributes_to_roles = [
          {
            name  = "groups"
            value = "teleport-admin"
            roles = [
              "editor",
              "access",
              "reviewer",
              "${var.resource_prefix}session-moderate",
              "${var.resource_prefix}access-list-admin",
              "${var.resource_prefix}aws-admin",
            ]
          }
        ]
        audience                = "https://${local.teleport_cluster_fqdn}:443/v1/webapi/saml/acs/okta"
        display                 = "Okta"
        entity_descriptor_url   = var.okta_entity_descriptor_url
        service_provider_issuer = "https://${local.teleport_cluster_fqdn}:443/v1/webapi/saml/acs/okta"
      }
    }
  )
}