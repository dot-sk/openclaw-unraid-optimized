#!/usr/bin/env bash
set -Eeuo pipefail

# Install the optimized OpenClaw Unraid template and User Script.
#
# Usage after publishing to GitHub:
#   curl -fsSL https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main/install.sh | bash
#
# To also run the one-button setup immediately:
#   curl -fsSL https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main/install.sh | RUN_NOW=1 bash
#
# Override source branch/repo:
#   REPO_RAW=https://raw.githubusercontent.com/<owner>/<repo>/main bash install.sh

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main}"
TEMPLATE_URL="${TEMPLATE_URL:-${REPO_RAW}/templates/my-OpenClaw-Optimized.xml}"
SCRIPT_URL="${SCRIPT_URL:-${REPO_RAW}/scripts/openclaw-unraid-onebutton.sh}"

TEMPLATE_DEST="${TEMPLATE_DEST:-/boot/config/plugins/dockerMan/templates-user/my-OpenClaw-Optimized.xml}"
USER_SCRIPT_DIR="${USER_SCRIPT_DIR:-/boot/config/plugins/user.scripts/scripts/OpenClaw Optimized Setup}"
USER_SCRIPT_DEST="${USER_SCRIPT_DEST:-${USER_SCRIPT_DIR}/script}"
RUN_NOW="${RUN_NOW:-0}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

fetch() {
  url="$1"
  dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    die "Missing curl or wget"
  fi
}

if [ "$(id -u)" != "0" ]; then
  die "Run as root on Unraid."
fi

need_cmd mkdir
need_cmd chmod

echo "Installing OpenClaw optimized Unraid files"
echo "Source: ${REPO_RAW}"

mkdir -p "$(dirname "$TEMPLATE_DEST")"
mkdir -p "$USER_SCRIPT_DIR"

tmp_template="$(mktemp)"
tmp_script="$(mktemp)"
trap 'rm -f "$tmp_template" "$tmp_script"' EXIT

echo "Downloading template"
fetch "$TEMPLATE_URL" "$tmp_template"

echo "Downloading one-button script"
fetch "$SCRIPT_URL" "$tmp_script"

echo "Writing ${TEMPLATE_DEST}"
cp "$tmp_template" "$TEMPLATE_DEST"

echo "Writing ${USER_SCRIPT_DEST}"
cp "$tmp_script" "$USER_SCRIPT_DEST"
chmod +x "$USER_SCRIPT_DEST"

echo
echo "Installed:"
echo "  ${TEMPLATE_DEST}"
echo "  ${USER_SCRIPT_DEST}"

if [ "$RUN_NOW" = "1" ]; then
  echo
  echo "RUN_NOW=1 set; running one-button setup"
  "$USER_SCRIPT_DEST"
else
  echo
  echo "Next steps:"
  echo "  1. Open Unraid UI -> Plugins -> User Scripts."
  echo "  2. Run: OpenClaw Optimized Setup"
  echo "  3. Or run now:"
  echo "     bash '${USER_SCRIPT_DEST}'"
fi
