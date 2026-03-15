# ---------------------------------------------------------------------------- #
# AWS Vars
# ---------------------------------------------------------------------------- #
variable "aws_eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}
variable "aws_domain_name" {
  description = "domain name to query for DNS"
  type        = string
}
variable "aws_region" {
  description = "region to create resources in"
  type        = string
}
variable "aws_profile" {
  description = "Profile to use for AWS Profile"
  default     = "default"
}
variable "aws_tags" {
  description = "tags to apply to all resources"
  type        = map(string)
  default     = {}
}
# ---------------------------------------------------------------------------- #
# Teleport
# ---------------------------------------------------------------------------- #
variable "teleport_subdomain" {
  description = "subdomain to create in the provided aws domain"
  type        = string
}
variable "teleport_license_filepath" {
  type        = string
  description = "Path to the Teleport license file"
}
variable "teleport_install_CRDs" {
  type        = string
  default     = "dynamic"
  description = "CRD install mode for the main teleport-cluster chart operator (CRDs are primarily managed by helm_release.teleport_crds)"
}

variable "teleport_version" {
  description = "full version of teleport (e.g. 17.4.0)"
  type        = string
  default     = "17.4.7"
}

# ---------------------------------------------------------------------------- #
# Cluster Name
# ---------------------------------------------------------------------------- #
locals {
  teleport_cluster_fqdn = "${var.teleport_subdomain}.${var.aws_domain_name}"
  teleport_cluster_name = "${var.resource_prefix}${replace(local.teleport_cluster_fqdn, ".", "-")}"
}
# ---------------------------------------------------------------------------- #
# Teleport Vars
# ---------------------------------------------------------------------------- #
variable "resource_prefix" {
  description = "Prefix to use for all resources"
  type        = string
  default     = ""
}
# ---------------------------------------------------------------------------- #
# Github Connector
# ---------------------------------------------------------------------------- #
variable "github_client_secret" {
  description = "client secret for github"
  type        = string
}
variable "github_client_id" {
  description = "client id for github"
  type        = string
}
variable "github_org" {
  description = "github organization to use for teleport"
  type        = string
}
# ---------------------------------------------------------------------------- #
# Coder Github OAuth
# ---------------------------------------------------------------------------- #
variable "coder_github_client_id" {
  description = "GitHub OAuth App client ID for Coder"
  type        = string
}
variable "coder_github_client_secret" {
  description = "GitHub OAuth App client secret for Coder"
  type        = string
  sensitive   = true
}
variable "coder_session_token" {
  description = "Coder API session token for template management"
  type        = string
  sensitive   = true
}
# ---------------------------------------------------------------------------- #
# Okta Vars
# ---------------------------------------------------------------------------- #
variable "okta_entity_descriptor_url" {
  type        = string
  description = "Okta Entity Descriptor URL"
}
# ---------------------------------------------------------------------------- #
# k8s Vars
# ---------------------------------------------------------------------------- #
variable "k8s_config_path" {
  type        = string
  description = "Path to the Kubernetes config to use for authentication"
}
variable "k8s_config_context" {
  type        = string
  default     = null
  description = "Context in the Kubeconfig to use"
}
# ---------------------------------------------------------------------------- #
# Google SAML Vars
# ---------------------------------------------------------------------------- #
variable "google_acs" {
  type        = string
  description = "Google ACS URL"
}
variable "google_entity_descriptor" {
  type        = string
  description = "Google Entity Descriptor URL"
}
# ---------------------------------------------------------------------------- #
# MongoDB Atlas Vars
# ---------------------------------------------------------------------------- #
variable "mongodbatlas_project_id" {
  type        = string
  description = "MongoDB Atlas Project ID"
}
variable "mongodbatlas_client_id" {
  type        = string
  description = "MongoDB Atlas API public key"
}
variable "mongodbatlas_client_secret" {
  type        = string
  sensitive   = true
  description = "MongoDB Atlas API private key"
}
