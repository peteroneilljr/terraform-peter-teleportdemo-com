# ---------------------------------------------------------------------------- #
# Read-Only ClusterRole and ClusterRoleBinding
# ---------------------------------------------------------------------------- #
resource "kubernetes_cluster_role" "read_only" {
  metadata {
    name = "read-only"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "services", "configmaps", "endpoints", "persistentvolumeclaims", "events", "serviceaccounts", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "read_only" {
  metadata {
    name = "read-only"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.read_only.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "read-only"
    api_group = "rbac.authorization.k8s.io"
  }
}
