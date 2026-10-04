#!/usr/bin/env bash
# SOCKS5 proxy into the VPC: SSH to node 1 tunnelled through an SSM session.
# No public IPs or open inbound ports are involved.
#   usage: tunnel.sh start|stop|status   (SOCKS_PORT, default 1080)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${SOCKS_PORT:-1080}"
KEY="${SSH_KEY:-$HOME/.ssh/dktest_ed25519}"
SOCK="${TMPDIR:-/tmp}/dktest-tunnel-$PORT.sock"
REGION="$(terraform -chdir="$ROOT/terraform" output -raw region)"
TARGET="$(terraform -chdir="$ROOT/terraform" output -json nodes | jq -r '.[0].instance_id')"

case "${1:-start}" in
  start)
    if ssh -S "$SOCK" -O check "ubuntu@$TARGET" 2>/dev/null; then
      echo "tunnel already running on 127.0.0.1:$PORT"; exit 0
    fi
    ssh -f -N -M -S "$SOCK" -D "127.0.0.1:$PORT" -i "$KEY" \
      -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
      -o StrictHostKeyChecking=accept-new \
      -o ProxyCommand="aws ssm start-session --region $REGION --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p" \
      "ubuntu@$TARGET"
    echo "SOCKS5 proxy on 127.0.0.1:$PORT -> VPC (via SSM to $TARGET)"
    ;;
  stop)
    ssh -S "$SOCK" -O exit "ubuntu@$TARGET" 2>/dev/null || true
    ;;
  status)
    ssh -S "$SOCK" -O check "ubuntu@$TARGET"
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2; exit 2
    ;;
esac
