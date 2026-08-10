#!/usr/bin/env bash
# Fired by Alacritty on every terminal bell (BEL / \a).
# Many CLIs — including LLM/agent CLIs like opencode — ring the bell
# when a task finishes or they're waiting on your input.
TITLE="Terminal"
MSG="Needs your input"

if command -v notify-send >/dev/null 2>&1; then
    notify-send "$TITLE" "$MSG" -t 4000
elif command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier -title "$TITLE" -message "$MSG"
elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$MSG\" with title \"$TITLE\""
fi
