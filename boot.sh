#!/usr/bin/env bash

set -Eeuo pipefail

# ---------- Config (override via env) ----------
PROJECT_NAME="${PROJECT_NAME:-arch-me-later}"             # change default to your project name
REPO_URL="${REPO_URL:-https://github.com/you/myenv.git}"
REPO_REF="${REPO_REF:-main}"                      # branch/tag/commit
INSTALL_DIR="${INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/$PROJECT_NAME}"
LOG_DIR="${LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$PROJECT_NAME}"
NO_UPGRADE="${NO_UPGRADE:-0}"                     # set to 1 to skip `pacman -Syu`

die() { printf "boot.sh: %s\n" "$*" >&2; exit 1; }
info() { printf "==> %s\n" "$*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Please run as a normal user (not root). This script will use sudo when needed."
fi

need_cmd sudo
need_cmd bash

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bootstrap-$(date +%Y%m%d-%H%M%S).log"

# Log everything (stdout+stderr) to file, while still showing output
exec > >(tee -a "$LOG_FILE") 2>&1

info "Bootstrap log: $LOG_FILE"

info "Requesting sudo credentials..."
sudo -v

( while true; do sudo -n -v 2>/dev/null || exit 0; sleep 60; done ) &
SUDO_KEEPALIVE_PID=$!

cleanup() {
  kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  sudo -k 2>/dev/null || true
}
trap cleanup EXIT

need_cmd pacman

if [[ "$NO_UPGRADE" != "1" ]]; then
  info "Updating system packages (pacman -Syu)..."
  sudo pacman -Syu --noconfirm
else
  info "Skipping full system upgrade (NO_UPGRADE=1)."
fi

info "Installing bootstrap dependencies (git, curl)..."
sudo pacman -S --needed --noconfirm git curl ca-certificates

info "Ensuring install directory: $INSTALL_DIR"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Repo already present; updating..."
  git -C "$INSTALL_DIR" remote set-url origin "$REPO_URL" || true
  git -C "$INSTALL_DIR" fetch --all --tags --prune

  # Try to checkout the requested ref (branch/tag/commit)
  if git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/heads/$REPO_REF"; then
    git -C "$INSTALL_DIR" checkout "$REPO_REF"
    git -C "$INSTALL_DIR" pull --ff-only origin "$REPO_REF" || true
  else
    git -C "$INSTALL_DIR" checkout -B "$REPO_REF" "origin/$REPO_REF" 2>/dev/null \
      || git -C "$INSTALL_DIR" checkout "$REPO_REF"
  fi
elif [[ -d "$INSTALL_DIR" ]]; then
  die "INSTALL_DIR exists but is not a git repo: $INSTALL_DIR"
else
  info "Cloning repo..."
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR" \
    || git clone "$REPO_URL" "$INSTALL_DIR"
fi

INSTALLER="$INSTALL_DIR/install.sh"
[[ -x "$INSTALLER" ]] || die "Installer not found or not executable: $INSTALLER"

info "Running installer: $INSTALLER"
exec bash "$INSTALLER" "$@"
