# Terraform with Terragrunt

The layers (`10-network` … `45-gitlab-server`) are run with Terragrunt, a thin wrapper around Terraform.
The `.tf` code and the state files are the same as before. Terragrunt only supplies the wiring:
the backend, the provider, the versions and the values one layer reads from another.

> **Migration status: done** for every layer except `00-bootstrap`.
> Each migrated layer was checked against a baseline taken from the original code: same `plan`, same `state list`.

## Layout

```text
terraform/
├── root.hcl                 # shared: state bucket, state key per layer, generated files
├── _shared/
│   ├── providers.tf.tpl     # becomes providers.tf in every layer (LAYER_NAME -> folder name)
│   ├── versions.tf.tpl      # becomes versions.tf in every layer (terraform + aws provider)
│   └── versions-http.tf.tpl # same plus the http provider (30-cicd)
├── 00-bootstrap/            # NOT migrated: creates the state bucket, local state
├── 10-network/   terragrunt.hcl + *.tf
├── 20-persistent/ …
└── 45-gitlab-server/ …
```

What each layer folder contains now:

| File | Where it comes from |
| --- | --- |
| `main.tf`, `variables.tf`, `outputs.tf`, … | your code (unchanged apart from the dependency variables below) |
| `terragrunt.hcl` | includes `root.hcl`, declares `dependency` blocks and `inputs` |
| `terraform.tfvars` | yours, git-ignored (holds `allowed_cidrs`). Stays where it is, `up.sh` edits it |
| `backend.tf`, `providers.tf`, `versions.tf` | **generated** by Terragrunt into `.terragrunt-cache/`, not in the folder |

`terraform_remote_state` is gone. A layer that needs another layer's output has a `variable` for it, and its
`terragrunt.hcl` fills it from a `dependency` block. Optional outputs (the ALB while the edge is off) use
`try(dependency.cicd.outputs.x, null)`, like the old `try()` on the remote state.

## Day to day

| Task | Command |
| --- | --- |
| Plan one layer | `cd 40-eks && terragrunt plan` |
| Apply one layer (with a review step) | `scripts/apply.sh 40-eks` |
| Plan everything, in dependency order | `cd terraform && terragrunt run --all plan` |
| Destroy one layer | `cd 40-eks && terragrunt destroy` |
| Outputs / state of a layer | `terragrunt output`, `terragrunt state list` |
| Format `.hcl` files | `terragrunt hcl fmt` |
| Checks like CI (fmt, validate, lint, scan) | `scripts/check.sh all` |

Extra Terraform flags pass straight through: `terragrunt apply -var edge_enabled=true`.

`terragrunt run --all plan` reports an error for `35-gitlab-data` (and skips `45-gitlab-server`) while the project
is down. That is the same error the layer gave before the migration: it needs the shared ALB from `30-cicd`,
which only exists after `up.sh` switched the edge on.

## Things to know

- **State keys are the original ones.** They are listed in `root.hcl` (`state_keys`). Never change one: the layer
  would point at an empty state and plan to create everything again.
- **`.terragrunt-cache/`** is where Terragrunt runs your code. It is git-ignored. Do not edit files in it.
  Delete it (`find . -name .terragrunt-cache -prune -exec rm -rf {} +`) if something looks stale.
- **A dependency must have outputs.** Terragrunt reads them from the other layer's state. `mock_outputs` are used
  only for `init`, `validate` and `plan`, and only when the other layer has no outputs yet. Never for `apply`.
- **Terragrunt runs `init` itself** on the first command and when the generated files change.
- **Orphaned state lock** (a crashed run): `terragrunt force-unlock <ID>` in the layer, only after you are sure no
  run is still going (`ps`, `docker ps`).
- **Versions:** Terraform 1.15.9 and Terragrunt 1.2.1 are in `.tool-versions`. CI uses the image
  `alpine/terragrunt:1.15.9` (Terraform 1.15.9, Terragrunt 1.1.3).

## Scripts and CI

| File | What changed |
| --- | --- |
| `scripts/lib.sh` | new helpers `tg LAYER ARGS…` (terragrunt in a layer) and `layer_ready LAYER` |
| `scripts/up.sh`, `scripts/down.sh` | `terragrunt apply/destroy` instead of `terraform`; they need `terragrunt` installed |
| `scripts/apply.sh` | plan, review, apply with Terragrunt; `--log-disable` keeps the plan text clean for its greps |
| `scripts/tf.sh` | `plan` runs in `TG_IMAGE`. fmt/validate/lint/scan run on a temporary copy of the layer **plus** the generated `providers.tf` and `versions.tf` from `_shared/` (`*.tf.tpl`, templates, so editors do not lint them as code), so they judge the same code as a real run |
| `scripts/tf-layers.sh` | dependencies are read from `dependency` blocks in `terragrunt.hcl`; a change in `_shared/` or `root.hcl` checks every layer |
| `scripts/check.sh` | ignores `.terragrunt-cache` in its clean copy |
| `Jenkinsfile` | new `TG_IMAGE` |
| `.gitignore`, `.tool-versions` | `.terragrunt-cache/`, `terragrunt 1.2.1` |

The runbook uses the Terragrunt commands. `terraform/backend.tfbackend` was removed: the backend is generated
from `root.hcl`.

## How a layer was migrated (and how to add a new one)

1. **Baseline first**, from the original code: `terraform plan` and `terraform state list`, saved to files.
   A deployed layer says "No changes". A layer that is torn down plans its creates. That is fine: the goal is that
   the plan after the migration is identical.
2. **Add the layer to `root.hcl`:** its original key in `state_keys` (and in `versions_files` if it needs another provider).
3. **Add `terragrunt.hcl`:**

   ```hcl
   include "root" {
     path = find_in_parent_folders("root.hcl")
   }

   inputs = {
     region = "eu-west-1"
   }
   ```

4. **Delete** `providers.tf`, `versions.tf` and the `backend` block from the layer. Leave `terraform.tfvars`.
5. **If the layer reads other layers:** add a `dependency` block for each, with `mock_outputs` (init, validate, plan only),
   declare a `variable` for every value, put `var.x` where `data.terraform_remote_state.y.outputs.x` was, and delete the
   `data "terraform_remote_state"` blocks:

   ```hcl
   dependency "network" {
     config_path = "../10-network"
     mock_outputs = { vpc_id = "vpc-00000000" }
     mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
   }

   inputs = {
     region = "eu-west-1"
     vpc_id = dependency.network.outputs.vpc_id
   }
   ```

6. **Verify:** `terragrunt init -reconfigure`, then `terragrunt plan` and `terragrunt state list`.
   Both must equal the baseline. Do not apply until they do.

## Why `00-bootstrap` is not migrated

It creates the S3 bucket that holds every other state, and keeps its own state in a local file. Terragrunt's
`remote_state` would need that bucket to exist first. It is applied once and never again (`apply.sh` refuses it).

## Rollback

Nothing in the migration changes state or infrastructure. To go back for a layer, restore `providers.tf`,
`versions.tf` and the `terraform_remote_state` blocks from Git (`git checkout <commit> -- terraform/<layer>`),
delete its `terragrunt.hcl`, restore `terraform/backend.tfbackend` the same way, and run
`terraform init -reconfigure -backend-config=../backend.tfbackend`.
