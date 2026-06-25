# Claude Code sbx template

A personal [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) (`sbx`) template for Claude
Code. One image (`template/Dockerfile`) extending `docker/sandbox-templates:claude-code-docker`.

## Build & run

```bash
docker build -t <registry>/claude-sbx:v1 --push template/
sbx run --template <registry>/claude-sbx:v1 claude
```

For a local image, `sbx template load` it first:

```bash
docker image save <registry>/claude-sbx:v1 -o claude-sbx.tar
sbx template load claude-sbx.tar
```

## Host-side runtime

Default-deny outbound and secrets aren't baked into the image:

```bash
sbx policy allow network "api.etherscan.io:443,<rpc-host>:443,ntfy.sh:443"
sbx secret set <sandbox> github -t "$(gh auth token)"
```

Secrets used: `ETHERSCAN_API_KEY`, RPC `*_URL`, `NTFY_TOPIC`.
