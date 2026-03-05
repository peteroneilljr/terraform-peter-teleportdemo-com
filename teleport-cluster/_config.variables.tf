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
  description = "Choose the CRD installation option, always, dynamic or never"
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
  default     = "teleport-"
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
