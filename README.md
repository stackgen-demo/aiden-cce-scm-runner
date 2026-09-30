# Aiden CCE SCM runner

Paste a GitLab URL in Guild chat. The agent runs `cce scm describe` on a remote runner and returns forge metadata YAML. No clone on the default path.

Public image: `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` (anonymous pull; multi-arch `linux/amd64` + `linux/arm64`).

This root does **not** create LLM providers, models, or vendor API keys. It also does **not** create the remote runner or attach it to the agent. Those steps are manual.

## Who does what

| Step | Who | How |
|---|---|---|
| 1. Create remote runner in Guild | SE / customer admin | Guild UI → Remote runners → Create (`cce-scm-runner`). Copy token + mothership URL. |
| 2. tofu apply | SE | Creates GitLab integration + vault, agent, skills, policy. Optionally binds vault secret on the existing runner. |
| 3. Helm in cluster | Customer platform | `./helm/install.sh` with env you hand them (token + mothership). Creates namespace if needed. |
| 4. Attach runner → agent | SE | Guild UI after Online. |
| 5. Chat demo | SE | Agent `cce-scm-analyst`. |

## What tofu creates

| Resource | Name (defaults) |
|---|---|
| GitLab integration | `cce-scm-gitlab` |
| Vault secret (SCM/gitlab) | optionally bound on runner as `typed_secret_refs.gitlab` |
| Agent | `cce-scm-analyst` (**no** runner attached) |
| Skills | `scm-describe`, `scm-analyze` |
| Policy | `cce-scm-no-write` |

**Not created by tofu:** `sg_remote_runner`, agent `remote_runners` attachment.

## What you must provide

### 1. Environment variables for tofu

Export in your shell. OpenTofu maps `TF_VAR_<name>` → variable `<name>`. **Do not** put these in `terraform.tfvars`. An empty `""` in tfvars overrides a set `TF_VAR_*`.

| Env name | Required | Value |
|---|---|---|
| `TF_VAR_stackgen_url` | Yes | Guild base URL, no trailing slash |
| `TF_VAR_stackgen_token` | Yes | Guild personal access token |
| `TF_VAR_gitlab_token` | Yes | GitLab PAT with `read_api` (or `api` / `read_user`) |
| `TF_VAR_stackgen_project_id` | If tenant needs org scope | Guild org / project UUID |
| `TF_VAR_gitlab_base_url` | No | Default `https://gitlab.com` |

```bash
export TF_VAR_stackgen_url="https://<your-guild-host>"
export TF_VAR_stackgen_token="<guild-pat>"
export TF_VAR_gitlab_token="<gitlab-pat>"
# export TF_VAR_stackgen_project_id="<org-uuid>"
```

**Do not set** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or any other LLM vendor key.

### 2. `terraform/terraform.tfvars` (non-secrets)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

| Variable | Example | Purpose |
|---|---|---|
| `remote_runner_name` | `"cce-scm-runner"` | Name you will create in Guild UI (skill tool prefix + optional secret bind) |
| `create_gitlab_integration` | `true` | Create GitLab integration + vault |
| `bind_gitlab_secret_to_runner` | `true` | Bind vault on that runner (runner must already exist) |
| `gitlab_integration_name` | `"cce-scm-gitlab"` | Integration name |
| `runner_docker_image` | `"ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"` | Image for Helm notes |

If `bind_gitlab_secret_to_runner=true`, create the remote runner in Guild **before** `tofu apply`. Otherwise set it `false` and bind the secret in Guild UI later.

### 3. Helm (platform — explicit env only)

`./helm/install.sh` **does not** read tofu state. Platform must set:

| Env name | Required | Value |
|---|---|---|
| `STACKGEN_RUNNER_TOKEN` | Yes | Registration token from Guild remote-runner create / detail |
| `MOTHERSHIP_URL` | Yes | Same as Guild URL (no trailing slash) |
| `RUNNER_IMAGE` | No | Default `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` |
| `NS` | No | Default `aiden-cce-runner` (script creates it) |
| `RUNNER_NAME` | No | Default `cce-scm-runner` (status wait label) |

No GitLab token in Helm values. No GHCR login for the public image.

## Prerequisites

- OpenTofu (or Terraform) ≥ 1.5, StackGen provider ≥ 0.1.25
- `kubectl` + Helm 3 on the cluster that will host the runner
- Cluster egress to Guild, `ghcr.io`, and GitLab
- Valid GitLab PAT (`read_api` or better)

## Quick start

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner

# --- A. Manual: Guild UI → create remote runner "cce-scm-runner" ---
# Copy registration token + mothership URL. Keep them off git / Slack long-lived.

export TF_VAR_stackgen_url="https://<your-guild-host>"
export TF_VAR_stackgen_token="<guild-pat>"
export TF_VAR_gitlab_token="<gitlab-pat>"

cd terraform
cp terraform.tfvars.example terraform.tfvars
tofu init && tofu apply
tofu output

# --- B. Hand platform (or run yourself) ---
export MOTHERSHIP_URL="$TF_VAR_stackgen_url"
export STACKGEN_RUNNER_TOKEN="<token-from-Guild-UI>"
export RUNNER_IMAGE="$(tofu output -raw runner_docker_image)"
cd ..
./helm/install.sh

# --- C. Manual: Guild UI → attach cce-scm-runner to agent cce-scm-analyst ---
# Wait ~60s for vault sync, then chat.
```

Paste block for platform (fill the two secrets):

```bash
export MOTHERSHIP_URL="https://<their-guild-host>"
export STACKGEN_RUNNER_TOKEN="<registration-token>"
# optional: export NS=aiden-cce-runner KUBE_CONTEXT=...
./helm/install.sh
```

## Verify

1. Guild → Integrations → `cce-scm-gitlab`
2. Guild → remote runners → `cce-scm-runner` Online; GitLab secret bound
3. Agent has the runner attached (UI)
4. Demo prompt below succeeds

## Demo prompt

> Describe https://gitlab.com/gitlab-org/cli as repository metadata. Prefer the forge/API path.

## Security

- Policy `cce-scm-no-write` blocks write actions on the runner
- GitLab PAT reaches the pod only via Guild vault → `typed_secret_refs.gitlab` sync
- Public image; no GHCR credentials
- Runner registration token stays in shell env for Helm only — never in tfvars or checked-in values

## Teardown

```bash
helm uninstall cce-runner -n "${NS:-aiden-cce-runner}"
kubectl delete namespace "${NS:-aiden-cce-runner}"
# optional: cd terraform && tofu destroy
# Delete the remote runner in Guild UI if you no longer need it.
```

## Rebuild the image (maintainers)

Release tarball CCE **v0.0.8 has no `scm describe`**. Bake from CCE git `main`:

```bash
FROM_MAIN=1 \
  CCE_REPO=/path/to/cce \
  IMAGE=ghcr.io/stackgen-demo/aiden-cce-scm-runner \
  TAG=scm-main \
  PLATFORMS=linux/amd64,linux/arm64 \
  ./scripts/build-and-push.sh
```

Confirm anonymous pull. Package visibility must stay **Public**. Multi-arch covers amd64 and arm64 nodes.
