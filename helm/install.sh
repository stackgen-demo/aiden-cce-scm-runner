#!/usr/bin/env bash
# install.sh — deploy the CCE overlay aiden-runner into a throwaway namespace.
# Takes env vars. Does not lock to any specific cluster or kube context.
#
# Required:
#   STACKGEN_RUNNER_TOKEN   from: tofu -chdir=terraform output -raw remote_runner_token
#   MOTHERSHIP_URL          from: tofu -chdir=terraform output -raw remote_runner_mothership_url
#
# Optional:
#   RUNNER_IMAGE   default ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main
#   NS             default aiden-cce-runner
#   KUBE_CONTEXT   current context when unset
#   HELM_RELEASE   default cce-runner
#   ALLOWED_CLIS   includes cce (and git/glab for gated deep scan)
#
# Teardown:
#   helm uninstall "$HELM_RELEASE" -n "$NS"
#   kubectl delete namespace "$NS"
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
NS_FILE="${ROOT}/.helm-namespace"

HELM_REPO="${HELM_REPO:-https://appcd-public-releases.s3.us-east-2.amazonaws.com/charts/}"
HELM_CHART="${HELM_CHART:-aiden-runner}"
HELM_RELEASE="${HELM_RELEASE:-cce-runner}"
ALLOWED_CLIS="${ALLOWED_CLIS:-bash,sh,git,glab,gh,cce,curl,jq,cat,head,tail,wc,mkdir,cp,rm,mktemp,printf,test,command}"
ONLINE_TIMEOUT_SECS="${ONLINE_TIMEOUT_SECS:-300}"
DEFAULT_IMAGE="ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"

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

assert_throwaway_ns() {
  local ns="$1"
  [[ "${ns}" != aiden-runner ]] || die "refusing shared namespace aiden-runner; use a throwaway ns"
  [[ "${ns}" != kube-system ]] || die "refusing namespace kube-system"
}

split_image() {
  local image="$1"
  case "${image}" in
    *:*)
      IMAGE_REPO="${image%:*}"
      IMAGE_TAG="${image##*:}"
      ;;
    *)
      IMAGE_REPO="${image}"
      IMAGE_TAG="scm-main"
      ;;
  esac
}

load_runner_creds() {
  if [[ -n "${STACKGEN_RUNNER_TOKEN:-}" && -n "${MOTHERSHIP_URL:-}" ]]; then
    RUNNER_TOKEN="${STACKGEN_RUNNER_TOKEN}"
    MOTHERSHIP="${MOTHERSHIP_URL}"
    return
  fi

  local tf
  tf="$(pick_tf)"
  [[ -n "${tf}" ]] || die "set STACKGEN_RUNNER_TOKEN and MOTHERSHIP_URL, or apply terraform/ first"
  [[ -f "${TF_DIR}/terraform.tfstate" ]] || die "no terraform.tfstate in terraform/; tofu apply first (attach still false)"

  RUNNER_TOKEN="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_token)"
  MOTHERSHIP="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_mothership_url)"
  if [[ -z "${RUNNER_IMAGE:-}" ]]; then
    RUNNER_IMAGE="$("${tf}" -chdir="${TF_DIR}" output -raw runner_docker_image)"
  fi
  RUNNER_NAME="$("${tf}" -chdir="${TF_DIR}" output -raw remote_runner_name)"
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

wait_guild_online() {
  info "wait until Guild runner status is Online (timeout ${ONLINE_TIMEOUT_SECS}s)"
  local deadline=$((SECONDS + ONLINE_TIMEOUT_SECS))
  local status=""
  while (( SECONDS < deadline )); do
    status="$(guild_runner_status 2>/dev/null || true)"
    if [[ -z "${status}" ]]; then
      if kubectl --context "${CTX}" -n "${NS}" logs -l app.kubernetes.io/name=aiden-runner --tail=80 2>/dev/null \
        | grep -q '"msg":"Runner registered".*"status":"online"'; then
        status="online"
      fi
    fi
    info "runner status=${status:-unknown}"
    if [[ "${status}" =~ [Oo]nline ]]; then
      return 0
    fi
    sleep 10
  done
  die "runner did not become Online (last status=${status:-unknown}). Check pod logs in ${NS}."
}

CTX="$(resolve_context)"
NS="${NS:-aiden-cce-runner}"
RUNNER_IMAGE="${RUNNER_IMAGE:-}"
RUNNER_TOKEN=""
MOTHERSHIP=""
RUNNER_NAME="${RUNNER_NAME:-cce-scm-runner}"

assert_throwaway_ns "${NS}"
load_runner_creds
[[ -n "${RUNNER_TOKEN}" ]] || die "empty runner token"
[[ -n "${MOTHERSHIP}" ]] || die "empty mothership URL"
[[ -n "${RUNNER_IMAGE}" ]] || RUNNER_IMAGE="${DEFAULT_IMAGE}"
split_image "${RUNNER_IMAGE}"

info "context=${CTX}"
info "namespace=${NS} release=${HELM_RELEASE} image=${IMAGE_REPO}:${IMAGE_TAG}"
info "ALLOWED_CLIS=${ALLOWED_CLIS}"
info "public image: no GHCR pull secret required"

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" label namespace "${NS}" purpose=cce-scm-runner ephemeral=true --overwrite
printf '%s\n' "${NS}" > "${NS_FILE}"

VALUES="$(mktemp)"
trap 'rm -f "${VALUES}"' EXIT
umask 077
IMAGE_REPO="${IMAGE_REPO}" IMAGE_TAG="${IMAGE_TAG}" \
  MOTHERSHIP="${MOTHERSHIP}" RUNNER_TOKEN="${RUNNER_TOKEN}" ALLOWED_CLIS="${ALLOWED_CLIS}" \
  python3 - "${VALUES}" <<'PY'
import os, sys
path = sys.argv[1]

def q(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

lines = [
    "image:",
    f"  repository: {q(os.environ['IMAGE_REPO'])}",
    f"  tag: {q(os.environ['IMAGE_TAG'])}",
    "  pullPolicy: Always",
    "runner:",
    f"  mothershipUrl: {q(os.environ['MOTHERSHIP'])}",
    f"  token: {q(os.environ['RUNNER_TOKEN'])}",
    f"  allowedClis: {q(os.environ['ALLOWED_CLIS'])}",
    "rbac:",
    "  createClusterReadRole: false",
    "  namespaced:",
    "    enabled: true",
    "    createReadRole: true",
]
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY

helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" \
  --repo "${HELM_REPO}" \
  --kube-context "${CTX}" \
  --namespace "${NS}" \
  --values "${VALUES}" \
  --wait --timeout 5m

info "rollout restart so the pod loads the current runner token"
kubectl --context "${CTX}" -n "${NS}" rollout restart "deploy/${HELM_RELEASE}-aiden-runner"
kubectl --context "${CTX}" -n "${NS}" rollout status "deploy/${HELM_RELEASE}-aiden-runner" --timeout=120s

info "pods in ${NS}:"
kubectl --context "${CTX}" -n "${NS}" get pods,sa
wait_guild_online
info "OK: runner ${RUNNER_NAME} Online in ${NS}."
info "Next: ./scripts/attach-runner.sh"
