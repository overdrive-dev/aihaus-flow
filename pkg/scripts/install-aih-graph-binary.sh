#!/usr/bin/env bash
# install-aih-graph-binary.sh — download a pre-built aih-graph release binary
# from GitHub Releases and install it into AIH_GRAPH_BIN (default
# ~/.aihaus/bin/aih-graph).
#
# Per ADR-260515-D-amend-01 option [2] (binary fallback) + ADR-260515-B-amend-02
# (pure-Go pivot — binary is the primary distribution path; source build is
# contributor-only).
#
# Env vars:
#   AIH_GRAPH_VERSION   Tag to download (default: latest). Format: v0.1.0
#   AIH_GRAPH_BIN       Output path (default: $HOME/.aihaus/bin/aih-graph[.exe])
#   AIH_GRAPH_REPO      GitHub repo (default: overdrive-dev/aihaus-flow)
#
# Exit codes:
#   0  success
#   1  download failure / platform unsupported
#   2  invocation error (bad args)

set -euo pipefail

readonly DEFAULT_REPO="overdrive-dev/aihaus-flow"
readonly REPO="${AIH_GRAPH_REPO:-$DEFAULT_REPO}"

usage() {
  cat <<'USAGE'
Usage: install-aih-graph-binary.sh [--version vX.Y.Z] [--bin PATH] [--repo OWNER/REPO]

Downloads a pre-built aih-graph binary for the current platform.

Options:
  --version  vX.Y.Z       Release tag (default: latest)
  --bin      PATH         Output path (default: $HOME/.aihaus/bin/aih-graph)
  --repo     OWNER/REPO   GitHub repo (default: overdrive-dev/aihaus-flow)
  -h, --help              Show this message

Resolution rules:
  - Platform = (uname -s, uname -m) → linux-amd64 | darwin-amd64 | darwin-arm64
                                       | windows-amd64
  - Release asset filename = aih-graph-<goos>-<goarch>[.exe]
USAGE
}

VERSION="${AIH_GRAPH_VERSION:-latest}"
BIN_PATH="${AIH_GRAPH_BIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --bin)     BIN_PATH="$2"; shift 2 ;;
    --repo)    REPO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Detect platform.
uname_s="$(uname -s)"
uname_m="$(uname -m)"
case "$uname_s" in
  Linux*)        goos="linux" ;;
  Darwin*)       goos="darwin" ;;
  MINGW*|MSYS*|CYGWIN*) goos="windows" ;;
  *)             echo "install-aih-graph-binary: unsupported OS '$uname_s'" >&2; exit 1 ;;
esac
case "$uname_m" in
  x86_64|amd64)  goarch="amd64" ;;
  arm64|aarch64) goarch="arm64" ;;
  *)             echo "install-aih-graph-binary: unsupported arch '$uname_m'" >&2; exit 1 ;;
esac

# Linux ARM64 / Windows ARM64 not in v0.1 matrix per .github/workflows/aih-graph-release.yml.
if [[ "$goos" == "linux" && "$goarch" == "arm64" ]]; then
  echo "install-aih-graph-binary: linux-arm64 not in v0.1 release matrix; build from source" >&2
  exit 1
fi
if [[ "$goos" == "windows" && "$goarch" == "arm64" ]]; then
  echo "install-aih-graph-binary: windows-arm64 not in v0.1 release matrix; build from source" >&2
  exit 1
fi

ext=""
[[ "$goos" == "windows" ]] && ext=".exe"

# Default output path.
if [[ -z "$BIN_PATH" ]]; then
  BIN_PATH="$HOME/.aihaus/bin/aih-graph${ext}"
fi

# Resolve version → tag.
if [[ "$VERSION" == "latest" ]]; then
  # GitHub redirects /releases/latest to the actual tag URL. Follow once.
  tag_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null || true)"
  if [[ -z "$tag_url" ]]; then
    echo "install-aih-graph-binary: failed to resolve latest release" >&2
    exit 1
  fi
  # tag_url is like https://github.com/owner/repo/releases/tag/aih-graph-v0.1.0
  TAG="${tag_url##*/}"
else
  TAG="$VERSION"
  [[ "$TAG" != aih-graph-v* ]] && TAG="aih-graph-${TAG}"
fi

ASSET="aih-graph-${goos}-${goarch}${ext}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

echo "install-aih-graph-binary: ${TAG} → ${BIN_PATH}"
mkdir -p "$(dirname "$BIN_PATH")"

# Download. curl with -fL = fail on HTTP error + follow redirects.
tmp="${BIN_PATH}.tmp.$$"
if ! curl -fL --progress-bar -o "$tmp" "$DOWNLOAD_URL"; then
  rm -f "$tmp"
  echo "install-aih-graph-binary: download failed: ${DOWNLOAD_URL}" >&2
  echo "  (verify the release exists at https://github.com/${REPO}/releases/tag/${TAG})" >&2
  exit 1
fi

# Verify SHA-256 if checksum file is also published. Optional — soft-fail on
# absent checksum but hard-fail on mismatch.
checksum_url="${DOWNLOAD_URL}.sha256"
if curl -fsSL "$checksum_url" -o "${tmp}.sha256" 2>/dev/null; then
  expected_sha="$(awk '{print $1}' "${tmp}.sha256")"
  actual_sha="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$tmp" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$expected_sha" && -n "$actual_sha" && "$expected_sha" != "$actual_sha" ]]; then
    rm -f "$tmp" "${tmp}.sha256"
    echo "install-aih-graph-binary: SHA-256 mismatch (expected $expected_sha, got $actual_sha)" >&2
    exit 1
  fi
  rm -f "${tmp}.sha256"
fi

chmod +x "$tmp" 2>/dev/null || true
mv -f "$tmp" "$BIN_PATH"

echo "install-aih-graph-binary: installed to $BIN_PATH"
"$BIN_PATH" version 2>/dev/null || true
