#!/bin/bash
set -e

# Run post-install setup (idempotent, fast)
# Run from /opt to avoid uv scanning /workspace for config files
(cd /opt && uv run --no-project post_install.py)

exec "$@"
