#!/usr/bin/env bash
# build-and-push.sh — build the CCE runner overlay and push it to GHCR.
#
# Multi-arch call image (recommended — works on amd64 and arm64 clusters):
#   FROM_MAIN=1 \
#     CCE_REPO=/path/to/cce \
#     IMAGE=ghcr.io/stackgen-demo/aiden-cce-scm-runner \
#     TAG=scm-main \
#     PLATFORMS=linux/amd64,linux/arm64 \
#     ./scripts/build-and-push.sh
#
# Single arch (legacy):
#   PLATFORMS=linux/arm64   # developer-eks
#   PLATFORMS=linux/amd64   # many customer nodes
#
# FROM_MAIN=1 compiles CCE from local git main into docker/cce-staging/cce,
# then docker buildx with CCE_FROM_LOCAL=1. Do NOT use the default (non-FROM_MAIN)
# path for customer demos — that curls CCE release v0.0.8, which has no `scm` subcommand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CCE_REPO="${CCE_REPO:-${HOME}/work/cce}"
FROM_MAIN="${FROM_MAIN:-0}"
STAGING="${ROOT}/docker/cce-staging"
DUMMY_CCESRC="${ROOT}/docker/cce-staging"

IMAGE="${IMAGE:-ghcr.io/stackgen-demo/aiden-cce-scm-runner}"
BASE_IMAGE="${AIDEN_RUNNER_IMAGE:-ghcr.io/appcd-dev/stackgen-guild-aiden-runner:main}"
GO_IMAGE="${GO_IMAGE:-golang:1.25-bookworm}"

cleanup_staging_binary() {
  rm -f "${STAGING}/cce"
}
trap cleanup_staging_binary EXIT

echo "==> login ghcr.io"
gh auth token | docker login ghcr.io -u "$(gh api user --jq .login)" --password-stdin

if [[ "${FROM_MAIN}" != "1" ]]; then
  echo "error: default (release tarball) bake is not for the scm-describe call image." >&2
  echo "       Use FROM_MAIN=1 so the binary includes \`cce scm describe\`." >&2
  echo "       Example:" >&2
  echo "         FROM_MAIN=1 CCE_REPO=/path/to/cce IMAGE=${IMAGE} TAG=scm-main PLATFORMS=linux/amd64,linux/arm64 $0" >&2
  exit 1
fi

PLATFORMS="${PLATFORMS:-linux/arm64}"
TAG="${TAG:-scm-main}"
[[ -d "${CCE_REPO}" ]] || { echo "error: CCE_REPO not a directory: ${CCE_REPO}" >&2; exit 1; }
[[ -d "${CCE_REPO}/cmd/cce" ]] || {
  echo "error: ${CCE_REPO} does not look like the CCE repo (missing cmd/cce)" >&2
  exit 1
}

GOMODCACHE="$(go env GOMODCACHE)"
[[ -d "${GOMODCACHE}" ]] || { echo "error: GOMODCACHE missing (${GOMODCACHE}); run go mod download in CCE first" >&2; exit 1; }

echo "==> ensure CCE modules on host (for private github.com/appcd-dev/*)"
(cd "${CCE_REPO}" && go mod download)

IFS=',' read -r -a PLATFORM_LIST <<< "${PLATFORMS}"
ARCH_TAGS=()

build_one_platform() {
  local platform="$1"
  local goarch arch_tag
  case "${platform}" in
    linux/arm64) goarch=arm64 ;;
    linux/amd64) goarch=amd64 ;;
    *) echo "error: unsupported platform ${platform} (need linux/arm64 or linux/amd64)" >&2; exit 1 ;;
  esac

  if [[ "${#PLATFORM_LIST[@]}" -gt 1 ]]; then
    arch_tag="${TAG}-${goarch}"
  else
    arch_tag="${TAG}"
  fi

  echo "==> compile cce linux/${goarch} in ${GO_IMAGE}"
  rm -f "${STAGING}/cce"
  docker run --rm --platform "${platform}" \
    -v "${CCE_REPO}:/src:ro" \
    -v "${GOMODCACHE}:/go/pkg/mod" \
    -v "${STAGING}:/out" \
    -w /src \
    -e CGO_ENABLED=1 \
    -e GOOS=linux \
    -e GOARCH="${goarch}" \
    -e GOMODCACHE=/go/pkg/mod \
    -e GOPRIVATE=github.com/appcd-dev/* \
    "${GO_IMAGE}" \
    bash -c 'apt-get update -qq && apt-get install -y -qq gcc libc6-dev >/dev/null && go build -mod=mod -o /out/cce ./cmd/cce && chmod +x /out/cce'

  test -x "${STAGING}/cce"

  echo "==> build+push ${IMAGE}:${arch_tag} (${platform})"
  docker buildx build \
    --platform "${platform}" \
    --build-context "ccesrc=${DUMMY_CCESRC}" \
    --build-arg "AIDEN_RUNNER_IMAGE=${BASE_IMAGE}" \
    --build-arg "GO_IMAGE=${GO_IMAGE}" \
    --build-arg "CCE_FROM_GIT=0" \
    --build-arg "CCE_FROM_LOCAL=1" \
    --build-arg "CCE_VERSION=main" \
    -t "${IMAGE}:${arch_tag}" \
    --push \
    -f "${ROOT}/docker/Dockerfile" \
    "${ROOT}/docker"

  ARCH_TAGS+=("${IMAGE}:${arch_tag}")
}

for platform in "${PLATFORM_LIST[@]}"; do
  platform="$(echo "${platform}" | tr -d '[:space:]')"
  [[ -n "${platform}" ]] || continue
  build_one_platform "${platform}"
done

if [[ "${#ARCH_TAGS[@]}" -gt 1 ]]; then
  echo "==> create multi-arch manifest ${IMAGE}:${TAG}"
  docker buildx imagetools create -t "${IMAGE}:${TAG}" "${ARCH_TAGS[@]}"
fi

docker buildx imagetools inspect "${IMAGE}:${TAG}"
echo "OK: ${IMAGE}:${TAG}"
echo "Verify (anonymous pull): docker logout ghcr.io; docker pull ${IMAGE}:${TAG}"
echo "Verify scm: docker run --rm --entrypoint cce ${IMAGE}:${TAG} scm describe --help"
