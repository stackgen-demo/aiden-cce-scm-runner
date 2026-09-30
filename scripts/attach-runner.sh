#!/usr/bin/env bash
# attach-runner.sh — reminder / checklist only.
#
# This root does NOT attach the remote runner via tofu. Create the runner in
# Guild UI, bring it Online with Helm, then attach it to the agent in Guild UI.
#
#   ./scripts/attach-runner.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"

pick_tf() {
  if command -v tofu >/dev/null 2>&1; then
    echo tofu
  elif command -v terraform >/dev/null 2>&1; then
    echo terraform
  else
    echo ""
  fi
}

info() { echo "==> $*" >&2; }

AGENT="cce-scm-analyst"
RUNNER="${RUNNER_NAME:-cce-scm-runner}"

tf="$(pick_tf)"
if [[ -n "${tf}" && -f "${TF_DIR}/terraform.tfstate" ]]; then
  AGENT="$("${tf}" -chdir="${TF_DIR}" output -raw agent_name 2>/dev/null || echo "${AGENT}")"
  RUNNER="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_name 2>/dev/null || echo "${RUNNER}")"
fi

cat <<EOF
Attach is manual (not managed by tofu).

  1. Guild → Remote runners → confirm "${RUNNER}" is Online
  2. Guild → Agents → "${AGENT}" → attach remote runner "${RUNNER}"
  3. Wait ~60s for vault / GITLAB_TOKEN sync
  4. Chat the demo prompt (see README)

Do not set remote_runners on sg_agent via this root.
EOF
info "checklist printed; no tofu apply performed."
