#!/usr/bin/env bash
set -Eeuo pipefail

# One-button OpenClaw setup for Unraid.
# Safe to rerun. It recreates the Docker container, but keeps appdata.

CONTAINER_NAME="${CONTAINER_NAME:-OpenClaw}"
IMAGE="${IMAGE:-ghcr.io/openclaw/openclaw:latest}"
CONFIG_DIR="${CONFIG_DIR:-/mnt/user/appdata/openclaw/config}"
RUNTIME_ROOT="${RUNTIME_ROOT:-/mnt/cache/appdata/openclaw}"
HOST_PORT="${HOST_PORT:-18789}"
PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-https://claw.example.com}"
TRUSTED_PROXY_HEADER="${TRUSTED_PROXY_HEADER:-cf-access-authenticated-user-email}"
DETECTED_UNRAID_IP="${DETECTED_UNRAID_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
TRUSTED_PROXIES="${TRUSTED_PROXIES:-${DETECTED_UNRAID_IP:-127.0.0.1}}"
MODEL_REF="${MODEL_REF:-openai-codex/gpt-5.5}"
EMBEDDING_MODEL="${EMBEDDING_MODEL:-text-embedding-3-small}"
BROWSER_EXECUTABLE_PATH="${BROWSER_EXECUTABLE_PATH:-/root/.openclaw/ms-playwright/chromium-1217/chrome-linux64/chrome}"
PLUGIN_STAGE_DIR="${PLUGIN_STAGE_DIR:-/tmp/openclaw-plugin-stage}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/boot/config/plugins/dockerMan/templates-user}"

PLAYWRIGHT_DIR="${RUNTIME_ROOT}/root/ms-playwright"
BROWSER_DIR="${RUNTIME_ROOT}/root/browser"
WORKSPACE_DIR="${RUNTIME_ROOT}/workspace"
PROJECTS_DIR="${RUNTIME_ROOT}/projects"
HOMEBREW_DIR="${RUNTIME_ROOT}/homebrew"
PLUGIN_STAGE_HOST_DIR="${RUNTIME_ROOT}/plugin-stage"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

log() {
  printf '\n==> %s\n' "$*"
}

if [ "$(id -u)" != "0" ]; then
  die "Run as root on Unraid."
fi

need_cmd docker
need_cmd jq

if [ ! -d /mnt/cache ]; then
  die "/mnt/cache does not exist. Set RUNTIME_ROOT=/path/to/fast/appdata/openclaw and rerun."
fi

log "Creating persistent config and fast runtime directories"
mkdir -p \
  "$CONFIG_DIR" \
  "$PLAYWRIGHT_DIR" \
  "$BROWSER_DIR" \
  "$WORKSPACE_DIR" \
  "$PROJECTS_DIR" \
  "$HOMEBREW_DIR" \
  "$PLUGIN_STAGE_HOST_DIR" \
  "$TEMPLATE_DIR"

CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

if [ ! -s "$CONFIG_FILE" ]; then
  log "Creating minimal OpenClaw config"
  umask 077
  cat > "$CONFIG_FILE" <<JSON
{}
JSON
fi

log "Applying OpenClaw config"
stamp="$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-onebutton-${stamp}"

jq \
  --arg public_origin "$PUBLIC_ORIGIN" \
  --arg trusted_proxy_header "$TRUSTED_PROXY_HEADER" \
  --arg trusted_proxies "$TRUSTED_PROXIES" \
  --arg model_ref "$MODEL_REF" \
  --arg embedding_model "$EMBEDDING_MODEL" \
  --arg browser_executable_path "$BROWSER_EXECUTABLE_PATH" \
  '
  .gateway = (.gateway // {})
  | .gateway.mode = "local"
  | .gateway.bind = "lan"
  | .gateway.controlUi = (.gateway.controlUi // {})
  | .gateway.controlUi.allowedOrigins = [$public_origin]
  | .gateway.controlUi.allowInsecureAuth = true
  | .gateway.auth = (.gateway.auth // {})
  | .gateway.auth.mode = "trusted-proxy"
  | .gateway.auth.trustedProxy = (.gateway.auth.trustedProxy // {})
  | .gateway.auth.trustedProxy.userHeader = $trusted_proxy_header
  | .gateway.trustedProxies = (
      $trusted_proxies
      | split(",")
      | map(gsub("^\\s+|\\s+$"; ""))
      | map(select(length > 0))
    )
  | .update = (.update // {})
  | .update.checkOnStart = false
  | .update.auto = (.update.auto // {})
  | .update.auto.enabled = false
  | .agents = (.agents // {})
  | .agents.defaults = (.agents.defaults // {})
  | .agents.defaults.model = (.agents.defaults.model // {})
  | .agents.defaults.model.primary = $model_ref
  | .agents.defaults.memorySearch = (.agents.defaults.memorySearch // {})
  | .agents.defaults.memorySearch.provider = "openai"
  | .agents.defaults.memorySearch.model = $embedding_model
  | .agents.defaults.memorySearch.enabled = false
  | .plugins = (.plugins // {})
  | .plugins.enabled = true
  | .plugins.allow = [
      "browser",
      "device-pair",
      "document-extract",
      "openai",
      "telegram",
      "web-readability"
    ]
  | .plugins.entries = (.plugins.entries // {})
  | .plugins.entries.browser.enabled = true
  | .plugins.entries."device-pair".enabled = true
  | .plugins.entries."document-extract".enabled = true
  | .plugins.entries.openai.enabled = true
  | .plugins.entries.telegram.enabled = true
  | .plugins.entries."web-readability".enabled = true
  | .plugins.entries."memory-core".enabled = false
  | .plugins.entries.acpx.enabled = false
  | .plugins.entries.bonjour.enabled = false
  | .plugins.entries."phone-control".enabled = false
  | .plugins.entries."talk-voice".enabled = false
  | .plugins |= del(.deny)
  | .browser = (.browser // {})
  | .browser.enabled = true
  | .browser.defaultProfile = "openclaw"
  | .browser.headless = true
  | .browser.noSandbox = true
  | .browser.executablePath = $browser_executable_path
  | .browser.cdpPortRangeStart = 18800
  | .browser.remoteCdpTimeoutMs = 3000
  | .browser.remoteCdpHandshakeTimeoutMs = 6000
  | .browser.snapshotDefaults = ((.browser.snapshotDefaults // {}) | .mode = "efficient")
  | .browser.profiles = {
      "openclaw": {
        "cdpPort": 18800,
        "color": "#00AA00"
      }
    }
  | .browser |= del(.ssrfPolicy)
  | .tools = (.tools // {})
  | .tools.alsoAllow = (((.tools.alsoAllow // []) + ["browser"]) | unique)
  | .skills = (.skills // {})
  | .skills.entries = (.skills.entries // {})
  | .skills.entries.discord.enabled = false
  | .skills.entries.gemini.enabled = false
  | .skills.entries.slack.enabled = false
  | .skills.entries."voice-call".enabled = false
  | .skills.entries.trello.enabled = false
  | .skills.entries."node-connect".enabled = false
  | .skills.entries.notion.enabled = false
  ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

log "Pulling ${IMAGE}"
docker pull "$IMAGE"

log "Validating config"
docker run --rm --entrypoint openclaw --user root --hostname "$CONTAINER_NAME" \
  -e "OPENCLAW_PLUGIN_STAGE_DIR=${PLUGIN_STAGE_DIR}" \
  -v "${CONFIG_DIR}:/root/.openclaw:rw" \
  -v "${PLAYWRIGHT_DIR}:/root/.openclaw/ms-playwright:rw" \
  -v "${BROWSER_DIR}:/root/.openclaw/browser:rw" \
  -v "${WORKSPACE_DIR}:/home/node/clawd:rw" \
  -v "${PROJECTS_DIR}:/projects:rw" \
  -v "${HOMEBREW_DIR}:/home/linuxbrew/.linuxbrew:rw" \
  -v "${PLUGIN_STAGE_HOST_DIR}:${PLUGIN_STAGE_DIR}:rw" \
  "$IMAGE" \
  config validate

log "Replacing Docker container ${CONTAINER_NAME}"
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  docker inspect "$CONTAINER_NAME" > "${TEMPLATE_DIR}/my-${CONTAINER_NAME}.inspect-${stamp}.json" || true
  docker rm -f "$CONTAINER_NAME"
fi

env_args=(
  -e "OPENCLAW_PLUGIN_STAGE_DIR=${PLUGIN_STAGE_DIR}"
)

for v in OPENAI_API_KEY TELEGRAM_BOT_TOKEN ANTHROPIC_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY COPILOT_GITHUB_TOKEN; do
  if [ -n "${!v:-}" ]; then
    env_args+=(-e "${v}=${!v}")
  fi
done

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  --user root \
  --restart unless-stopped \
  --network bridge \
  --label net.unraid.docker.managed=dockerman \
  --label net.unraid.docker.webui='http://[IP]:[PORT:18789]/' \
  --label net.unraid.docker.icon='https://raw.githubusercontent.com/selfhosters/unRAID-CA-templates/master/templates/img/openclaw.png' \
  --health-cmd='curl -fsS http://127.0.0.1:18789/healthz >/dev/null' \
  --health-interval=30s \
  --health-timeout=10s \
  --health-start-period=5m \
  --health-retries=10 \
  -p "${HOST_PORT}:18789" \
  "${env_args[@]}" \
  -v "${CONFIG_DIR}:/root/.openclaw:rw" \
  -v "${PLAYWRIGHT_DIR}:/root/.openclaw/ms-playwright:rw" \
  -v "${BROWSER_DIR}:/root/.openclaw/browser:rw" \
  -v "${WORKSPACE_DIR}:/home/node/clawd:rw" \
  -v "${PROJECTS_DIR}:/projects:rw" \
  -v "${HOMEBREW_DIR}:/home/linuxbrew/.linuxbrew:rw" \
  -v "${PLUGIN_STAGE_HOST_DIR}:${PLUGIN_STAGE_DIR}:rw" \
  "$IMAGE" \
  sh -c 'unset OPENCLAW_GATEWAY_TOKEN; for v in OPENAI_API_KEY TELEGRAM_BOT_TOKEN ANTHROPIC_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY COPILOT_GITHUB_TOKEN; do eval "[ -n \"\${$v:-}\" ]" || unset "$v"; done; mkdir -p /root/.openclaw /home/linuxbrew /tmp/openclaw-plugin-stage; exec node dist/index.js gateway --bind lan'

log "Waiting for health"
for i in $(seq 1 40); do
  status="$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || true)"
  health="$(docker inspect "$CONTAINER_NAME" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"
  echo "try=${i} status=${status} health=${health}"
  if [ "$health" = "healthy" ]; then
    break
  fi
  sleep 10
done

log "Final status"
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
docker stats "$CONTAINER_NAME" --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} PIDS={{.PIDs}}'

cat <<EOF

Next steps:
  1. Open the UI through Cloudflare Access: ${PUBLIC_ORIGIN}
  2. Authenticate Codex subscription:
     docker exec -it ${CONTAINER_NAME} openclaw models auth login --provider openai-codex
  3. Set the model:
     docker exec -it ${CONTAINER_NAME} openclaw models set ${MODEL_REF}
  4. Check:
     docker exec -it ${CONTAINER_NAME} openclaw models status --plain

Updates:
  Update OpenClaw from the Unraid Docker UI by pulling ${IMAGE}.
  The internal OpenClaw update banner is disabled because Docker installs are not git checkouts.
EOF
