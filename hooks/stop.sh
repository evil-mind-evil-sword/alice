#!/bin/bash
# Stop hook wrapper
source "${CLAUDE_PLUGIN_ROOT}/hooks/ensure-binary.sh"
ensure_idle_binary || exit 1
exec "$IDLE_BIN" stop
