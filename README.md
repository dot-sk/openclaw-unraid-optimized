# OpenClaw for Unraid

This repo contains a practical Unraid setup for running OpenClaw in Docker.

It is built for this shape of setup:

- OpenClaw runs on an Unraid server.
- Access from the internet goes through Cloudflare Tunnel and Cloudflare Access.
- OpenClaw trusts Cloudflare Access instead of showing its own login page.
- Small config stays durable on `/mnt/user`.
- Heavy runtime files stay on `/mnt/cache` so startup does not get stuck on Unraid `shfs`.

No secrets are stored in this repo.

## Quick Install

Run this on your Unraid server as `root`:

```bash
curl -fsSL https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main/install.sh | bash
```

This installs:

- an Unraid Docker template;
- a User Script called `OpenClaw Optimized Setup`.

Then open Unraid:

```text
Plugins -> User Scripts -> OpenClaw Optimized Setup -> Run Script
```

To install and run in one command:

```bash
curl -fsSL https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main/install.sh | RUN_NOW=1 bash
```

## What It Creates

The setup script creates these paths:

```text
/mnt/user/appdata/openclaw/config                 -> /root/.openclaw
/mnt/cache/appdata/openclaw/root/ms-playwright   -> /root/.openclaw/ms-playwright
/mnt/cache/appdata/openclaw/root/browser         -> /root/.openclaw/browser
/mnt/cache/appdata/openclaw/workspace            -> /home/node/clawd
/mnt/cache/appdata/openclaw/projects             -> /projects
/mnt/cache/appdata/openclaw/homebrew             -> /home/linuxbrew/.linuxbrew
/mnt/cache/appdata/openclaw/plugin-stage         -> /tmp/openclaw-plugin-stage
```

The important part is the split:

- `/mnt/user/appdata/openclaw/config` keeps small durable state: config, OAuth sessions, identity, device pairing.
- `/mnt/cache/appdata/openclaw/...` keeps heavy runtime state: Chromium, browser profile, workspace, Homebrew, plugin staging.

This avoids putting lots of small-file runtime work through Unraid `shfs`.

## Authentication

The template is intended to be used behind Cloudflare Access.

Example public URL:

```text
https://claw.example.com
```

Default OpenClaw auth config:

```json
{
  "gateway": {
    "auth": {
      "mode": "trusted-proxy",
      "trustedProxy": {
        "userHeader": "cf-access-authenticated-user-email"
      }
    }
  }
}
```

That header is Cloudflare Access-specific. If you switch to another auth proxy later, change `TRUSTED_PROXY_HEADER` and rerun the setup script.

Do not expose OpenClaw directly to the internet without an auth proxy in front of it.

## Secrets

Put secrets into the Unraid Docker UI as environment variables.

Supported optional variables:

```text
OPENAI_API_KEY
TELEGRAM_BOT_TOKEN
ANTHROPIC_API_KEY
GEMINI_API_KEY
OPENROUTER_API_KEY
COPILOT_GITHUB_TOKEN
```

The template does not use `OPENCLAW_GATEWAY_TOKEN`. Cloudflare Access is the authentication layer.

Blank optional provider variables are unset before OpenClaw starts. This avoids confusing OpenClaw with empty provider tokens.

## Codex Subscription Login

For ChatGPT/Codex subscription access, use `openai-codex`, not the normal OpenAI API-key provider.

Run inside the container:

```bash
docker exec -it OpenClaw openclaw models auth login --provider openai-codex
docker exec -it OpenClaw openclaw models set openai-codex/gpt-5.5
docker exec -it OpenClaw openclaw models status --plain
```

The model must start with:

```text
openai-codex/
```

If it starts with `openai/`, that is the API billing path, not the subscription path.

## Embeddings

Codex subscription auth does not provide embeddings.

If you want embeddings or memory/search features, set `OPENAI_API_KEY` in the Unraid Docker UI.

Default embedding model:

```text
text-embedding-3-small
```

Memory search is disabled by default to avoid surprise API usage:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "enabled": false
      }
    }
  }
}
```

Enable it later only if you want that feature.

## Enabled Plugins

The setup keeps a small useful plugin set:

```text
browser
device-pair
document-extract
openai
telegram
web-readability
```

These local or unused skills are disabled by default:

```text
discord
gemini
node-connect
notion
slack
trello
voice-call
```

Other providers like Anthropic, Gemini, OpenRouter, and Copilot are not deleted. They can be enabled later if you add their tokens.

## Browser Tools

Browser tools run inside the main OpenClaw container.

The managed browser profile is:

```text
openclaw
```

Chromium is stored on cache:

```text
/mnt/cache/appdata/openclaw/root/ms-playwright
```

The browser profile is also stored on cache:

```text
/mnt/cache/appdata/openclaw/root/browser
```

First browser startup can take 3-4 minutes. The Docker healthcheck allows for that:

```text
interval: 30s
timeout: 10s
start period: 5m
retries: 10
```

Useful checks:

```bash
docker exec OpenClaw openclaw browser status
docker exec OpenClaw openclaw browser open https://example.com
docker exec OpenClaw openclaw browser snapshot --efficient
```

Sites like LinkedIn or Glassdoor may still require manual login, CAPTCHA, or 2FA.

## Updates

This is a Docker install.

Update OpenClaw from the Unraid Docker UI by pulling:

```text
ghcr.io/openclaw/openclaw:latest
```

Do not use the update button inside the OpenClaw UI for this install. That updater is for git/npm installs, not Docker images.

The setup disables the internal startup update hint:

```json
{
  "update": {
    "checkOnStart": false,
    "auto": {
      "enabled": false
    }
  }
}
```

## Checks

Validate config:

```bash
docker exec OpenClaw openclaw config validate
```

Check the container:

```bash
docker ps --filter name=OpenClaw
docker stats OpenClaw --no-stream
```

Show recent logs:

```bash
docker logs --tail 100 OpenClaw
```

List enabled plugins:

```bash
docker exec OpenClaw openclaw plugins list --enabled
```

## Useful Overrides

You can override defaults when running the setup script:

```bash
PUBLIC_ORIGIN=https://claw.example.com \
TRUSTED_PROXIES=192.168.1.10 \
MODEL_REF=openai-codex/gpt-5.5 \
bash /boot/config/plugins/user.scripts/scripts/OpenClaw\ Optimized\ Setup/script
```

For another reverse proxy, change:

```bash
TRUSTED_PROXY_HEADER=x-authenticated-user
```

Use the header your proxy actually sends after it authenticates the user.
