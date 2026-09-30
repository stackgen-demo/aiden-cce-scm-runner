# Aiden CCE SCM runner

Paste a GitLab URL in Guild chat. The agent runs `cce scm describe` on a remote runner and returns forge metadata YAML. No clone for the default path.

Public image: `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` (anonymous pull; bake from CCE git `main` with `FROM_MAIN=1`).

## Architecture

| Where | What |
|---|---|
| Your Guild (tofu) | `sg_remote_runner` registration + token, agent, skills, no-write policy, optional GitLab vault secret |
| Your cluster (Helm) | `aiden-runner` pod with the CCE overlay image; outbound long-poll to Guild |
| gitlab.com (or self-managed) | REST API called by `cce scm describe` using `GITLAB_TOKEN` synced onto the runner |

VPN may be required to reach your Guild mothership from the laptop and/or cluster. The cluster also needs egress to `ghcr.io` and GitLab.

One `tofu apply` registers the remote runner **together with** the agent (attached by default), skills, and policy. The runner may still be Offline; Helm makes it Online so shell tools work.

## Credentials and environment

Prefer env over secrets in git. Copy `scripts/env.example`.

```bash
# --- Guild / Aiden (required for tofu) ---
export STACKGEN_URL="https://<your-guild-host>"          # mothership; VPN may be required
export STACKGEN_TOKEN="<guild-personal-access-token>"  # create agents/runners/secrets
# export STACKGEN_PROJECT_ID="<org-or-project-id>"     # only if tenant requires it

# --- Existing Guild model name(s) — NOT an API key ---
# Copy from Guild UI (Models) or from another agent already working in this tenant.
export TF_VAR_model_names='["<existing-model-name>"]'

# --- GitLab API for scm describe (required even for public repos) ---
export GITLAB_TOKEN="<read-only PAT>"   # scopes: read_api (or equivalent)
# export GITLAB_BASE_URL="https://gitlab.com"   # set only for self-managed GitLab

# --- Helm install (after tofu; from outputs or explicit) ---
export MOTHERSHIP_URL="$STACKGEN_URL"
export STACKGEN_RUNNER_TOKEN="<from tofu output remote_runner_token>"
export RUNNER_IMAGE="ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"
# export KUBE_CONTEXT="..."
# export NS="aiden-cce-runner"
```

| Env var | Required | Used by | Purpose |
|---|---|---|---|
| `STACKGEN_URL` | Yes | tofu / Helm mothership | Guild base URL (no trailing slash) |
| `STACKGEN_TOKEN` | Yes | tofu | Guild PAT to create runner, agent, secrets |
| `STACKGEN_PROJECT_ID` | No | tofu | Org/project scope when required |
| `TF_VAR_model_names` | Yes | tofu → `sg_agent` | Names of models **already** in the tenant (JSON list). Not an LLM vendor API key. |
| `GITLAB_TOKEN` | Yes (before chat) | tofu → vault → runner env | GitLab API for `cce scm describe` |
| `GITLAB_BASE_URL` | No | tofu → vault → runner env | Self-managed GitLab origin; omit for gitlab.com |
| `STACKGEN_RUNNER_TOKEN` | Yes (Helm step) | `helm/install.sh` | From `tofu output remote_runner_token` |
| `MOTHERSHIP_URL` | Yes (Helm step) | `helm/install.sh` | Same as Guild URL unless output differs |
| `RUNNER_IMAGE` | No | Helm | Default `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main`; no GHCR login when public |
| `KUBE_CONTEXT` / `NS` | No | Helm | Cluster context and throwaway namespace |

**Not required:** `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or any other LLM provider credential. This root does not install LLM providers. If chat fails with “no model,” pick an existing model name from Guild and set `model_names`.

Also:

- Do not commit real tokens in `terraform/terraform.tfvars`.
- Do not put `GITLAB_TOKEN` in the image or checked-in Helm values.
- No GitHub token needed to pull the public runner image.
- Empty string in tfvars overrides env — omit secret keys instead of `""`.

## Prerequisites

- VPN to your Guild if the mothership is private
- `tofu` (or Terraform) ≥ 1.5 and StackGen provider ≥ 0.1.25
- `kubectl` + Helm 3
- Egress from the cluster to Guild, `ghcr.io`, and GitLab
- A read-only GitLab PAT (`read_api`)
- An existing Guild model name

## Quick start

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner
# export env vars from the table above (STACKGEN_*, TF_VAR_model_names, GITLAB_TOKEN)

cd terraform
cp terraform.tfvars.example terraform.tfvars
# fill stackgen_url; attach defaults true; prefer env for tokens and model_names
tofu init && tofu apply
tofu output

# Capture Helm inputs
export STACKGEN_RUNNER_TOKEN="$(tofu output -raw remote_runner_token)"
export MOTHERSHIP_URL="$(tofu output -raw remote_runner_mothership_url)"
cd ..
./helm/install.sh

# Wait until Guild shows the runner Online (~60s after GITLAB_TOKEN sync), then chat.
# Only needed if you set remote_runner_attach_to_agent=false:
#   ./scripts/attach-runner.sh
```

## Verify

1. Guild UI → remote runners → `cce-scm-runner` is **Online**.
2. Pod env has `GITLAB_TOKEN` set after vault sync (do not print the value).
3. Chat demo prompt below succeeds.

## Demo prompt

> Describe https://gitlab.com/gitlab-org/cli as repository metadata. Prefer the forge/API path.

## Security

- Policy `cce-scm-no-write` blocks forge/infra write commands on the runner.
- GitLab token reaches the pod only via Guild vault → runner secret sync.
- Public image pull needs no GHCR credentials.

## Teardown

```bash
helm uninstall cce-runner -n "${NS:-aiden-cce-runner}"
kubectl delete namespace "${NS:-aiden-cce-runner}"
# optional: cd terraform && tofu destroy
```

Helm teardown leaves the Guild `sg_remote_runner` row until you `tofu destroy`.

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
