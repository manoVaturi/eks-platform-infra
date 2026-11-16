# Architecture

## Layer dependencies

Layers are Terragrunt units. Values flow downwards through `dependency` blocks; every unit has mock outputs so `validate` and
`plan` work without live upstream state.

| Layer | Lifetime | Outputs consumed by |
| --- | --- | --- |
| `00-bootstrap` | permanent, local state | all layers (state bucket) |
| `10-network` | permanent; NAT gateway toggled per session | 30, 35, 40, 45 |
| `20-persistent` | permanent: ECR, KMS key, WAF web ACL, ACM certificate, Vault data volume, budget alarm | 30, 35, 40 |
| `30-cicd` | Jenkins instance stopped between sessions; ALB rules removed with `edge_enabled=false` | 32 |
| `32-ci-plan` | permanent IAM role for the plan stage | Jenkinsfile |
| `35-gitlab-data` | permanent data volume; ALB and DNS toggled | 45 |
| `40-eks` | destroyed after each session | gitops repo (role ARNs) |
| `45-gitlab-server` | destroyed after each session | none |

`edge_enabled` must be passed explicitly to layers 30 and 35 on every apply. Omitting it with the edge off silently removes the
listener rules, so `scripts/apply.sh` injects the flag and refuses ambiguous runs.

## Network

One VPC across two AZs with public, private and database subnets. The ALB and NAT gateway sit in the public subnets; every instance and the node group sit in private subnets. No
workload has a public IP. A single NAT gateway (one AZ) carries all egress. The ALB accepts traffic only from `allowed_cidrs`. The GitLab and Jenkins security groups accept ingress only from the ALB security group; their egress rules use `0.0.0.0/0` because all outbound traffic leaves through the NAT gateway.

## Identity and secrets

- Pod Identity roles: EBS CSI driver, AWS Load Balancer Controller, ExternalDNS.
- IRSA role `weatherapp-vault`: KMS auto-unseal for Vault.
- Jenkins instance role: ECR push only; the plan stage assumes the separate `weatherapp-ci-plan` role.
- Application credentials are written to Vault `kv/` and synced into Secrets by Vault Secrets Operator. No credential is committed.

## Evolution from V1

| | V1 | V2 (this repository) |
| --- | --- | --- |
| IaC | Terraform modules (`network`, `eks`, `access`, `ci`, `edge`) driven by one `cluster.sh` | Terragrunt layers with generated backend and providers |
| Edge | two ALBs, WAF, wildcard certificate, Ingress | WAF and certificate in a persistent layer, Gateway API on Istio ambient |
| Secrets | Kubernetes Secrets created by hand | Vault with KMS auto-unseal, Vault Secrets Operator |
| Policy | none | Kyverno policies (baseline Pod Security Standard, `disallow-latest-tag`), network policies, Falco |
| Observability | none | Alloy, Mimir (single process), Grafana with provisioned dashboards and Slack alerts |
| Scaling | fixed node | Spot node group, metrics-server, VPA in recommendation mode |
| Delivery | Argo CD, dev auto-sync and prod manual sync | Argo CD app-of-apps, AppProjects (platform, dev, prod), ApplicationSet per workload |
