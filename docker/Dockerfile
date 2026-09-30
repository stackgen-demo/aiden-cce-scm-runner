# CCE overlay on stock aiden-runner. git/gh/glab are already in the base image.
# Published as ghcr.io/stackgen-demo/aiden-cce-scm-runner:<tag> (call image: :scm-main from CCE git main).
#
# Install modes (mutually exclusive build-args):
#   CCE_FROM_GIT=1  — multi-stage build from BuildKit context `ccesrc` (FROM_MAIN=1 script)
#   CCE_FROM_LOCAL=1 — COPY prebuilt binary from cce-staging/cce
#   default — download pinned release from releases.stackgen.com
#
# TARGETARCH is amd64|arm64 from BuildKit.

ARG AIDEN_RUNNER_IMAGE=ghcr.io/appcd-dev/stackgen-guild-aiden-runner:main
ARG GO_IMAGE=golang:1.24-bookworm
ARG CCE_FROM_GIT=0

# ----- optional: compile CCE from git context (linux/${TARGETARCH}, CGO) -----
FROM ${GO_IMAGE} AS cce-git-build
ARG TARGETARCH
ARG CCE_FROM_GIT=0
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
  && rm -rf /var/lib/apt/lists/*
# When CCE_FROM_GIT=0, still create a stub so later COPY --from succeeds in one Dockerfile.
RUN mkdir -p /out && echo '#!/bin/true' > /out/cce && chmod +x /out/cce
COPY --from=ccesrc . /src/
RUN --mount=type=secret,id=gh_token \
  if [ "${CCE_FROM_GIT}" = "1" ]; then \
      TOKEN="$$(cat /run/secrets/gh_token)"; \
      git config --global url."https://x-access-token:$${TOKEN}@github.com/".insteadOf "https://github.com/"; \
      GOPRIVATE=github.com/appcd-dev/* CGO_ENABLED=1 GOOS=linux GOARCH="${TARGETARCH}" \
        go build -mod=mod -o /out/cce ./cmd/cce; \
    fi

# ----- runtime: aiden-runner + cce -----
FROM ${AIDEN_RUNNER_IMAGE}

ARG CCE_VERSION=0.0.8
ARG CCE_FROM_LOCAL=0
ARG CCE_FROM_GIT=0
ARG TARGETARCH
ARG CCE_SHA256_AMD64=8f3d27764f557ceb06b29e8fc2f66e6aef3ecacd1986aa80d1bd8854308bd9c5
ARG CCE_SHA256_ARM64=1f78693316a58e7db51a1768dd54ca7df8bb5a0e4a7c80434571e57735393dfe

USER root

COPY cce-staging/ /tmp/cce-staging/
COPY --from=cce-git-build /out/cce /tmp/cce-from-git

# Install into /usr/bin (not only /usr/local/bin). aiden-runner CLI discovery
# scans system_bin_dirs: /bin /usr/bin /sbin /usr/sbin — /usr/local/bin is skipped.
RUN set -eux; \
  if [ "${CCE_FROM_GIT}" = "1" ]; then \
    install -m 0755 /tmp/cce-from-git /usr/bin/cce; \
  elif [ "${CCE_FROM_LOCAL}" = "1" ]; then \
    test -f /tmp/cce-staging/cce; \
    install -m 0755 /tmp/cce-staging/cce /usr/bin/cce; \
  else \
    case "${TARGETARCH}" in \
      amd64) cce_sha="${CCE_SHA256_AMD64}" ;; \
      arm64) cce_sha="${CCE_SHA256_ARM64}" ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    url="https://releases.stackgen.com/binaries/cce/v${CCE_VERSION}/cce_${CCE_VERSION}_linux_${TARGETARCH}.tar.gz"; \
    curl -fsSL -o /tmp/cce.tgz "${url}"; \
    echo "${cce_sha}  /tmp/cce.tgz" | sha256sum -c -; \
    tar -xzf /tmp/cce.tgz -C /usr/bin cce; \
    rm -f /tmp/cce.tgz; \
    chmod +x /usr/bin/cce; \
  fi; \
  ln -sf /usr/bin/cce /usr/local/bin/cce; \
  rm -rf /tmp/cce-staging /tmp/cce-from-git; \
  cce --version; \
  if [ "${CCE_FROM_GIT}" = "1" ] || [ "${CCE_FROM_LOCAL}" = "1" ]; then \
    cce scm describe --help >/dev/null; \
  fi

USER runner

ENV CCE_VERSION=${CCE_VERSION}
ENV ALLOWED_CLIS=bash,sh,git,glab,gh,cce,curl,jq,tar,mkdir,cp,rm,cat,grep,awk,sed,head,tail,chmod,mktemp,printf,test,command
ENV AUTO_DISCOVER=true
