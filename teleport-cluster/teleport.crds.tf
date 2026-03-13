# CRD-only Helm release for the Teleport operator.
# Installs all operator CRDs without deploying the operator itself.
# The main teleport-cluster chart (teleport.cluster.tf) depends on this
# so the operator pod finds its CRDs on startup.
#
# Imported from the pre-existing teleport-operator release in teleport-iac.

resource "helm_release" "teleport_crds" {
  name       = "teleport-operator"
  namespace  = "teleport-iac"
  repository = "https://charts.releases.teleport.dev"
  chart      = "teleport-operator"
  version    = var.teleport_version

  values = [<<EOF
    enabled: false
    installCRDs: "always"
    EOF
  ]
}
