#!/usr/bin/env bash
#
# Launches whichever LLM assistant CLI this machine has, so the shared
# zellij layouts don't hardcode a tool that only exists on one machine.
#
# Pick order:
#   1. $LLM_CLI, if set (put `export LLM_CLI=opencode` in your local rc
#      to force one when several are installed)
#   2. first of: claude, opencode found on PATH

set -euo pipefail

candidates=(claude opencode)

if [[ -n "${LLM_CLI:-}" ]]; then
    if command -v "$LLM_CLI" >/dev/null 2>&1; then
        exec "$LLM_CLI" "$@"
    fi
    echo "llm: \$LLM_CLI is set to '$LLM_CLI' but it's not on PATH" >&2
    exit 127
fi

for cli in "${candidates[@]}"; do
    if command -v "$cli" >/dev/null 2>&1; then
        exec "$cli" "$@"
    fi
done

echo "llm: no LLM CLI found (looked for: ${candidates[*]})." >&2
echo "llm: install one, or set \$LLM_CLI to the command to use." >&2
exit 127
