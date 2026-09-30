#!/usr/bin/env bash
# attach-runner.sh — bind the Guild remote runner on sg_agent after it is Online.
# Keep remote_runner_attach_to_agent false on first apply; run this after helm/install.sh.
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

resolve_context() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    echo "${KUBE_CONTEXT}"
    return
  fi
  kubectl config current-context
}

guild_runner_status() {
  local token="${TF_VAR_stackgen_token:-${STACKGEN_TOKEN:-}}"
  local base="${TF_VAR_stackgen_url:-${STACKGEN_URL:-}}"
  local name="${RUNNER_NAME:-cce-scm-runner}"
  [[ -n "${token}" && -n "${base}" ]] || return 1
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json" \
    "${base%/}/guild/api/v1/remote-runners/${name}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status") or "")'
}

pod_says_online() {
  local ctx="$1" ns="$2"
  kubectl --context "${ctx}" -n "${ns}" logs -l app.kubernetes.io/name=aiden-runner --tail=80 2>/dev/null \
    | grep -q '"msg":"Runner registered".*"status":"online"'
}

tf="$(pick_tf)"
[[ -n "${tf}" ]] || die "tofu or terraform is required"
[[ -f "${TF_DIR}/terraform.tfstate" ]] || die "no terraform.tfstate; tofu apply first with attach false"

if [[ -z "${RUNNER_NAME:-}" ]]; then
  RUNNER_NAME="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_name 2>/dev/null || true)"
fi
RUNNER_NAME="${RUNNER_NAME:-cce-scm-runner}"

CTX="$(resolve_context)"
NS="${NS:-}"
if [[ -z "${NS}" && -f "${NS_FILE}" ]]; then
  NS="$(tr -d '[:space:]' < "${NS_FILE}")"
fi
NS="${NS:-aiden-cce-runner}"

info "runner=${RUNNER_NAME} namespace=${NS} context=${CTX}"

status="$(guild_runner_status 2>/dev/null || true)"
if [[ -z "${status}" ]] && pod_says_online "${CTX}" "${NS}"; then
  status="online"
fi
info "runner status=${status:-unknown}"
[[ "${status}" =~ [Oo]nline ]] || die "Guild runner is not Online (status=${status:-unknown}). Run ./helm/install.sh first."

printf 'remote_runner_attach_to_agent = true\n' > "${ATTACH_TFVARS}"
info "wrote ${ATTACH_TFVARS} (auto-loaded by tofu) so later applies keep the runner attached"

info "tofu apply remote_runners=[${RUNNER_NAME}]"
"${tf}" -chdir="${TF_DIR}" apply -input=false -auto-approve \
  -var="remote_runner_attach_to_agent=true"

attached="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_attach_to_agent)"
[[ "${attached}" == "true" ]] || die "apply finished but remote_runner_attach_to_agent is ${attached}"
info "OK: agent $("${tf}" -chdir="${TF_DIR}" output -raw agent_name) attached to ${RUNNER_NAME}"
info "Next: set GITLAB_TOKEN, tofu apply, wait ~60s for vault sync, then chat the prompt yourself."
