#!/usr/bin/env bash
set -e

# Start remote-control in the background
echo "Starting claude --remote-control ..."
claude --remote-control --dangerously-skip-permissions &

# Start the HTTP API server in the foreground
echo "Starting API server ..."
exec node /home/claude/server.js
