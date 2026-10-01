#!/usr/bin/env bash
# install.sh — deploy the CCE overlay aiden-runner into a customer namespace.
#
# For customer platform / cluster operators. No tofu. No Guild admin PAT required.
#
# Required env (from SE after Guild UI creates the remote runner):
#   STACKGEN_RUNNER_TOKEN   registration token
#   MOTHERSHIP_URL          Guild base URL (trailing slash stripped)
#
# Optional:
#   RUNNER_IMAGE     default ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main
#   NS               default aiden-cce-runner (created if missing)
#   KUBE_CONTEXT     current kubectl context when unset
#   HELM_RELEASE     default cce-runner
#   RUNNER_NAME      default cce-scm-runner (log messages only)
#   ALLOWED_CLIS     includes cce
#   HELM_TIMEOUT     default 10m (image is ~500MB)
#   WAIT_ONLINE=1    also poll pod logs for Online (default: off — SE checks Guild UI)
#
# Prereqs on the machine that runs this: kubectl, helm 3.
# Teardown:
#   helm uninstall "$HELM_RELEASE" -n "$NS"
#   kubectl delete namespace "$NS"
set -euo pipefail

HELM_REPO="${HELM_REPO:-https://appcd-public-releases.s3.us-east-2.amazonaws.com/charts/}"
HELM_CHART="${HELM_CHART:-aiden-runner}"
HELM_RELEASE="${HELM_RELEASE:-cce-runner}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
ALLOWED_CLIS="${ALLOWED_CLIS:-bash,sh,git,glab,gh,cce,curl,jq,cat,head,tail,wc,mkdir,cp,rm,mktemp,printf,test,command}"
ONLINE_TIMEOUT_SECS="${ONLINE_TIMEOUT_SECS:-300}"
DEFAULT_IMAGE="ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }
warn() { echo "warning: $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

resolve_context() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    echo "${KUBE_CONTEXT}"
    return
  fi
  kubectl config current-context
}

assert_throwaway_ns() {
  local ns="$1"
  [[ "${ns}" != aiden-runner ]] || die "refusing shared namespace aiden-runner; set NS to a throwaway name"
  [[ "${ns}" != kube-system ]] || die "refusing namespace kube-system"
  [[ "${ns}" != default ]] || die "refusing namespace default; set NS to a throwaway name"
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

# YAML double-quote escape without python (customer jump hosts may lack python3).
yaml_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

require_runner_creds() {
  [[ -n "${STACKGEN_RUNNER_TOKEN:-}" ]] || die "set STACKGEN_RUNNER_TOKEN (Guild remote-runner registration token from your SE)"
  [[ -n "${MOTHERSHIP_URL:-}" ]] || die "set MOTHERSHIP_URL (Guild base URL, e.g. https://guild.example.com)"
  RUNNER_TOKEN="${STACKGEN_RUNNER_TOKEN}"
  # Strip trailing slash — chart / runner are picky about base URL shape.
  MOTHERSHIP="${MOTHERSHIP_URL%/}"
  [[ "${MOTHERSHIP}" == https://* || "${MOTHERSHIP}" == http://* ]] || die "MOTHERSHIP_URL must start with https:// (or http:// for lab only)"
}

write_values() {
  local path="$1"
  umask 077
  cat > "${path}" <<EOF
image:
  repository: $(yaml_quote "${IMAGE_REPO}")
  tag: $(yaml_quote "${IMAGE_TAG}")
  pullPolicy: Always
runner:
  mothershipUrl: $(yaml_quote "${MOTHERSHIP}")
  token: $(yaml_quote "${RUNNER_TOKEN}")
  allowedClis: $(yaml_quote "${ALLOWED_CLIS}")
rbac:
  createClusterReadRole: false
  namespaced:
    enabled: true
    createReadRole: true
EOF
}

wait_pod_online_log() {
  info "WAIT_ONLINE=1 — watching pod logs for Online (timeout ${ONLINE_TIMEOUT_SECS}s)"
  local deadline=$((SECONDS + ONLINE_TIMEOUT_SECS))
  while (( SECONDS < deadline )); do
    if kubectl --context "${CTX}" -n "${NS}" logs -l app.kubernetes.io/name=aiden-runner --tail=100 2>/dev/null \
      | grep -q '"msg":"Runner registered".*"status":"online"'; then
      info "pod log reports Online"
      return 0
    fi
    info "still waiting for Online in pod logs…"
    sleep 10
  done
  warn "did not see Online in pod logs within ${ONLINE_TIMEOUT_SECS}s — Helm install succeeded; confirm in Guild UI"
  return 0
}

need_cmd kubectl
need_cmd helm

CTX="$(resolve_context)"
NS="${NS:-aiden-cce-runner}"
RUNNER_IMAGE="${RUNNER_IMAGE:-${DEFAULT_IMAGE}}"
RUNNER_NAME="${RUNNER_NAME:-cce-scm-runner}"

assert_throwaway_ns "${NS}"
require_runner_creds
split_image "${RUNNER_IMAGE}"

info "context=${CTX}"
info "namespace=${NS} release=${HELM_RELEASE} image=${IMAGE_REPO}:${IMAGE_TAG}"
info "mothership=${MOTHERSHIP}"
info "ALLOWED_CLIS=${ALLOWED_CLIS}"
info "public image: no GHCR pull secret required"

kubectl --context "${CTX}" create namespace "${NS}" --dry-run=client -o yaml | kubectl --context "${CTX}" apply -f -
kubectl --context "${CTX}" label namespace "${NS}" purpose=cce-scm-runner ephemeral=true --overwrite 2>/dev/null || true

VALUES="$(mktemp)"
trap 'rm -f "${VALUES}"' EXIT
write_values "${VALUES}"

info "helm upgrade --install (timeout ${HELM_TIMEOUT})"
helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART}" \
  --repo "${HELM_REPO}" \
  --kube-context "${CTX}" \
  --namespace "${NS}" \
  --create-namespace \
  --values "${VALUES}" \
  --wait --timeout "${HELM_TIMEOUT}"

# Token lives in a Helm secret; some upgrades skip a pod roll.
info "rollout restart so the pod loads the current runner token"
DEPLOY="${HELM_RELEASE}-aiden-runner"
kubectl --context "${CTX}" -n "${NS}" rollout restart "deploy/${DEPLOY}"
kubectl --context "${CTX}" -n "${NS}" rollout status "deploy/${DEPLOY}" --timeout=180s

info "pods in ${NS}:"
kubectl --context "${CTX}" -n "${NS}" get pods,sa

if [[ "${WAIT_ONLINE:-0}" == "1" ]]; then
  wait_pod_online_log
fi

info "OK: Helm release ${HELM_RELEASE} deployed in ${NS}."
info "SE next: Guild UI → confirm runner ${RUNNER_NAME} is Online → attach to analyst agent → wait ~60s for vault sync."
