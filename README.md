# Claude Code sbx template

A personal [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) (`sbx`) template for Claude
Code. One image (`template/Dockerfile`) extending `docker/sandbox-templates:claude-code-docker`.

## Claude settings

`template/claude-settings.json` is applied by a `claude` PATH wrapper that injects
`--settings` at launch. File-based managed settings don't work here: the org's
server-managed settings make claude ignore `/etc/claude-code/managed-settings.json`.

## Build & run

```bash
docker build -t claude-sbx
docker image save /claude-sbx -o claude-sbx.tar
sbx template load claude-sbx.tar
```

## Host-side runtime

Default-deny outbound and secrets aren't baked into the image:

```bash
sbx policy allow network "api.etherscan.io:443,<rpc-host>:443,ntfy.sh:443"
sbx secret set <sandbox> github -t "$(gh auth token)"
```

Secrets used: `ETHERSCAN_API_KEY`, RPC `*_URL`, `NTFY_TOPIC`.
