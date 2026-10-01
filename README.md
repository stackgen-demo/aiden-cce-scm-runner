# Aiden CCE SCM runner

Paste a GitLab URL in Guild chat. The agent runs `cce scm describe` on a remote runner (API only, no clone), maps forge metadata into **customer Backstage catalog YAML**, and returns it. Upload/publish is out of scope until the customer names a destination.

**Public image:** `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main`  
Anonymous pull. Multi-arch: `linux/amd64` + `linux/arm64`.

This root does **not** create LLM providers, models, or vendor API keys.  
This root does **not** create the remote runner or attach it to the agent. Those are manual Guild UI actions.

---

## Roles

| Role | Actions |
|---|---|
| **SE / Guild admin** | Create remote runner in Guild, run tofu, attach runner to agent, run chat demo |
| **Customer platform** | Run Helm in their cluster with the token + mothership URL you give them |

---

## Prerequisites

- Guild access (UI + PAT for tofu)
- OpenTofu (or Terraform) ≥ 1.5, StackGen provider ≥ 0.1.42 (`sg_skill`)
- Customer cluster: `kubectl` + Helm 3
- Egress from that cluster to Guild, `ghcr.io`, and GitLab
- GitLab PAT with `read_api` (or `api` / `read_user`)
- An existing Guild model name only if the agent UI requires one later (this root does not set `model_names` or LLM keys)

---

## End-to-end steps

Do these in order. Runner create (Step 1) can happen before or after tofu; tofu never binds vault secrets onto the runner.

### Step 1 — Create the remote runner (Guild UI, manual)

1. Open Guild → **Remote runners** → **Create**.
2. Name it exactly: `cce-scm-runner` (must match `remote_runner_name` in tfvars).
3. Save and **copy immediately**:
   - Registration **token**
   - **Mothership URL** (Guild base URL, no trailing slash)
4. Keep both off git and long-lived chat. You will hand them to platform for Helm.

Runner stays **Offline** until Helm runs. That is expected.

`tofu state rm` / editing tfvars does **not** delete a runner in Guild. Only Guild UI delete (or an old tofu destroy while the runner was still in state) removes it.

### Step 2 — Export tofu credentials (SE laptop)

```bash
export TF_VAR_stackgen_url="https://<your-guild-host>"   # same as mothership; no trailing slash
export TF_VAR_stackgen_token="<guild-pat>"
export TF_VAR_gitlab_token="<gitlab-pat>"                 # read_api or better
# export TF_VAR_stackgen_project_id="<org-uuid>"          # only if tenant requires it
# export TF_VAR_gitlab_base_url="https://gitlab.example.com"  # self-managed only
```

Do **not** put these in `terraform.tfvars`. Empty `""` in tfvars overrides a set `TF_VAR_*`.  
Do **not** set `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, or any LLM vendor key.

### Step 3 — tofu apply (GitLab integration + agent; no runner)

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner

cd terraform
cp terraform.tfvars.example terraform.tfvars
# Confirm remote_runner_name = "cce-scm-runner"
tofu init
tofu apply
tofu output
```

**What tofu creates**

| Resource | Default name | Notes |
|---|---|---|
| GitLab integration | `cce-scm-gitlab` | Vault secret included |
| Agent | `cce-scm-analyst` | **Not** attached to a runner yet. Thin domain persona. Skill bound via `skills = [...]`. |
| Skill | `scm-api-to-backstage` | Real catalog skill (`SKILL.md`) managed by `sg_skill`. Technical procedure lives here — not in the persona, not as a runbook. |
| Policy | `cce-scm-no-write` | |

**What tofu does not create:** remote runner, agent↔runner attachment.

Bind the GitLab vault secret onto the runner in Guild UI after the runner exists (tofu does not do this).

### Step 4 — Helm in the customer cluster (platform)

Hand platform this block. Fill the two secrets from Step 1.  
Requires: `kubectl`, Helm 3, cluster egress to Guild + `ghcr.io`.  
Does **not** need: tofu, Guild PAT, GitLab token, or GHCR login.

```bash
git clone https://github.com/stackgen-demo/aiden-cce-scm-runner.git
cd aiden-cce-scm-runner

export MOTHERSHIP_URL="https://<their-guild-host>"
export STACKGEN_RUNNER_TOKEN="<registration-token-from-Guild>"
# optional:
# export NS="aiden-cce-runner"
# export KUBE_CONTEXT="<context>"
# export RUNNER_NAME="cce-scm-runner"
# export RUNNER_IMAGE="ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"
# export HELM_TIMEOUT="15m"          # slow pulls
# export WAIT_ONLINE=1               # also watch pod logs for Online (default: off)

./helm/install.sh
```

**What the script does**

1. Checks `kubectl` + `helm` are installed  
2. Creates namespace (default `aiden-cce-runner`) if missing  
3. `helm upgrade --install` chart `aiden-runner` with the public CCE image, mothership URL, runner token, and `ALLOWED_CLIS` (includes `cce`)  
4. Restarts the deploy so the pod loads the token  
5. Prints pods; exits 0 when Helm succeeds  

Online confirmation is **Guild UI (SE)** by default. Platform does not need a Guild PAT. Set `WAIT_ONLINE=1` only if they want the script to also watch pod logs.

**If Helm fails**

- Image pull / timeout → raise `HELM_TIMEOUT` (image is ~500MB)  
- CrashLoop / `exec format error` → node arch vs image (use multi-arch `:scm-main`)  
- Never Online → wrong token, or no egress to Guild; check  
  `kubectl -n aiden-cce-runner logs -l app.kubernetes.io/name=aiden-runner`  

Use the token from the **current** Guild runner. A token from a deleted runner will never go Online.

### Step 5 — Attach runner to agent (Guild UI, manual)

1. Confirm Guild → Remote runners → `cce-scm-runner` is **Online**.
2. Guild → Agents → `cce-scm-analyst` → **attach** remote runner `cce-scm-runner`.
3. Wait ~60 seconds for vault sync (`GITLAB_TOKEN` into runner tool env). Do not print the token.

### Step 6 — Demo chat

Open agent **`cce-scm-analyst`** and send:

> Scan https://gitlab.com/gitlab-org/cli via SCM APIs and produce Backstage catalog YAML. Use the skill example template unless I paste a customer template. Do not clone. Do not upload.

Replace the companion template under `skills/scm-api-to-backstage/references/` (or paste YAML in chat) with the customer's real Backstage shape when they provide it.

### Skills vs runbooks

| | Skills (`SKILL.md`) | Runbook SOPs |
|---|---|---|
| Purpose | Technical how-to for agents (CLIs, mapping, stop conditions) | Policy-blessed incident playbooks |
| This repo | **`scm-api-to-backstage` only** | None |
| Load path | Agent `skills = [...]` + `load_skill` | `get_runbook` / workflow `runbook_refs` |

Do not put CLI choreography in the agent persona. Guild already owns tool routing prompts.

### Replacing a runner (rehearsal / recreate)

If an old `cce-scm-runner` already exists (including one previously created by tofu):

1. Guild UI → detach it from the agent if attached  
2. Guild UI → **delete** the remote runner (state rm does not delete it)  
3. If an old tofu state still tracks a runner/secrets resource from an earlier revision, `tofu state rm` those addresses  
4. Start again at Step 1 (new token) → Step 3 apply → Step 4 Helm with the **new** token → Step 5 attach  

---

## Reference

### Helm env vars

| Env | Required | Purpose |
|---|---|---|
| `STACKGEN_RUNNER_TOKEN` | Yes | Guild remote-runner registration token |
| `MOTHERSHIP_URL` | Yes | Guild base URL (trailing slash stripped) |
| `RUNNER_IMAGE` | No | Default `ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main` |
| `NS` | No | Default `aiden-cce-runner` |
| `KUBE_CONTEXT` | No | Current kubectl context if unset |
| `RUNNER_NAME` | No | Default `cce-scm-runner` (messages only) |
| `HELM_TIMEOUT` | No | Default `10m` |
| `WAIT_ONLINE` | No | Set `1` to watch pod logs for Online (default off) |

### tfvars knobs (non-secrets)

| Variable | Example | Purpose |
|---|---|---|
| `remote_runner_name` | `"cce-scm-runner"` | Must match Guild runner name (shell tool prefix) |
| `create_gitlab_integration` | `true` | Create GitLab integration + vault |
| `gitlab_integration_name` | `"cce-scm-gitlab"` | Integration name |
| `runner_docker_image` | `"ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"` | Documented Helm image |

### Verify checklist

1. Guild → Integrations → `cce-scm-gitlab` exists  
2. Guild → Remote runners → `cce-scm-runner` **Online**; bind GitLab vault secret in UI  
3. Agent `cce-scm-analyst` has that runner attached  
4. Demo prompt returns Backstage catalog YAML from API metadata (no clone)  

### Security

- Policy `cce-scm-no-write` blocks write actions on the runner  
- GitLab PAT reaches the pod only via Guild vault → runner secret bind (UI) → mothership sync  
- Public image; no GHCR pull secret  
- Runner registration token: shell env for Helm only — never tfvars or checked-in values  

### Teardown

```bash
# Cluster (platform)
helm uninstall cce-runner -n "${NS:-aiden-cce-runner}"
kubectl delete namespace "${NS:-aiden-cce-runner}"

# Guild (SE) — tofu does not delete the remote runner
cd terraform && tofu destroy    # integration, agent, policy, vault secret, sg_skill
# Then Guild UI → delete remote runner cce-scm-runner (detach from agent first if needed)
```

### Rebuild the image (maintainers)

Release CCE **v0.0.8 has no `scm describe`**. Bake from CCE git `main`:

```bash
FROM_MAIN=1 \
  CCE_REPO=/path/to/cce \
  IMAGE=ghcr.io/stackgen-demo/aiden-cce-scm-runner \
  TAG=scm-main \
  PLATFORMS=linux/amd64,linux/arm64 \
  ./scripts/build-and-push.sh
```

Package visibility must stay **Public**. Confirm anonymous `docker pull`.
