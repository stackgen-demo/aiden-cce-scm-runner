# Aiden CCE SCM runner

Paste a GitLab URL in Guild chat. The agent runs `cce scm describe` on a remote runner and returns forge metadata YAML. No clone on the default path.

Public image: `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` (anonymous pull).

This root does **not** create LLM providers, models, or vendor API keys. The agent has no `model_names`.

## What tofu creates

| Resource | Name (defaults) |
|---|---|
| Remote runner | `cce-scm-runner` |
| GitLab integration | `cce-scm-gitlab` |
| Vault secret (SCM/gitlab) | bound on the runner as `typed_secret_refs.gitlab` |
| Agent | `cce-scm-analyst` (runner attached by default) |
| Skills | `scm-describe`, `scm-analyze` |
| Policy | `cce-scm-no-write` |

Helm (`./helm/install.sh`) then runs aiden-runner Online so shell tools work. Vault sync injects `GITLAB_TOKEN` into the pod (~60s after Online).

## What you must provide

### 1. Environment variables (secrets and Guild URL)

Export in your shell (or CI secrets). OpenTofu maps `TF_VAR_<name>` → variable `<name>`. **Do not** put these in `terraform.tfvars` or any `.env` file in the repo. An empty `""` in tfvars overrides a set `TF_VAR_*`.

| Env name | Required | Value |
|---|---|---|
| `TF_VAR_stackgen_url` | Yes | Guild base URL, no trailing slash (e.g. `https://ai.dev.stackgen.com`) |
| `TF_VAR_stackgen_token` | Yes | Guild personal access token |
| `TF_VAR_gitlab_token` | Yes | GitLab PAT with `read_api` (or `api` / `read_user`). Vault stores it as metadata key `token` |
| `TF_VAR_stackgen_project_id` | If tenant needs org scope | Guild org / project UUID |
| `TF_VAR_gitlab_base_url` | No | Default `https://gitlab.com`. Set for self-managed GitLab |

Example:

```bash
export TF_VAR_stackgen_url="https://ai.dev.stackgen.com"
export TF_VAR_stackgen_token="<guild-pat>"
export TF_VAR_gitlab_token="<gitlab-pat>"
export TF_VAR_stackgen_project_id="<org-uuid>"   # omit if not required
# export TF_VAR_gitlab_base_url="https://gitlab.example.com"  # self-managed only
```

You can keep these in `~/.zshrc` the same way. `source ~/.zshrc` before `tofu apply`.

**Do not set** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or any other LLM vendor key for this stack.

### 2. `terraform/terraform.tfvars` (non-secrets only)

Copy the example and edit names/flags as needed:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Current example knobs:

| Variable | Example | Purpose |
|---|---|---|
| `create_remote_runner` | `true` | Register `sg_remote_runner` |
| `remote_runner_name` | `"cce-scm-runner"` | Runner name in Guild |
| `remote_runner_attach_to_agent` | `true` | Bind runner on the agent in the same apply |
| `create_gitlab_integration` | `true` | Create GitLab integration + bind vault secret on the runner |
| `gitlab_integration_name` | `"cce-scm-gitlab"` | Integration name in Guild |
| `runner_docker_image` | `"ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"` | Image Helm should pull |

Optional non-secret you may add to tfvars (or use `TF_VAR_stackgen_project_id` instead):

```hcl
stackgen_project_id = "<org-uuid>"
```

Omit that key entirely if you do not need project scope. Do not set it to `""`.

### 3. After apply (Helm)

| Env name | Required | Value |
|---|---|---|
| `STACKGEN_RUNNER_TOKEN` | Yes | `tofu -chdir=terraform output -raw remote_runner_token` |
| `MOTHERSHIP_URL` | Yes | `tofu -chdir=terraform output -raw remote_runner_mothership_url` (same as Guild URL) |
| `RUNNER_IMAGE` | No | Defaults to `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` |
| `NS` | No | Defaults to `aiden-cce-runner` |

No GitLab token in Helm values. No GHCR login for the public image.

## Prerequisites

- OpenTofu (or Terraform) ≥ 1.5, StackGen provider ≥ 0.1.25
- `kubectl` + Helm 3
- Cluster egress to Guild, `ghcr.io`, and GitLab
- Valid GitLab PAT (`read_api` or better; not expired)

## Quick start

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner

export TF_VAR_stackgen_url="https://<your-guild-host>"
export TF_VAR_stackgen_token="<guild-pat>"
export TF_VAR_gitlab_token="<gitlab-pat>"
# export TF_VAR_stackgen_project_id="<org-uuid>"

cd terraform
cp terraform.tfvars.example terraform.tfvars
tofu init && tofu apply
tofu output

export STACKGEN_RUNNER_TOKEN="$(tofu output -raw remote_runner_token)"
export MOTHERSHIP_URL="$(tofu output -raw remote_runner_mothership_url)"
cd ..
./helm/install.sh
```

Wait until Guild shows `cce-scm-runner` **Online**, then ~60s for vault sync. Chat with agent `cce-scm-analyst`.

If you set `remote_runner_attach_to_agent = false`, run `./scripts/attach-runner.sh` after Online.

## Verify

1. Guild → Integrations → `cce-scm-gitlab`
2. Guild → remote runners → `cce-scm-runner` Online, GitLab secret bound
3. Pod has `GITLAB_TOKEN` after sync (do not print it)
4. Demo prompt below succeeds

## Demo prompt

> Describe https://gitlab.com/gitlab-org/cli as repository metadata. Prefer the forge/API path.

## Security

- Policy `cce-scm-no-write` blocks write actions on the runner
- GitLab PAT reaches the pod only via Guild vault → `typed_secret_refs.gitlab` sync
- Public image; no GHCR credentials
- Secrets stay in shell / CI only, never in tfvars or `.env` in the tree

## Teardown

```bash
helm uninstall cce-runner -n "${NS:-aiden-cce-runner}"
kubectl delete namespace "${NS:-aiden-cce-runner}"
# optional: cd terraform && tofu destroy
```

Helm teardown leaves Guild resources until `tofu destroy`.

## Rebuild the image (maintainers)

Release tarball CCE **v0.0.8 has no `scm describe`**. Bake from CCE git `main`:

```bash
FROM_MAIN=1 \
  CCE_REPO=/path/to/cce \
  IMAGE=ghcr.io/stackgen-demo/aiden-cce-scm-runner \
  TAG=scm-main \
  PLATFORMS=linux/amd64 \
  ./scripts/build-and-push.sh
```

Confirm anonymous pull. Package visibility must stay **Public**.
