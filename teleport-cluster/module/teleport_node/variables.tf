variable "namespace" {
  type        = string
  description = "Kubernetes namespace for demo nodes"
}

variable "configmap_name" {
  type        = string
  description = "Name of the ConfigMap containing teleport.yaml"
}

variable "service_account_name" {
  type        = string
  description = "Name of the Kubernetes ServiceAccount for demo nodes"
}

variable "nodes" {
  type = map(object({
    name             = string
    image            = string
    teleport_labels  = optional(map(string), {})
    replicas         = optional(number, 1)
    wait_for_rollout = optional(bool, false)
  }))
  default = {}
}
