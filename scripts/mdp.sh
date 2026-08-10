#!/usr/bin/env bash
# Live markdown preview in the terminal: re-renders on every save.
# Usage: mdp README.md
set -euo pipefail

file="${1:?usage: mdp <file.md>}"

command -v glow >/dev/null 2>&1 || { echo "Install glow: https://github.com/charmbracelet/glow"; exit 1; }
command -v entr >/dev/null 2>&1 || { echo "Install entr (apt/brew/pacman install entr)"; exit 1; }

echo "$file" | entr -c glow -p -s light "$file"
