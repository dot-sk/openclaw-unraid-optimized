# OpenClaw for Unraid

This is a simple Unraid setup for running OpenClaw in Docker.

It is meant for people who want OpenClaw to run reliably on Unraid, especially when using it through a reverse proxy or Cloudflare Tunnel.

This repo does not include any secrets, tokens, API keys, OAuth sessions, or personal OpenClaw data.

## What This Fixes

The default OpenClaw setup can work, but on Unraid it may feel slow or unreliable.

Common problems:

- OpenClaw appdata is mounted through `/mnt/user`, which uses Unraid `shfs`.
- Plugin dependencies are staged inside appdata.
- Too many plugins are enabled by default.

This setup makes a few practical changes:

- Uses `/mnt/cache/appdata/openclaw/...` instead of `/mnt/user/...`.
- Stages plugin runtime files in `/tmp/openclaw-plugin-stage`.
- Keeps only a small useful plugin set enabled.
- Uses `openai-codex/gpt-5.5` as the default model.
- Runs Chromium as a separate Browserless sidecar container for browser tools.

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

If you want to install and run everything immediately:

```bash
curl -fsSL https://raw.githubusercontent.com/dot-sk/openclaw-unraid-optimized/main/install.sh | RUN_NOW=1 bash
```

## What the Script Does

The setup script:

- creates OpenClaw folders under `/mnt/cache/appdata/openclaw`;
- creates a minimal `openclaw.json` if one does not exist;
- applies the optimized plugin list;
- enables the OpenClaw browser tool through a Browserless sidecar;
- creates a private Docker network for OpenClaw and Browserless;
- sets `OPENCLAW_PLUGIN_STAGE_DIR=/tmp/openclaw-plugin-stage`;
- runs `openclaw config validate`;
- recreates the `OpenClaw` and `OpenClawBrowserless` Docker containers;
- sets restart policy to `unless-stopped`;
- waits until OpenClaw is healthy.

The script does not delete your appdata.

If the containers already exist, the script recreates them, but keeps the data in `/mnt/cache/appdata/openclaw`.

## Docker Volumes

Use `/mnt/cache`, not `/mnt/user`.

Recommended mounts:

```text
/mnt/cache/appdata/openclaw/config    -> /root/.openclaw
/mnt/cache/appdata/openclaw/workspace -> /home/node/clawd
/mnt/cache/appdata/openclaw/projects  -> /projects
/mnt/cache/appdata/openclaw/homebrew  -> /home/linuxbrew/.linuxbrew
```

Why this matters:

`/mnt/user` goes through Unraid `shfs`. That can be slow for Node, SQLite, and many small files. OpenClaw does all of those things during startup.

## Codex Subscription Login

After the container is running, log in to Codex:

```bash
docker exec -it OpenClaw openclaw models auth login --provider openai-codex
docker exec -it OpenClaw openclaw models set openai-codex/gpt-5.5
docker exec -it OpenClaw openclaw models status --plain
```

Use this model ref:

```text
openai-codex/...
```

The auth provider is also:

```text
openai-codex
```

Do not use the normal `openai` API-key provider for the main chat model if your goal is ChatGPT/Codex subscription access.

## OpenAI API Key

You do not need a normal OpenAI API key for Codex subscription login.

You do need a normal OpenAI API key if you want OpenAI embeddings.

That is separate from Codex subscription auth.

For embeddings, use:

```text
text-embedding-3-small
```

This is used for memory/search features, not for the main chat model.

To provide the API key:

```bash
OPENAI_API_KEY=sk-... bash scripts/openclaw-unraid-onebutton.sh
```

Do not commit API keys to GitHub.

By default this setup keeps memory indexing disabled. That avoids unexpected API usage. You can enable it later if you want OpenClaw memory/search.

## Enabled Plugins

By default this setup keeps only a small useful set:

```text
device-pair
document-extract
openai
telegram
web-readability
browser
```

Heavy or unused default plugins are disabled.

You can enable more later from the OpenClaw UI or by editing `openclaw.json`.

## Browser Support

Browser tools need a real Chromium runtime. The OpenClaw image is small and may not include all browser system libraries, so this setup runs Chromium in a separate sidecar container:

```text
OpenClawBrowserless
```

The script creates a private Docker network:

```text
openclaw-browser-net
```

Default addresses:

```text
OpenClaw            -> 172.28.238.2
OpenClawBrowserless -> 172.28.238.10
```

OpenClaw connects to Browserless through:

```text
ws://172.28.238.10:3000
```

This is meant for the agent to read pages through a browser. For sites like LinkedIn or Glassdoor, you may still need to log in manually or pass CAPTCHA/2FA yourself. Do not expose Browserless directly to the public internet.

## Check That It Works

Validate config:

```bash
docker exec OpenClaw openclaw config validate
```

Check the container:

```bash
docker ps --filter name=OpenClaw
docker ps --filter name=OpenClawBrowserless
docker stats OpenClaw --no-stream
```

List enabled plugins:

```bash
docker exec OpenClaw openclaw plugins list --enabled
```

Show recent logs:

```bash
docker logs --tail 100 OpenClaw
docker logs --tail 100 OpenClawBrowserless
```

Check that OpenClaw can reach Browserless:

```bash
docker exec OpenClaw node -e "fetch('http://172.28.238.10:3000/json/version').then(r=>r.json()).then(j=>console.log(j.Browser, j.webSocketDebuggerUrl))"
```

## Cloudflare Tunnel

If you use Cloudflare Tunnel, point it to:

```text
http://<UNRAID_IP>:18789
```

Example:

```text
http://192.168.86.80:18789
```

## Security Notes

This setup follows the upstream OpenClaw Unraid template and runs the container as `root` inside Docker.

The container is still limited:

- it is not privileged;
- it does not mount the Docker socket;
- it does not mount the whole host filesystem;
- it only gets the OpenClaw appdata, workspace, projects, and homebrew folders.
- Browserless is kept on a private Docker network and should not be published without access control.

Do not publish these files or folders:

- OpenClaw credentials;
- OAuth state;
- Telegram bot tokens;
- OpenAI API keys;
- your real `openclaw.json` if it contains private data;
- `agents`, `identity`, or `devices` from your live appdata.

## Files

```text
install.sh
scripts/openclaw-unraid-onebutton.sh
templates/my-OpenClaw-Optimized.xml
```

`install.sh` installs the template and User Script on Unraid.

`scripts/openclaw-unraid-onebutton.sh` does the full setup.

`templates/my-OpenClaw-Optimized.xml` can be imported manually in the Unraid Docker UI.
