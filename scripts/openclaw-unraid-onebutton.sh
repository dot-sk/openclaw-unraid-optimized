#!/usr/bin/env bash
set -Eeuo pipefail

# One-button OpenClaw setup for Unraid.
# Safe to rerun. It recreates only the Docker container, not appdata.

CONTAINER_NAME="${CONTAINER_NAME:-OpenClaw}"
IMAGE="${IMAGE:-ghcr.io/openclaw/openclaw:latest}"
APPDATA_ROOT="${APPDATA_ROOT:-/mnt/cache/appdata/openclaw}"
HOST_PORT="${HOST_PORT:-18789}"
MODEL_ID="${MODEL_ID:-gpt-5.5}"
MODEL_REF="${MODEL_REF:-openai/${MODEL_ID}}"
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
      "memory-core": { "enabled": false },
      "browser": { "enabled": false },
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
      "browser",
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
      "litellm",
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
  }
}
JSON
fi

log "Applying OpenClaw config optimizations"
stamp="$(date +%Y%m%d-%H%M%S)"
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-onebutton-${stamp}"

jq --arg model_id "$MODEL_ID" --arg model_ref "$MODEL_REF" '
  .agents = (.agents // {})
  | .agents.defaults = (.agents.defaults // {})
  | .agents.defaults.model = (.agents.defaults.model // {})
  | .agents.defaults.model.primary = $model_ref
  | .agents.defaults.memorySearch = (.agents.defaults.memorySearch // {})
  | .agents.defaults.memorySearch.provider = "openai"
  | .agents.defaults.memorySearch.model = "text-embedding-3-small"
  | .agents.defaults.memorySearch.enabled = false
  | .models = (.models // {})
  | .models.providers = (.models.providers // {})
  | .models.providers.openai = (.models.providers.openai // {})
  | .models.providers.openai.baseUrl = "https://api.openai.com/v1"
  | .models.providers.openai.models = (
      ((.models.providers.openai.models // []) | map(select(.id != $model_id)))
      + [{
          "id": $model_id,
          "name": ("GPT " + $model_id),
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }]
    )
  | .models.providers."openai-codex" = (.models.providers."openai-codex" // {})
  | .models.providers."openai-codex".baseUrl = "https://chatgpt.com"
  | .models.providers."openai-codex".models = (
      ((.models.providers."openai-codex".models // []) | map(select(.id != $model_id)))
      + [{
          "id": $model_id,
          "name": ("GPT Codex " + $model_id),
          "cost": {
            "input": 0,
            "output": 0,
            "cacheRead": 0,
            "cacheWrite": 0
          }
        }]
    )
  | .plugins = (.plugins // {})
  | .plugins.entries = (.plugins.entries // {})
  | .plugins.entries."device-pair".enabled = true
  | .plugins.entries."document-extract".enabled = true
  | .plugins.entries.openai.enabled = true
  | .plugins.entries.telegram.enabled = true
  | .plugins.entries."web-readability".enabled = true
  | .plugins.entries."memory-core".enabled = false
  | .plugins.entries.browser.enabled = false
  | .plugins.entries.acpx.enabled = false
  | .plugins.entries.bonjour.enabled = false
  | .plugins.entries."phone-control".enabled = false
  | .plugins.entries."talk-voice".enabled = false
  | .plugins.deny = (
      ((.plugins.deny // []) + [
        "acpx","active-memory","alibaba","amazon-bedrock","amazon-bedrock-mantle",
        "anthropic","anthropic-vertex","arcee","azure-speech","bluebubbles",
        "bonjour","brave","browser","byteplus","cerebras","chutes",
        "cloudflare-ai-gateway","codex","comfy","copilot-proxy","deepgram",
        "deepseek","diagnostics-otel","diagnostics-prometheus","diffs","discord",
        "duckduckgo","elevenlabs","exa","fal","feishu","firecrawl","fireworks",
        "github-copilot","google","google-meet","googlechat","gradium","groq",
        "huggingface","imessage","inworld","irc","kilocode","kimi","line",
        "litellm","llm-task","lmstudio","lobster","matrix","mattermost",
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
    )
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

log "Validating config"
docker run --rm --entrypoint openclaw --user root --hostname "$CONTAINER_NAME" \
  -e "OPENCLAW_PLUGIN_STAGE_DIR=${PLUGIN_STAGE_DIR}" \
  -v "${CONFIG_DIR}:/root/.openclaw:rw" \
  -v "${WORKSPACE_DIR}:/home/node/clawd:rw" \
  -v "${PROJECTS_DIR}:/projects:rw" \
  -v "${HOMEBREW_DIR}:/home/linuxbrew/.linuxbrew:rw" \
  "$IMAGE" \
  config validate

log "Replacing Docker container ${CONTAINER_NAME}"
mkdir -p "$BACKUP_DIR"
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

If using Cloudflare Tunnel, point it to:
  http://<UNRAID_IP>:${HOST_PORT}
EOF
