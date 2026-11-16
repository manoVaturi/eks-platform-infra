# Known constraints and production hardening

| Constraint | Reason | Production approach |
| --- | --- | --- |
| Single NAT gateway and a single-node Spot group in one AZ | Cost control; the Vault data volume is zonal | One NAT gateway per AZ, on-demand system node group, Vault on integrated raft with three replicas across AZs |
| Dev and prod share the same Redis, PostgreSQL and MongoDB instances | Fewer pods on one node | Separate instances or at minimum separate databases and credentials per environment, with network policies between them |
| Kyverno policies run in `Audit` mode | Policy reports must be clean before enforcement | Switch `validationFailureAction` to `Enforce` per policy after remediating reports |
| Mimir and Grafana use disposable storage | Environment is rebuilt each session; dashboards and alerts are provisioned from Git | Object storage backend (S3) for Mimir, distributed deployment, Alertmanager |
| Jenkins can run Docker on the host, which is root-equivalent | Single-tenant CI host | Ephemeral build pods without the Docker socket, or rootless builders (Kaniko, BuildKit) |
| Node scaling is a fixed Spot group | Predictable cost | Karpenter with NodePools by workload class; the design guide is in `eks-platform-gitops/docs/karpenter.md` |
| Argo CD polls GitLab about every 3 minutes | No inbound webhook path from GitLab to the cluster | Webhook through the internal ALB |
