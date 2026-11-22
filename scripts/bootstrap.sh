#!/usr/bin/env bash
# Prepare a new Mac to run this repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This repository only supports macOS." >&2
  exit 1
fi

if ! xcode-select --print-path >/dev/null 2>&1; then
  log "Installing the Xcode command line tools"
  xcode-select --install
  echo "Finish the installer, then re-run this script." >&2
  exit 1
fi

find_brew_prefix() {
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [[ -x "$prefix/bin/brew" ]]; then
      echo "$prefix"
      return 0
    fi
  done
  return 1
}

if ! BREW_PREFIX="$(find_brew_prefix)"; then
  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if ! BREW_PREFIX="$(find_brew_prefix)"; then
    echo "Homebrew installed, but brew was not found in /opt/homebrew or /usr/local." >&2
    exit 1
  fi
fi

eval "$("$BREW_PREFIX/bin/brew" shellenv)"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "Installing Ansible"
  brew install ansible
fi

if ! command -v ansible-lint >/dev/null 2>&1; then
  log "Installing ansible-lint"
  brew install ansible-lint
fi

log "Installing pinned Galaxy collections"
ansible-galaxy install -r requirements.yml

log "Ready. Preview changes with 'make check', apply them with 'make apply'."
