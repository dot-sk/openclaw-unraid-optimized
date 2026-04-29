#!/usr/bin/env bash
set -Eeuo pipefail

# One-button OpenClaw setup for Unraid.
# Safe to rerun. It recreates only the Docker container, not appdata.

CONTAINER_NAME="${CONTAINER_NAME:-OpenClaw}"
IMAGE="${IMAGE:-ghcr.io/openclaw/openclaw:latest}"
BROWSER_CONTAINER_NAME="${BROWSER_CONTAINER_NAME:-OpenClawBrowserless}"
BROWSER_IMAGE="${BROWSER_IMAGE:-ghcr.io/browserless/chromium:latest}"
BROWSER_NETWORK="${BROWSER_NETWORK:-openclaw-browser-net}"
BROWSER_SUBNET="${BROWSER_SUBNET:-172.28.238.0/24}"
BROWSER_IP="${BROWSER_IP:-172.28.238.10}"
BROWSER_CDP_URL="${BROWSER_CDP_URL:-ws://${BROWSER_IP}:3000}"
APPDATA_ROOT="${APPDATA_ROOT:-/mnt/cache/appdata/openclaw}"
HOST_PORT="${HOST_PORT:-18789}"
MODEL_ID="${MODEL_ID:-gpt-5.5}"
MODEL_REF="${MODEL_REF:-openai-codex/${MODEL_ID}}"
PLUGIN_STAGE_DIR="${PLUGIN_STAGE_DIR:-/tmp/openclaw-plugin-stage}"
BACKUP_DIR="${BACKUP_DIR:-/boot/config/plugins/dockerMan/templates-user}"

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
  die "/mnt/cache does not exist. Set APPDATA_ROOT=/path/to/cache/appdata/openclaw and rerun."
fi

CONFIG_DIR="${APPDATA_ROOT}/config"
WORKSPACE_DIR="${APPDATA_ROOT}/workspace"
PROJECTS_DIR="${APPDATA_ROOT}/projects"
HOMEBREW_DIR="${APPDATA_ROOT}/homebrew"

log "Creating appdata directories under ${APPDATA_ROOT}"
mkdir -p \
  "$CONFIG_DIR" \
  "$WORKSPACE_DIR" \
  "$PROJECTS_DIR" \
  "$HOMEBREW_DIR" \
  "$PLUGIN_STAGE_DIR"

CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

if [ ! -s "$CONFIG_FILE" ]; then
  log "Creating minimal OpenClaw config"
  umask 077
  cat > "$CONFIG_FILE" <<JSON
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "allowInsecureAuth": true
    },
    "auth": {
      "mode": "token"
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${MODEL_REF}"
      },
      "memorySearch": {
        "provider": "openai",
        "model": "text-embedding-3-small",
        "enabled": false
      }
    }
  },
  "plugins": {
    "entries": {
      "device-pair": { "enabled": true },
      "document-extract": { "enabled": true },
      "openai": { "enabled": true },
      "telegram": { "enabled": true },
      "web-readability": { "enabled": true },
      "browser": { "enabled": true },
      "memory-core": { "enabled": false },
      "acpx": { "enabled": false },
      "bonjour": { "enabled": false },
      "phone-control": { "enabled": false },
      "talk-voice": { "enabled": false }
    },
    "deny": [
      "acpx",
      "active-memory",
      "alibaba",
      "amazon-bedrock",
      "amazon-bedrock-mantle",
      "anthropic",
      "anthropic-vertex",
      "arcee",
      "azure-speech",
      "bluebubbles",
      "bonjour",
      "brave",
      "byteplus",
      "cerebras",
      "chutes",
      "cloudflare-ai-gateway",
      "codex",
      "comfy",
      "copilot-proxy",
      "deepgram",
      "deepseek",
      "diagnostics-otel",
      "diagnostics-prometheus",
      "diffs",
      "discord",
      "duckduckgo",
      "elevenlabs",
      "exa",
      "fal",
      "feishu",
      "firecrawl",
      "fireworks",
      "github-copilot",
      "google",
      "google-meet",
      "googlechat",
      "gradium",
      "groq",
      "huggingface",
      "imessage",
      "inworld",
      "irc",
      "kilocode",
      "kimi",
      "line",
      "llm-task",
      "lmstudio",
      "lobster",
      "matrix",
      "mattermost",
      "memory-core",
      "memory-lancedb",
      "memory-wiki",
      "microsoft",
      "microsoft-foundry",
      "migrate-claude",
      "migrate-hermes",
      "minimax",
      "mistral",
      "moonshot",
      "msteams",
      "nextcloud-talk",
      "nostr",
      "nvidia",
      "ollama",
      "open-prose",
      "opencode",
      "opencode-go",
      "openrouter",
      "openshell",
      "perplexity",
      "phone-control",
      "qianfan",
      "qqbot",
      "qwen",
      "runway",
      "searxng",
      "senseaudio",
      "sglang",
      "signal",
      "skill-workshop",
      "slack",
      "stepfun",
      "synology-chat",
      "synthetic",
      "talk-voice",
      "tavily",
      "tencent",
      "thread-ownership",
      "tlon",
      "together",
      "tokenjuice",
      "tts-local-cli",
      "twitch",
      "venice",
      "vercel-ai-gateway",
      "vllm",
      "voice-call",
      "volcengine",
      "voyage",
      "vydra",
      "webhooks",
      "whatsapp",
      "xai",
      "xiaomi",
      "zai",
      "zalo",
      "zalouser"
    ]
  },
  "browser": {
    "enabled": true,
    "defaultProfile": "browserless",
    "headless": true,
    "remoteCdpTimeoutMs": 3000,
    "remoteCdpHandshakeTimeoutMs": 6000,
    "snapshotDefaults": {
      "mode": "efficient"
    },
    "profiles": {
      "browserless": {
        "cdpUrl": "${BROWSER_CDP_URL}",
        "color": "#00AA00"
      }
    }
  },
  "tools": {
    "alsoAllow": [
      "browser"
    ]
  }
}
JSON
fi

log "Applying OpenClaw config optimizations"
stamp="$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-onebutton-${stamp}"

jq --arg model_id "$MODEL_ID" --arg model_ref "$MODEL_REF" --arg browser_cdp_url "$BROWSER_CDP_URL" '
  .agents = (.agents // {})
  | .agents.defaults = (.agents.defaults // {})
  | .agents.defaults.model = (.agents.defaults.model // {})
  | .agents.defaults.model.primary = $model_ref
  | .agents.defaults.memorySearch = (.agents.defaults.memorySearch // {})
  | .agents.defaults.memorySearch.provider = "openai"
  | .agents.defaults.memorySearch.model = "text-embedding-3-small"
  | .agents.defaults.memorySearch.enabled = false
  | .models = (.models // {})
  | .models.providers = ((.models.providers // {}) | del(."openai-codex"))
  | .plugins = (.plugins // {})
  | .plugins.entries = (.plugins.entries // {})
  | .plugins.entries."device-pair".enabled = true
  | .plugins.entries."document-extract".enabled = true
  | .plugins.entries.openai.enabled = true
  | .plugins.entries.telegram.enabled = true
  | .plugins.entries."web-readability".enabled = true
  | .plugins.entries.browser.enabled = true
  | .plugins.entries."memory-core".enabled = false
  | .plugins.entries.acpx.enabled = false
  | .plugins.entries.bonjour.enabled = false
  | .plugins.entries."phone-control".enabled = false
  | .plugins.entries."talk-voice".enabled = false
  | .plugins.deny = (
      ((.plugins.deny // []) + [
        "acpx","active-memory","alibaba","amazon-bedrock","amazon-bedrock-mantle",
        "anthropic","anthropic-vertex","arcee","azure-speech","bluebubbles",
        "bonjour","brave","byteplus","cerebras","chutes",
        "cloudflare-ai-gateway","codex","comfy","copilot-proxy","deepgram",
        "deepseek","diagnostics-otel","diagnostics-prometheus","diffs","discord",
        "duckduckgo","elevenlabs","exa","fal","feishu","firecrawl","fireworks",
        "github-copilot","google","google-meet","googlechat","gradium","groq",
        "huggingface","imessage","inworld","irc","kilocode","kimi","line",
        "llm-task","lmstudio","lobster","matrix","mattermost",
        "memory-core","memory-lancedb","memory-wiki","microsoft","microsoft-foundry",
        "migrate-claude","migrate-hermes","minimax","mistral","moonshot","msteams",
        "nextcloud-talk","nostr","nvidia","ollama","open-prose","opencode",
        "opencode-go","openrouter","openshell","perplexity","phone-control",
        "qianfan","qqbot","qwen","runway","searxng","senseaudio","sglang",
        "signal","skill-workshop","slack","stepfun","synology-chat","synthetic",
        "talk-voice","tavily","tencent","thread-ownership","tlon","together",
        "tokenjuice","tts-local-cli","twitch","venice","vercel-ai-gateway",
        "vllm","voice-call","volcengine","voyage","vydra","webhooks","whatsapp",
        "xai","xiaomi","zai","zalo","zalouser"
      ]) | unique
      | map(select(. != "browser"))
    )
  | .plugins.allow = (((.plugins.allow // []) + [
      "browser",
      "device-pair",
      "document-extract",
      "openai",
      "telegram",
      "web-readability"
    ]) | unique)
  | .browser = (.browser // {})
  | .browser.enabled = true
  | .browser.defaultProfile = "browserless"
  | .browser.headless = true
  | .browser.remoteCdpTimeoutMs = 3000
  | .browser.remoteCdpHandshakeTimeoutMs = 6000
  | .browser.snapshotDefaults = ((.browser.snapshotDefaults // {}) | .mode = "efficient")
  | .browser.profiles = (.browser.profiles // {})
  | .browser.profiles.browserless = {
      "cdpUrl": $browser_cdp_url,
      "color": "#00AA00"
    }
  | .tools = (.tools // {})
  | .tools.alsoAllow = (((.tools.alsoAllow // []) + ["browser"]) | unique)
  | .skills = (.skills // {})
  | .skills.entries = (.skills.entries // {})
  | .skills.entries.discord = (.skills.entries.discord // {})
  | .skills.entries.discord.enabled = false
  | .skills.entries.gemini = (.skills.entries.gemini // {})
  | .skills.entries.gemini.enabled = false
  | .skills.entries.slack = (.skills.entries.slack // {})
  | .skills.entries.slack.enabled = false
  | .skills.entries."voice-call" = (.skills.entries."voice-call" // {})
  | .skills.entries."voice-call".enabled = false
' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

log "Pulling ${IMAGE}"
docker pull "$IMAGE"

log "Pulling ${BROWSER_IMAGE}"
docker pull "$BROWSER_IMAGE"

log "Validating config"
docker run --rm --entrypoint openclaw --user root --hostname "$CONTAINER_NAME" \
  -e "OPENCLAW_PLUGIN_STAGE_DIR=${PLUGIN_STAGE_DIR}" \
  -v "${CONFIG_DIR}:/root/.openclaw:rw" \
  -v "${WORKSPACE_DIR}:/home/node/clawd:rw" \
  -v "${PROJECTS_DIR}:/projects:rw" \
  -v "${HOMEBREW_DIR}:/home/linuxbrew/.linuxbrew:rw" \
  "$IMAGE" \
  config validate

mkdir -p "$BACKUP_DIR"

log "Creating Docker network ${BROWSER_NETWORK}"
if ! docker network inspect "$BROWSER_NETWORK" >/dev/null 2>&1; then
  docker network create --subnet "$BROWSER_SUBNET" "$BROWSER_NETWORK"
fi

log "Replacing browser sidecar ${BROWSER_CONTAINER_NAME}"
if docker inspect "$BROWSER_CONTAINER_NAME" >/dev/null 2>&1; then
  docker inspect "$BROWSER_CONTAINER_NAME" > "${BACKUP_DIR}/my-${BROWSER_CONTAINER_NAME}.inspect-${stamp}.json" || true
  docker rm -f "$BROWSER_CONTAINER_NAME"
fi

docker run -d \
  --name "$BROWSER_CONTAINER_NAME" \
  --restart unless-stopped \
  --network "$BROWSER_NETWORK" \
  --ip "$BROWSER_IP" \
  -e "EXTERNAL=${BROWSER_CDP_URL}" \
  -e "CONCURRENT=2" \
  -e "QUEUED=5" \
  -e "TIMEOUT=300000" \
  "$BROWSER_IMAGE"

log "Replacing Docker container ${CONTAINER_NAME}"
if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  docker inspect "$CONTAINER_NAME" > "${BACKUP_DIR}/my-${CONTAINER_NAME}.inspect-${stamp}.json" || true
  docker rm -f "$CONTAINER_NAME"
fi

env_args=(-e "OPENCLAW_PLUGIN_STAGE_DIR=${PLUGIN_STAGE_DIR}")
if [ -n "${OPENAI_API_KEY:-}" ]; then
  env_args+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  --user root \
  --restart unless-stopped \
  --network bridge \
  -p "${HOST_PORT}:18789" \
  "${env_args[@]}" \
  -v "${CONFIG_DIR}:/root/.openclaw:rw" \
  -v "${WORKSPACE_DIR}:/home/node/clawd:rw" \
  -v "${PROJECTS_DIR}:/projects:rw" \
  -v "${HOMEBREW_DIR}:/home/linuxbrew/.linuxbrew:rw" \
  "$IMAGE" \
  sh -c "mkdir -p /root/.openclaw /home/linuxbrew ${PLUGIN_STAGE_DIR}; exec node dist/index.js gateway --bind lan"

docker network connect "$BROWSER_NETWORK" "$CONTAINER_NAME" >/dev/null 2>&1 || true

log "Waiting for health"
for i in $(seq 1 36); do
  status="$(docker inspect "$CONTAINER_NAME" --format '{{.State.Status}}' 2>/dev/null || true)"
  health="$(docker inspect "$CONTAINER_NAME" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"
  echo "try=${i} status=${status} health=${health}"
  if [ "$health" = "healthy" ]; then
    break
  fi
  sleep 5
done

log "Final status"
docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker ps --filter "name=${BROWSER_CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
docker network inspect "$BROWSER_NETWORK" --format '{{range .Containers}}{{println .Name .IPv4Address}}{{end}}'
docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
docker stats "$CONTAINER_NAME" --no-stream --format '{{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} PIDS={{.PIDs}}'

cat <<EOF

Next steps:
  1. Open the UI: http://<UNRAID_IP>:${HOST_PORT}/
  2. Authenticate Codex subscription:
     docker exec -it ${CONTAINER_NAME} openclaw models auth login --provider openai-codex
  3. Set the model:
     docker exec -it ${CONTAINER_NAME} openclaw models set ${MODEL_REF}
  4. Check:
     docker exec -it ${CONTAINER_NAME} openclaw models status --plain
  5. Check browser sidecar:
     docker exec ${CONTAINER_NAME} node -e "fetch('http://${BROWSER_IP}:3000/json/version').then(r=>r.json()).then(j=>console.log(j.Browser, j.webSocketDebuggerUrl))"

If using Cloudflare Tunnel, point it to:
  http://<UNRAID_IP>:${HOST_PORT}
EOF
