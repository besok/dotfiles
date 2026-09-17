#!/usr/bin/env bash
#
# Reverses everything install.sh did:
#   - removes config symlinks that point back into this repo
#   - strips the aliases/functions it appended to ~/.bashrc / ~/.zshrc
#   - reverts the git config it set (diff/merge/pager/rerere)
# It only removes entries it recognizes, so your own additions are left
# alone. Safe to re-run.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

echo "==> Uninstalling dotfiles from: $DOTFILES_DIR"

# Portable in-place sed (no .bak files) across GNU (Linux) and BSD (macOS).
sed_i() {
    if sed --version >/dev/null 2>&1; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# -------------------------------------------------------------------
# 1. Remove symlinks that point back into this repo
# -------------------------------------------------------------------
echo "==> Removing config symlinks ..."
rm_link() {
    local l="$1"
    if [[ -L "$l" ]]; then
        local t; t="$(readlink "$l")"
        if [[ "$t" == "$DOTFILES_DIR"* ]]; then
            rm -f "$l" && echo "   removed $l"
        else
            echo "   skip    $l (points elsewhere: $t)"
        fi
    elif [[ -e "$l" ]]; then
        echo "   skip    $l (regular file, not a symlink)"
    fi
}

rm_link "$CONFIG_HOME/helix/config.toml"
rm_link "$CONFIG_HOME/helix/languages.toml"
rm_link "$CONFIG_HOME/alacritty/alacritty.toml"
rm_link "$CONFIG_HOME/zellij/config.kdl"
rm_link "$CONFIG_HOME/zellij/layouts/dev.kdl"
rm_link "$CONFIG_HOME/zellij/layouts/rsdev.kdl"
rm_link "$CONFIG_HOME/zellij/layouts/pydev.kdl"
rm_link "$CONFIG_HOME/starship.toml"
rm_link "$CONFIG_HOME/zed/settings.json"
rm_link "$CONFIG_HOME/zed/tasks.json"
rm_link "$CONFIG_HOME/zed/debug.json"
rm_link "$CONFIG_HOME/zed/keymap.json"
rm_link "$CONFIG_HOME/yazi/yazi.toml"
rm_link "$CONFIG_HOME/lazygit/config.yml"
rm_link "$LOCAL_BIN/mdp"
rm_link "$LOCAL_BIN/llm"
rm_link "$LOCAL_BIN/doctor"
rm_link "$LOCAL_BIN/prun"

# ~/.local/bin/zed: install.sh links the Zed.app CLI here on macOS when the
# app was installed outside Homebrew. Only remove it if it's that link.
if [[ -L "$LOCAL_BIN/zed" && "$(readlink "$LOCAL_BIN/zed")" == /Applications/Zed.app/* ]]; then
    rm -f "$LOCAL_BIN/zed" && echo "   removed $LOCAL_BIN/zed"
fi

# alacritty/shell.toml is a generated file, not a symlink — remove it too.
rm -f "$CONFIG_HOME/alacritty/shell.toml" && echo "   removed $CONFIG_HOME/alacritty/shell.toml"

# -------------------------------------------------------------------
# 2. Strip injected aliases/functions from shell rc files
# -------------------------------------------------------------------
echo "==> Removing aliases/functions from shell rc files ..."
rcs=()
[[ -f "$HOME/.bashrc" ]] && rcs+=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc"  ]] && rcs+=("$HOME/.zshrc")

strip_line() {
    local file="$1" line="$2"
    [[ -f "$file" ]] || return 0
    if grep -Fqx -- "$line" "$file"; then
        grep -Fvx -- "$line" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        echo "   removed  $line"
    fi
}

# Aliases (exact lines appended by install.sh).
aliases=(
    "alias dev='zellij --layout dev'"
    "alias rsdev='zellij --layout rsdev'"
    "alias pydev='zellij --layout pydev'"
    "alias dev='zellij attach --create dev options --default-layout dev'"
    "alias rsdev='zellij attach --create rsdev options --default-layout rsdev'"
    "alias pydev='zellij attach --create pydev options --default-layout pydev'"
    "alias kill_devs='for s in dev rsdev pydev; do zellij delete-session --force \"\$s\" 2>/dev/null; done; zellij delete-all-sessions --yes 2>/dev/null'"
    "alias cb='cargo build --quiet --message-format=short'"
    "alias cc='cargo check --quiet --message-format=short'"
    "alias ccl='cargo clippy --quiet --message-format=short'"
    "alias cw='cargo watch -x \"check --message-format=short\"'"
    "alias cbg='bacon'"
    "alias ct='cargo nextest run'"
    "alias cf='cargo fmt'"
    "alias cu='cargo update'"
    "alias cr='cargo run'"
    "alias pvenv='uv venv'"
    "alias pd='uv sync'"
    "alias pa='uv add'"
    "alias prm='uv remove'"
    "alias pu='uv lock --upgrade'"
    "alias pf='ruff format .'"
    "alias pl='ruff check .'"
    "alias pcx='ruff check --fix .'"
    "alias pt='uv run pytest'"
    "alias pw='uv run ptw .'"
)

for rc in "${rcs[@]}"; do
    for a in "${aliases[@]}"; do
        strip_line "$rc" "$a"
    done
    strip_line "$rc" 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac  # dotfiles: ~/.local/bin (zed, uv, pipx, mdp/llm/doctor)'
    strip_line "$rc" 'export EDITOR="hx"'
    strip_line "$rc" 'export VISUAL="hx"'
    strip_line "$rc" '[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"  # dotfiles: bash-completion (make/ssh/git tab completion)'
    strip_line "$rc" '[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion  # dotfiles: bash-completion (make/ssh/git tab completion)'
    strip_line "$rc" 'eval "$(starship init bash)"'
    strip_line "$rc" 'eval "$(starship init zsh)"'
    strip_line "$rc" 'eval "$(zoxide init bash)"'
    strip_line "$rc" 'eval "$(zoxide init zsh)"'
done

# Multi-line functions appended by install.sh (remove comment through `}`).
strip_range() {
    local file="$1" start="$2"
    [[ -f "$file" ]] || return 0
    if grep -Fq "$start" "$file"; then
        sed_i "/^${start}/,/^}$/d" "$file"
        echo "   stripped $start ... from $file"
    fi
}

for rc in "${rcs[@]}"; do
    strip_range "$rc" '# y(): launch yazi'
    strip_range "$rc" '# rt(): fuzzy-pick'
    strip_range "$rc" '# ptk(): fuzzy-pick'
    # pyproj block: newer installs close it with `# pyproj: end`; older ones
    # (ptk() last) end at the first bare `}`, which strip_range handles.
    if grep -Fxq "# pyproj: end" "$rc" 2>/dev/null; then
        sed_i '/^# pyproj: Poetry\/uv project tooling/,/^# pyproj: end$/d' "$rc"
        echo "   stripped # pyproj: Poetry/uv project tooling ... from $rc"
    else
        strip_range "$rc" '# pyproj: Poetry/uv project tooling'
    fi
    strip_range "$rc" '# pm(): run a Python'
done

# macOS: install.sh chains ~/.bash_profile -> ~/.bashrc.
if [[ -f "$HOME/.bash_profile" ]]; then
    strip_line "$HOME/.bash_profile" '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
fi

# -------------------------------------------------------------------
# 3. Revert git config set by install.sh
# -------------------------------------------------------------------
echo "==> Reverting git config ..."
git_unset() {
    if git config --global --get "$1" >/dev/null 2>&1; then
        git config --global --unset "$1" && echo "   unset $1"
    fi
}
git_unset diff.external
git_unset alias.dlog
git_unset alias.dshow
git_unset core.pager
git_unset interactive.diffFilter
git_unset rerere.enabled
git_unset merge.conflictStyle
git_unset merge.mergiraf.name
git_unset merge.mergiraf.driver

if [[ -f "$CONFIG_HOME/git/attributes" ]]; then
    grep -Fvx '* merge=mergiraf' "$CONFIG_HOME/git/attributes" > "$CONFIG_HOME/git/attributes.tmp" \
        && mv "$CONFIG_HOME/git/attributes.tmp" "$CONFIG_HOME/git/attributes"
    echo "   removed 'merge=mergiraf' from $CONFIG_HOME/git/attributes"
fi

echo ""
echo "==> Done. The installed packages themselves are left in place;"
echo "    remove them with your package manager if you no longer need them."
