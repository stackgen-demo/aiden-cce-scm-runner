#!/usr/bin/env bash
# attach-runner.sh — bind the Guild remote runner on sg_agent when attach was left false.
# Default terraform sets remote_runner_attach_to_agent=true on first apply (Offline is fine).
# Use this only if you applied with attach=false and want to bind later.
#
#   ./scripts/attach-runner.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
NS_FILE="${ROOT}/.helm-namespace"
ATTACH_TFVARS="${TF_DIR}/attach.auto.tfvars"

pick_tf() {
  if command -v tofu >/dev/null 2>&1; then
    echo tofu
  elif command -v terraform >/dev/null 2>&1; then
    echo terraform
  else
    echo ""
  fi
}

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }

tf="$(pick_tf)"
[[ -n "${tf}" ]] || die "tofu or terraform is required"
[[ -f "${TF_DIR}/terraform.tfstate" ]] || die "no terraform.tfstate; tofu apply first"

if [[ -z "${RUNNER_NAME:-}" ]]; then
  RUNNER_NAME="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_name 2>/dev/null || true)"
fi
RUNNER_NAME="${RUNNER_NAME:-cce-scm-runner}"

already="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_attach_to_agent 2>/dev/null || echo false)"
if [[ "${already}" == "true" ]]; then
  info "already attached (remote_runner_attach_to_agent=true). Nothing to do."
  exit 0
fi

printf 'remote_runner_attach_to_agent = true\n' > "${ATTACH_TFVARS}"
info "wrote ${ATTACH_TFVARS} (auto-loaded by tofu) so later applies keep the runner attached"

info "tofu apply remote_runners=[${RUNNER_NAME}]"
"${tf}" -chdir="${TF_DIR}" apply -input=false -auto-approve \
  -var="remote_runner_attach_to_agent=true"

attached="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_attach_to_agent)"
[[ "${attached}" == "true" ]] || die "apply finished but remote_runner_attach_to_agent is ${attached}"
info "OK: agent $("${tf}" -chdir="${TF_DIR}" output -raw agent_name) attached to ${RUNNER_NAME}"
