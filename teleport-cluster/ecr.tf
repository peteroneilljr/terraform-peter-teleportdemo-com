data "aws_caller_identity" "current" {}

resource "aws_ecr_repository" "teleport_demo_nodes" {
  name                 = "teleport-demo-nodes"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "teleport_demo_nodes" {
  repository = aws_ecr_repository.teleport_demo_nodes.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 60 images (5 versions x 12 variants)"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 60
      }
      action = {
        type = "expire"
      }
    }]
  })
}

locals {
  node_images = {
    debian12   = { dockerfile = "node-apt.Dockerfile", base_image = "debian:12" }
    ubuntu2404 = { dockerfile = "node-apt.Dockerfile", base_image = "ubuntu:24.04" }
    ubuntu2204 = { dockerfile = "node-apt.Dockerfile", base_image = "ubuntu:22.04" }
    rocky9     = { dockerfile = "node-dnf.Dockerfile", base_image = "rockylinux:9" }
    rocky8     = { dockerfile = "node-dnf.Dockerfile", base_image = "rockylinux:8" }
    fedora43   = { dockerfile = "node-dnf.Dockerfile", base_image = "fedora:43" }
    al2023     = { dockerfile = "node-dnf.Dockerfile", base_image = "amazonlinux:2023" }
    alpine321  = { dockerfile = "node-apk.Dockerfile", base_image = null }
    opensuse16 = { dockerfile = "node-zypper.Dockerfile", base_image = "opensuse/leap:16.0" }
    archlinux  = { dockerfile = "node-pacman.Dockerfile", base_image = null }
    tetris     = { dockerfile = "node-tetris.Dockerfile", base_image = null }
    pacman     = { dockerfile = "node-pacman-game.Dockerfile", base_image = null }
  }

  ecr_url = aws_ecr_repository.teleport_demo_nodes.repository_url

  node_image_names = {
    for k, v in local.node_images : k => "${local.ecr_url}:${k}-v${var.teleport_version}"
  }
}

# Get ECR auth token for pushing images from Sparky
data "aws_ecr_authorization_token" "this" {}

# Sync docker build context to Sparky once, then build all images.
# The kreuzwerker/docker provider's buildx code path has a bug with SSH hosts
# (hardcoded http://docker.example.com default), so we shell out instead.
resource "terraform_data" "docker_context_sync" {
  triggers_replace = {
    hash = sha256(join(",", [for k, v in local.node_images : filesha256("${path.module}/../docker/${v.dockerfile}")]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      rsync -az --delete "${path.module}/../docker/" clairefox@sparky:/tmp/docker-build/
      echo "${data.aws_ecr_authorization_token.this.password}" | \
        ssh clairefox@sparky docker login --username AWS --password-stdin "${local.ecr_url}"
    EOT
  }
}

resource "terraform_data" "node_image" {
  for_each = local.node_images

  triggers_replace = {
    dockerfile_hash = filesha256("${path.module}/../docker/${each.value.dockerfile}")
    version         = var.teleport_version
  }

  depends_on = [terraform_data.docker_context_sync]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail

      IMAGE="${local.ecr_url}:${each.key}-v${var.teleport_version}"

      CACHE="${local.ecr_url}:cache-${each.key}"

      # Build with buildx (registry cache for faster rebuilds)
      ssh clairefox@sparky docker buildx build \
        --builder tf-amd64 \
        --platform linux/amd64 \
        --load \
        --cache-from type=registry,ref="$CACHE" \
        --cache-to type=registry,ref="$CACHE",mode=max \
        -f /tmp/docker-build/${each.value.dockerfile} \
        --build-arg TELEPORT_VERSION=${var.teleport_version} \
        ${each.value.base_image != null ? "--build-arg BASE_IMAGE=${each.value.base_image}" : ""} \
        -t "$IMAGE" \
        /tmp/docker-build/

      # Push to ECR
      ssh clairefox@sparky docker push "$IMAGE"
    EOT
  }
}
