#!/bin/bash
# Shared helper: ensure idle binary exists, download if missing

IDLE_BIN="${CLAUDE_PLUGIN_ROOT}/bin/idle"

ensure_idle_binary() {
    if [ -x "$IDLE_BIN" ]; then
        return 0
    fi

    mkdir -p "${CLAUDE_PLUGIN_ROOT}/bin"

    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64)  ARTIFACT="idle-macos-aarch64" ;;
        Darwin-x86_64) ARTIFACT="idle-macos-x86_64" ;;
        Linux-x86_64)  ARTIFACT="idle-linux-x86_64" ;;
        *) echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2; return 1 ;;
    esac

    URL="https://github.com/evil-mind-evil-sword/idle/releases/latest/download/${ARTIFACT}"
    curl -fsSL "$URL" -o "$IDLE_BIN" && chmod +x "$IDLE_BIN"
}
