# Aiden CCE SCM runner

Paste a GitLab URL in Guild chat. The agent runs `cce scm describe` on a remote runner and returns forge metadata YAML. No clone for the default path.

Public image: `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` (anonymous pull; bake from CCE git `main` with `FROM_MAIN=1`).

This root does **not** create LLM providers, models, or vendor API keys. The agent is registered without `model_names`.

## Architecture

| Where | What |
|---|---|
| Your Guild (tofu) | `sg_remote_runner`, GitLab `sg_guild_integration`, vault secret bound on the runner (`typed_secret_refs.gitlab`), agent, skills, no-write policy |
| Your cluster (Helm) | `aiden-runner` pod with the CCE overlay image; outbound long-poll to Guild |
| gitlab.com (or self-managed) | REST API called by `cce scm describe` using `GITLAB_TOKEN` synced onto the runner from the GitLab integration vault secret |

The cluster needs egress to Guild, `ghcr.io`, and GitLab.

One `tofu apply` registers the remote runner **together with** the GitLab integration (secret attached to the runner), agent (attached by default), skills, and policy. The runner may still be Offline; Helm makes it Online so shell tools work.

## Credentials and environment

Copy `scripts/env.example` → `scripts/.env`, fill the placeholders, source it. Do not commit `.env`.

Terraform variables ↔ env (OpenTofu reads `TF_VAR_<name>`):

| Terraform var | Env (`scripts/.env`) | What you put |
|---|---|---|
| `stackgen_url` | `TF_VAR_stackgen_url` | Guild base URL, no trailing slash |
| `stackgen_token` | `TF_VAR_stackgen_token` | Guild personal access token |
| `gitlab_token` | `TF_VAR_gitlab_token` | GitLab PAT with `read_api` (needed even for public gitlab.com) |
| `gitlab_base_url` | `TF_VAR_gitlab_base_url` | Optional. Default `https://gitlab.com`. Self-managed origin when needed |
| `stackgen_project_id` | `TF_VAR_stackgen_project_id` | Optional. Org/project id if the tenant requires it |

Prefer env for secrets. Do not set secret keys to `""` in tfvars — that overrides env.

### After `tofu apply` (Helm)

| Variable | What you put |
|---|---|
| `STACKGEN_RUNNER_TOKEN` | `tofu -chdir=terraform output -raw remote_runner_token` |
| `MOTHERSHIP_URL` | Usually same as `TF_VAR_stackgen_url` |
| `RUNNER_IMAGE` | Leave default: `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` |

**Do not set:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or any other LLM vendor credential. No foundation apply. No `model_names`.

No GitLab token in the image or checked-in Helm values. No GitHub token to pull the public image.

## Prerequisites

- `tofu` (or Terraform) ≥ 1.5 and StackGen provider ≥ 0.1.25
- `kubectl` + Helm 3
- Egress from the cluster to Guild, `ghcr.io`, and GitLab
- A read-only GitLab PAT (`read_api`)

## Quick start

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner

cp scripts/env.example scripts/.env
# fill: TF_VAR_stackgen_url, TF_VAR_stackgen_token, TF_VAR_gitlab_token
# optional: TF_VAR_stackgen_project_id, TF_VAR_gitlab_base_url
set -a && source scripts/.env && set +a

cd terraform
cp terraform.tfvars.example terraform.tfvars   # non-secrets only; no tokens
tofu init && tofu apply
tofu output

export STACKGEN_RUNNER_TOKEN="$(tofu output -raw remote_runner_token)"
export MOTHERSHIP_URL="$(tofu output -raw remote_runner_mothership_url)"
cd ..
./helm/install.sh

# Wait until Guild shows the runner Online (~60s after vault sync), then chat.
# Only needed if you set remote_runner_attach_to_agent=false:
#   ./scripts/attach-runner.sh
```

## Verify

1. Guild UI → Integrations → `cce-scm-gitlab` exists.
2. Guild UI → remote runners → `cce-scm-runner` is **Online**, with GitLab secret sync.
3. Pod env has `GITLAB_TOKEN` set after vault sync (do not print the value).
4. Chat demo prompt below succeeds.

## Demo prompt

> Describe https://gitlab.com/gitlab-org/cli as repository metadata. Prefer the forge/API path.

## Security

- Policy `cce-scm-no-write` blocks forge/infra write commands on the runner.
- GitLab token reaches the pod only via Guild vault → runner secret sync (`typed_secret_refs.gitlab`).
- Public image pull needs no GHCR credentials.

## Teardown

```bash
helm uninstall cce-runner -n "${NS:-aiden-cce-runner}"
kubectl delete namespace "${NS:-aiden-cce-runner}"
# optional: cd terraform && tofu destroy
```

Helm teardown leaves the Guild `sg_remote_runner` / integration until you `tofu destroy`.

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

Then `docker logout ghcr.io` and `docker pull …:scm-main` to confirm anonymous pull. Package settings must stay **Public**.
