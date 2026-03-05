terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.94"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # teleport = {
    #   source  = "terraform.releases.teleport.dev/gravitational/teleport"
    #   version = "> 18.0"
    # }
  }

}

provider "tls" {}
provider "null" {}
provider "random" {}

provider "aws" {
  profile = var.aws_profile

  region = var.aws_region
  default_tags {
    tags = var.aws_tags
  }
}

provider "helm" {
  kubernetes = {
    config_path    = var.k8s_config_path
    config_context = var.k8s_config_context
  }
}
provider "kubernetes" {
  config_path    = var.k8s_config_path
  config_context = var.k8s_config_context
}
provider "kubectl" {
  config_path    = var.k8s_config_path
  config_context = var.k8s_config_context
}

resource "random_password" "postgres" {
  length  = 16
  special = false
}

resource "random_password" "postgres_superuser" {
  length  = 16
  special = false
}

resource "random_password" "mysql" {
  length  = 16
  special = false
}

resource "random_password" "mariadb" {
  length  = 16
  special = false
}

resource "random_password" "mariadb_root" {
  length  = 16
  special = false
}