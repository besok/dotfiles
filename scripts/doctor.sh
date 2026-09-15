#!/usr/bin/env bash
#
# Health check for a `./install.sh` setup: confirms the binaries are
# present, the config symlinks point back into this repo, the git
# diff/merge config is wired, and the shell rc files carry the aliases and
# functions install.sh appended. Prints PASS/FAIL per check and exits
# non-zero if anything is missing.
#
# Usage: doctor   (installed to ~/.local/bin/doctor by install.sh)

set -uo pipefail

# Resolve the real location of this script even when invoked through the
# ~/.local/bin/doctor symlink (install.sh symlinks with an absolute target,
# so `readlink` yields the repo path; fall back to $0 when run directly).
self="${BASH_SOURCE[0]}"
resolved="$(readlink -f "$self" 2>/dev/null || readlink "$self" 2>/dev/null || echo "$self")"
DOTFILES_DIR="$(cd "$(dirname "$resolved")/.." && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

pass=0; fail=0; warn=0
ok()   { pass=$((pass+1)); printf '  PASS  %s\n' "$*"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$*"; }
note() { warn=$((warn+1)); printf '  WARN  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s\n' "$*"; }

section "binaries"
for b in hx alacritty zellij git; do
  have "$b" && ok "$b" || bad "$b (not on PATH)"
done
for b in zed cargo uv python3 rust-analyzer lldb-dap glow entr bear yazi \
         ripgrep fzf zoxide bat eza jq delta direnv starship lazygit \
         difft mergiraf; do
  have "$b" && ok "$b" || note "$b (not found — optional until you need it)"
done

section "config symlinks"
link() {
  local l="$1"
  if [[ -L "$l" ]]; then
    local t; t="$(readlink "$l")"
    if [[ "$t" == "$DOTFILES_DIR"* ]]; then ok "$l"
    else bad "$l -> $t (not in $DOTFILES_DIR)"; fi
  elif [[ -e "$l" ]]; then
    bad "$l is a regular file, not a symlink into this repo"
  else
    bad "$l missing"
  fi
}
link "$CONFIG_HOME/helix/config.toml"
link "$CONFIG_HOME/helix/languages.toml"
link "$CONFIG_HOME/alacritty/alacritty.toml"
link "$CONFIG_HOME/zellij/config.kdl"
link "$CONFIG_HOME/zellij/layouts/dev.kdl"
link "$CONFIG_HOME/zellij/layouts/rsdev.kdl"
link "$CONFIG_HOME/zellij/layouts/pydev.kdl"
link "$CONFIG_HOME/starship.toml"
link "$CONFIG_HOME/zed/settings.json"
link "$CONFIG_HOME/yazi/yazi.toml"
link "$CONFIG_HOME/lazygit/config.yml"
link "$LOCAL_BIN/mdp"
link "$LOCAL_BIN/llm"
link "$LOCAL_BIN/doctor"

# shell.toml is generated (not symlinked) by install.sh — just check it exists
[[ -f "$CONFIG_HOME/alacritty/shell.toml" ]] \
  && ok "$CONFIG_HOME/alacritty/shell.toml" \
  || note "$CONFIG_HOME/alacritty/shell.toml missing (run install.sh to regenerate)"

section "git config"
cfg() {
  local v; v="$(git config --global --get "$1" 2>/dev/null || true)"
  [[ -n "$v" ]] && ok "$1 = $v" || bad "$1 not set"
}
cfg diff.external
cfg core.pager
cfg rerere.enabled
cfg merge.conflictStyle
cfg merge.mergiraf.driver
grep -Fq 'merge=mergiraf' "$CONFIG_HOME/git/attributes" 2>/dev/null \
  && ok "git attributes: merge=mergiraf" \
  || bad "~/.config/git/attributes missing 'merge=mergiraf'"

section "shell rc"
rcs=()
[[ -f "$HOME/.bashrc" ]] && rcs+=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc"  ]] && rcs+=("$HOME/.zshrc")
[[ ${#rcs[@]} -eq 0 ]] && bad "no ~/.bashrc or ~/.zshrc found"

needle() {
  local desc="$1" pat="$2" rc found=""
  for rc in "${rcs[@]}"; do
    grep -qE "$pat" "$rc" && found=1 && break
  done
  [[ -n "$found" ]] && ok "$desc" || bad "$desc"
}
needle "~/.local/bin on PATH"  'dotfiles: ~/.local/bin'
needle "EDITOR=hx"             'export EDITOR="hx"'
needle "bash-completion sourced" 'dotfiles: bash-completion'
needle "starship init"         'starship init'
needle "zoxide init"           'zoxide init'
needle "dev alias"             '^alias dev='
needle "rsdev alias"           '^alias rsdev='
needle "pydev alias"           '^alias pydev='
needle "cargo aliases"         '^alias cb='
needle "uv aliases"            '^alias pvenv='
needle "y() yazi wrapper"      '^# y\(\): launch yazi'
needle "rt() test picker"      '^# rt\(\): fuzzy-pick'
needle "ptk() test picker"     '^# ptk\(\): fuzzy-pick'
needle "pm() entrypoint"       '^# pm\(\): run a Python'

section "fonts"
if have fc-list; then
  fc-list 2>/dev/null | grep -qi "JetBrainsMono" \
    && ok "JetBrainsMono Nerd Font installed" \
    || note "JetBrainsMono Nerd Font not in font cache"
else
  note "fc-list not found — can't verify fonts"
fi

printf '\n== summary: %d pass, %d fail, %d warn\n' "$pass" "$fail" "$warn"
[[ "$fail" -eq 0 ]] && printf 'All checks passed.\n'
exit "$fail"
