# Teleport Enterprise Demo Cluster

Self-hosted Teleport Enterprise cluster on AWS EKS, managed entirely with Terraform. Used for demos, testing, and exploring Teleport features at `peter.teleportdemo.com`.

## What's Deployed

**Teleport cluster** — HA deployment with DynamoDB backend, S3 session storage, and Let's Encrypt TLS via the `teleport-cluster` Helm chart.

**SSH nodes** (11) — containerized Linux distros running the Teleport agent, installed at container startup from upstream distro images:
- Rocky 9, Rocky 8, Fedora 43, AL2023, Ubuntu 24.04, Ubuntu 22.04, Debian 12, openSUSE Leap 16, Arch Linux
- Pac-Man and Tetris (game containers with `access=restricted` label, launched via SSH)

**Databases** (4) — all registered with Teleport for auto-provisioned access:
- PostgreSQL, MySQL, MariaDB (Bitnami Helm charts with seed data)
- MongoDB Atlas (cloud-hosted)

**Apps** (8) — registered with Teleport app access:
- Grafana, ArgoCD, AWS Console, AWS Bedrock, Coder, Swagger UI, Elasticsearch, Kibana

**Monitoring** — Prometheus (metrics collection, 7-day retention) with a Grafana dashboard (Teleport Overview), plus Elasticsearch and Kibana for log analytics.

**Access Graph** — identity security visualization deployed in its own namespace (`psh-teleport-access-graph`) with a dedicated PostgreSQL instance.

**MCP server** — a custom MCP (Model Context Protocol) server that exposes Teleport admin operations as tools for AI agents. See [teleport-cluster/MCP.md](teleport-cluster/MCP.md).

**Kubernetes access** — the EKS cluster is registered with Teleport. A read-only `ClusterRole` is bound to the `read-only` group for demo use.

**SSO providers** — GitHub, Google SAML, Okta SAML, Entra ID

**RBAC** — read-only roles, access request/approval workflows, session observation and moderation

## Prerequisites

- AWS account with an EKS cluster and Route53-hosted domain
- AWS CLI profile configured
- Teleport Enterprise license
- SSO provider credentials (GitHub OAuth app, Google/Okta/Entra SAML metadata)
- MongoDB Atlas project and API credentials
- Terraform >= 1.0

## Project Structure

```
teleport-cluster/               # All Terraform configuration
  _config.*.tf                  # Providers, variables, outputs, data sources
  teleport.cluster.tf           # Teleport cluster Helm release + k8s role
  teleport.agent.tf             # Kube agent (app + db proxy)
  teleport.backend*.tf          # DynamoDB/S3 backend + IAM
  teleport.dns.tf               # Route53 DNS
  teleport.crds.tf              # Teleport operator CRDs (teleport-iac namespace)
  teleport.apps.tf              # Teleport app registrations (8 apps)
  teleport.databases.tf         # Teleport database registrations
  teleport.access-graph.tf      # Access Graph + dedicated PostgreSQL
  resource.nodes.tf             # SSH node containers (11 nodes)
  resource.postgres.tf          # PostgreSQL (Bitnami via demo_database module)
  resource.mysql.tf             # MySQL (Bitnami via demo_database module)
  resource.mariadb.tf           # MariaDB (Bitnami via demo_database module)
  resource.mongodb-atlas.tf     # MongoDB Atlas
  resource.grafana.tf           # Grafana Helm release
  resource.grafana-dashboards.tf # Grafana dashboard ConfigMaps
  resource.prometheus.tf        # Prometheus Helm release
  resource.elasticsearch.tf     # Elasticsearch + Kibana
  resource.argocd.tf            # ArgoCD Helm release + SAML config
  resource.coder.tf             # Coder Helm release + templates
  resource.swagger-ui.tf        # Swagger UI deployment
  resource.k8s.tf               # Read-only ClusterRole + binding
  resource.aws-iam.tf           # IAM roles (IRSA, AWS console access)
  teleport.mcp-bot.tf           # MCP server deployment + bot identities
  files/teleport-mcp-server.py  # Python MCP server script (mounted as ConfigMap)
  resource.access-lists.tf      # Teleport access lists
  resource.access-requests.tf   # Teleport access request roles
  roles.*.tf                    # Teleport RBAC roles (CRDs)
  sso.*.tf                      # SSO connector configs
  locals.seed_data.tf           # Database seed data
  coder-templates/              # Coder workspace templates
    kubernetes/main.tf          #   Kubernetes workspace
    task/main.tf                #   Task workspace
  module/
    demo_database/              # Reusable module for Bitnami DB charts + TLS
    db_tls/                     # TLS cert generation for database mTLS
docs/                           # Setup guides
  coder-oidc-setup.md           # Coder OIDC configuration guide
```

File naming follows a `prefix.name.tf` convention where the prefix groups related resources.

## Namespaces

| Namespace | Purpose |
|---|---|
| `psh-cluster` | Teleport auth/proxy, kube agent, and databases (PostgreSQL, MySQL, MariaDB) |
| `psh-nodes` | SSH node containers |
| `psh-apps` | Grafana, Prometheus, Swagger UI |
| `psh-argocd` | ArgoCD |
| `psh-coder` | Coder |
| `psh-elasticsearch` | Elasticsearch + Kibana |
| `psh-teleport-access-graph` | Access Graph + dedicated PostgreSQL |
| `psh-teleport-mcp` | MCP server + tbot sidecar |
| `teleport-iac` | Teleport operator CRDs |

## Helm Charts

- `teleport-cluster` — Teleport auth/proxy (psh-cluster)
- `teleport-kube-agent` — app + database proxy agent (psh-cluster)
- `teleport-operator` — CRD definitions only, operator disabled (teleport-iac)
- `teleport-access-graph` — Access Graph (psh-teleport-access-graph)
- `postgresql` — Bitnami PostgreSQL (psh-cluster)
- `mysql` — Bitnami MySQL (psh-cluster)
- `mariadb` — Bitnami MariaDB (psh-cluster)
- `tag-postgresql` — PostgreSQL for Access Graph (psh-teleport-access-graph)
- `grafana` — Grafana dashboards (psh-apps)
- `prometheus` — Prometheus metrics (psh-apps)
- `elasticsearch` — Elastic Elasticsearch (psh-elasticsearch)
- `argocd` — ArgoCD (psh-argocd)
- `coder` — Coder workspaces (psh-coder)

## Usage

```bash
cd teleport-cluster
terraform init
terraform plan -var-file=your.tfvars
terraform apply -var-file=your.tfvars
```

SSH nodes use upstream distro images (e.g., `debian:12`, `rockylinux:9`) and install Teleport at container startup by downloading the tarball. No pre-built images or container registry is needed.

## License

See [LICENSE](LICENSE).
