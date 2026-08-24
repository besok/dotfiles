#!/usr/bin/env bash
#
# Installs Helix, Alacritty, Zellij, toolchains/LSPs/DAPs for
# Python, Rust, Zig, C++, and C, plus a set of everyday CLI utilities
# (search, navigation, git, system, prompt) — then symlinks the
# configs in this repo into the right XDG locations and sets shell
# aliases.
#
# Supports: macOS (Homebrew), Debian/Ubuntu (apt), Arch (pacman).
# Re-run any time; it's safe/idempotent where the package manager allows it.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

echo "==> Detected dotfiles at: $DOTFILES_DIR"
echo "==> Config target: $CONFIG_HOME"

# Remove leftover dev script executable if present from earlier setups
rm -f "$LOCAL_BIN/dev" "$DOTFILES_DIR/scripts/dev.sh"

# -------------------------------------------------------------------
# 1. Detect platform / package manager
# -------------------------------------------------------------------
OS="$(uname -s)"
PKG=""

if [[ "$OS" == "Darwin" ]]; then
    PKG="brew"
    command -v brew >/dev/null 2>&1 || { echo "Homebrew not found. Install it from https://brew.sh first."; exit 1; }
elif [[ -f /etc/debian_version ]]; then
    PKG="apt"
elif [[ -f /etc/arch-release ]]; then
    PKG="pacman"
else
    echo "Unsupported OS. Please install packages manually — see README.md."
    exit 1
fi

echo "==> Using package manager: $PKG"

install_pkgs() {
    case "$PKG" in
        brew)   brew install "$@" ;;
        apt)    sudo apt update && sudo apt install -y "$@" ;;
        pacman) sudo pacman -Sy --needed --noconfirm "$@" ;;
    esac
}

ensure_rust() {
    if ! command -v cargo >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    source "$HOME/.cargo/env"
}

# -------------------------------------------------------------------
# 2. Core apps: helix, alacritty, zellij
# -------------------------------------------------------------------
echo "==> Installing helix, alacritty, zellij..."
case "$PKG" in
    brew)   install_pkgs helix alacritty zellij ;;
    apt)    install_pkgs alacritty
            # Prefer snap for Helix — the maveonair PPA has lagged noticeably
            # behind upstream releases (confirmed: PPA stuck at 24.7 while
            # snap ships 25.07+). Snap also makes future updates a one-liner.
            if command -v snap >/dev/null 2>&1; then
                # Remove a stale apt/PPA-installed helix so it doesn't shadow
                # the snap binary on PATH
                if dpkg -l helix >/dev/null 2>&1; then
                    echo "   Removing older apt-installed helix in favor of snap..."
                    sudo apt remove -y helix || true
                fi
                if snap list helix >/dev/null 2>&1; then
                    echo "   Refreshing helix snap to the latest version..."
                    sudo snap refresh helix
                else
                    sudo snap install helix --classic || sudo snap install helix
                fi
                if ! command -v hx >/dev/null 2>&1 && command -v helix.hx >/dev/null 2>&1; then
                    sudo snap alias helix.hx hx
                fi
            elif [[ -f /etc/os-release ]] && grep -qi '^ID=ubuntu' /etc/os-release; then
                echo "!! snapd not found — falling back to the maveonair PPA,"
                echo "   which can lag behind upstream. Install snapd for a"
                echo "   more current build: sudo apt install snapd"
                command -v add-apt-repository >/dev/null 2>&1 || install_pkgs software-properties-common
                sudo add-apt-repository -y ppa:maveonair/helix-editor
                sudo apt update
                sudo apt install -y helix
            else
                echo "!! No snap and not Ubuntu. Grab a release from:"
                echo "   https://github.com/helix-editor/helix/releases"
            fi
            if ! command -v zellij >/dev/null 2>&1; then
                ensure_rust
                cargo install --locked zellij || {
                    echo "!! zellij build failed. Try 'rustup update' then re-run,"
                    echo "   or grab a release from https://github.com/zellij-org/zellij/releases"
                }
            fi ;;
    pacman) install_pkgs helix alacritty zellij ;;
esac

# -------------------------------------------------------------------
# 3. Nerd Fonts (JetBrains Mono)
# -------------------------------------------------------------------
echo "==> Installing JetBrainsMono Nerd Font..."
case "$PKG" in
    brew)
        brew install --cask font-jetbrains-mono-nerd-font || true
        ;;
    pacman)
        install_pkgs ttf-jetbrains-mono-nerd
        ;;
    apt)
        install_pkgs curl unzip fontconfig
        FONT_DIR="$HOME/.local/share/fonts"
        if ! fc-list | grep -qi "JetBrainsMono"; then
            mkdir -p "$FONT_DIR"
            echo "   Downloading JetBrainsMono Nerd Font release..."
            curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
            unzip -o /tmp/JetBrainsMono.zip -d "$FONT_DIR/JetBrainsMonoNerdFont"
            rm /tmp/JetBrainsMono.zip
            fc-cache -fv
        else
            echo "   JetBrainsMono Nerd Font already present in font cache."
        fi
        ;;
esac

# -------------------------------------------------------------------
# 4. Common build tooling + markdown-preview helpers
# -------------------------------------------------------------------
echo "==> Installing common build tools + glow/entr..."
case "$PKG" in
    brew)   install_pkgs git cmake llvm glow entr ;;
    apt)    install_pkgs git cmake build-essential clang clangd clang-tidy \
                          lldb entr
            if ! command -v glow >/dev/null 2>&1; then
                echo "   Installing glow via Charm's apt repo..."
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y glow
            fi ;;
    pacman) install_pkgs git cmake base-devel clang lldb glow entr ;;
esac

if ! command -v lldb-dap >/dev/null 2>&1; then
    if command -v lldb-vscode >/dev/null 2>&1; then
        mkdir -p "$LOCAL_BIN"
        ln -sf "$(command -v lldb-vscode)" "$LOCAL_BIN/lldb-dap"
        echo "   Symlinked lldb-vscode -> lldb-dap in $LOCAL_BIN (make sure it's on PATH)"
    else
        echo "!! lldb-dap not found. Install your platform's LLVM/lldb package (>=17 ships lldb-dap directly)."
    fi
fi

# -------------------------------------------------------------------
# 5. Python: interpreter + pyright + ruff
# -------------------------------------------------------------------
echo "==> Setting up Python tooling..."
case "$PKG" in
    brew)   install_pkgs python pipx ;;
    apt)    install_pkgs python3 python3-pip pipx ;;
    pacman) install_pkgs python python-pipx ;;
esac
pipx ensurepath || true
pipx install pyright  --force
pipx install ruff     --force

# uv: the cargo-equivalent for Python — manages virtualenvs, dependencies,
# and `uv run` in one fast tool (Rust-based). Installed via its official
# installer, which drops the binary in ~/.local/bin.
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# pytest + pytest-watch (ptw): test runner and watch-mode for `pt`/`pw`/
# `ptk`. Installed globally as a fallback; prefer adding them as project
# dev-deps via `uv add --dev pytest` for per-project environments.
pipx install pytest        --force || echo "!! pytest install failed."
pipx install pytest-watch  --force || echo "!! pytest-watch install failed."

# -------------------------------------------------------------------
# 6. Rust: rustup toolchain + rust-analyzer + clippy + cargo subcommands
# -------------------------------------------------------------------
echo "==> Setting up Rust tooling..."
ensure_rust
rustup component add rust-analyzer clippy rustfmt

# Test running + fast incremental feedback
cargo install cargo-watch   --locked || echo "!! cargo-watch install failed — you can retry manually later."
cargo install cargo-nextest --locked || echo "!! cargo-nextest install failed — 'test' tab falls back to 'cargo test'."

# bacon: background compiler with a compact, always-on diagnostics panel.
# This is the thing most people actually want for "just show me errors,
# compactly, live" — nicer than piping cargo-watch output through grep.
cargo install bacon --locked || echo "!! bacon install failed — you can retry manually later."

# cargo-edit: adds `cargo add` / `cargo rm` / `cargo upgrade` for managing
# Cargo.toml dependencies from the CLI instead of hand-editing.
cargo install cargo-edit --locked || echo "!! cargo-edit install failed — you can retry manually later."

# cargo-outdated: reports dependencies with newer versions available.
cargo install cargo-outdated --locked || echo "!! cargo-outdated install failed — you can retry manually later."

# cargo-audit: scans Cargo.lock against the RustSec advisory database for
# known security vulnerabilities.
cargo install cargo-audit --locked || echo "!! cargo-audit install failed — you can retry manually later."

# cargo-expand: pretty-prints the output of macro expansion — handy for
# debugging derive macros and proc-macros.
cargo install cargo-expand --locked || echo "!! cargo-expand install failed — you can retry manually later."

# -------------------------------------------------------------------
# 6b. yazi: terminal file manager (tree/columns view, previews) — handy
#     for bulk file ops (rename/move/copy/delete) that Helix's built-in
#     `space e` explorer deliberately doesn't do.
# -------------------------------------------------------------------
echo "==> Installing yazi..."
case "$PKG" in
    brew)   install_pkgs yazi ;;
    pacman) install_pkgs yazi ;;
    apt)
        # No apt package. Note: yazi-fm/yazi-cli can't be built directly
        # from crates.io via `cargo install` due to a cargo build-script
        # limitation — yazi ships a small installer wrapper crate,
        # `yazi-build`, that has to be used instead.
        ensure_rust
        cargo install --force --locked yazi-build || echo "!! yazi install failed — you can retry manually later."
        install_pkgs ffmpegthumbnailer poppler-utils unar file || true
        ;;
esac

# -------------------------------------------------------------------
# 7. Zig: compiler (includes fmt) + zls language server
# -------------------------------------------------------------------
echo "==> Setting up Zig tooling..."
case "$PKG" in
    brew)   install_pkgs zig ;;
    apt)    echo "!! Debian/Ubuntu apt's zig package is usually stale."
            echo "   Grab the latest from https://ziglang.org/download/ and put it on PATH." ;;
    pacman) install_pkgs zig ;;
esac
echo "!! zls (Zig LSP) has no universal package — build it from source, matched to your zig version:"
echo "   git clone https://github.com/zigtools/zls && cd zls && zig build -Doptimize=ReleaseSafe"
echo "   then put zig-out/bin/zls on your PATH."

# -------------------------------------------------------------------
# 8. C / C++: clangd + lldb-dap already installed above
# -------------------------------------------------------------------
echo "==> C/C++ tooling uses clangd + lldb-dap (installed above)."
echo "   Tip: generate compile_commands.json per project with 'bear -- make'"
echo "   or CMake's -DCMAKE_EXPORT_COMPILE_COMMANDS=ON so clangd has full context."

# -------------------------------------------------------------------
# 9. Extra CLI utilities: search, navigation, git, system, prompt
# -------------------------------------------------------------------
echo "==> Installing extra CLI utilities..."
case "$PKG" in
    brew)
        install_pkgs ripgrep fd fzf zoxide bat eza jq git-delta \
                      btop dust procs gh lazygit just direnv \
                      hyperfine starship tealdeer resvg
        ;;
    pacman)
        install_pkgs ripgrep fd fzf zoxide bat eza jq git-delta \
                      btop dust procs github-cli lazygit just direnv \
                      hyperfine starship tealdeer resvg
        ;;
    apt)
        # Packages that install cleanly under their expected name/binary
        install_pkgs ripgrep fzf jq direnv hyperfine

        # fd and bat ship under different binary names on Debian/Ubuntu
        install_pkgs fd-find bat
        mkdir -p "$LOCAL_BIN"
        command -v fd  >/dev/null 2>&1 || ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
        command -v bat >/dev/null 2>&1 || ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"

        # zoxide / btop / git-delta: in repos on recent releases, otherwise
        # fall back to their official install scripts / cargo
        install_pkgs zoxide btop git-delta || true
        if ! command -v zoxide >/dev/null 2>&1; then
            curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
        fi
        if ! command -v delta >/dev/null 2>&1; then
            ensure_rust
            cargo install git-delta --locked || echo "!! git-delta install failed."
        fi

        # eza: usually not in the default Ubuntu/Debian repos — add the
        # maintainer's apt repo
        if ! command -v eza >/dev/null 2>&1; then
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
                | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
                | sudo tee /etc/apt/sources.list.d/gierens.list
            sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            sudo apt update && sudo apt install -y eza
        fi

        # gh CLI: needs GitHub's own apt repo
        if ! command -v gh >/dev/null 2>&1; then
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo gpg --dearmor -o /etc/apt/keyrings/githubcli.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list
            sudo apt update && sudo apt install -y gh
        fi

        # dust, procs, just, tealdeer: rarely packaged for apt — cargo install
        ensure_rust
        for entry in "dust:du-dust" "procs:procs" "just:just" "tldr:tealdeer"; do
            bin="${entry%%:*}"; crate="${entry##*:}"
            command -v "$bin" >/dev/null 2>&1 || cargo install "$crate" --locked || echo "!! $crate install failed."
        done

        # resvg: SVG rasterizer CLI (no apt package) — cargo install
        command -v resvg >/dev/null 2>&1 || cargo install resvg --locked || echo "!! resvg install failed."

        # lazygit: no apt package — grab the latest release binary
        if ! command -v lazygit >/dev/null 2>&1; then
            LG_VERSION="$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
                | grep -Po '"tag_name": *"v\K[^"]*')"
            curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VERSION}/lazygit_${LG_VERSION}_Linux_x86_64.tar.gz"
            tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
            install /tmp/lazygit "$LOCAL_BIN/lazygit"
            rm -f /tmp/lazygit.tar.gz /tmp/lazygit
        fi

        # starship: official install script
        command -v starship >/dev/null 2>&1 || curl -sS https://starship.rs/install.sh | sh -s -- -y
        ;;
esac

# Wire up delta as git's diff/pager, and zoxide + starship shell hooks
if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
fi

add_line() {
    local rc_file="$1" line="$2"
    if [[ -f "$rc_file" ]] && ! grep -Fq "$line" "$rc_file"; then
        echo "$line" >> "$rc_file"
    fi
}

if command -v zoxide >/dev/null 2>&1; then
    add_line "$HOME/.bashrc" 'eval "$(zoxide init bash)"'
    add_line "$HOME/.zshrc"  'eval "$(zoxide init zsh)"'
fi
if command -v starship >/dev/null 2>&1; then
    add_line "$HOME/.bashrc" 'eval "$(starship init bash)"'
    add_line "$HOME/.zshrc"  'eval "$(starship init zsh)"'
fi

# Set Helix as the default $EDITOR/$VISUAL — respected by yazi's built-in
# "open in editor" action, git commit/rebase, crontab -e, and anything
# else that shells out to an editor rather than using per-tool config.
add_line "$HOME/.bashrc" 'export EDITOR="hx"'
add_line "$HOME/.bashrc" 'export VISUAL="hx"'
add_line "$HOME/.zshrc"  'export EDITOR="hx"'
add_line "$HOME/.zshrc"  'export VISUAL="hx"'

# -------------------------------------------------------------------
# 10. Symlink configs + helper scripts + shell aliases
# -------------------------------------------------------------------
echo "==> Symlinking configs into $CONFIG_HOME ..."
mkdir -p "$CONFIG_HOME/helix" "$CONFIG_HOME/alacritty" "$CONFIG_HOME/zellij/layouts" "$LOCAL_BIN"

ln -sf "$DOTFILES_DIR/helix/config.toml"        "$CONFIG_HOME/helix/config.toml"
ln -sf "$DOTFILES_DIR/helix/languages.toml"     "$CONFIG_HOME/helix/languages.toml"
ln -sf "$DOTFILES_DIR/alacritty/alacritty.toml" "$CONFIG_HOME/alacritty/alacritty.toml"
ln -sf "$DOTFILES_DIR/zellij/config.kdl"        "$CONFIG_HOME/zellij/config.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/dev.kdl"   "$CONFIG_HOME/zellij/layouts/dev.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/rsdev.kdl" "$CONFIG_HOME/zellij/layouts/rsdev.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/pydev.kdl" "$CONFIG_HOME/zellij/layouts/pydev.kdl"
ln -sf "$DOTFILES_DIR/starship/starship.toml"   "$CONFIG_HOME/starship.toml"
ln -sf "$DOTFILES_DIR/scripts/mdp.sh"           "$LOCAL_BIN/mdp"

# yazi: route Enter on text/code files to Helix instead of yazi's default
# opener (block=true hands the terminal fully to hx instead of trying to
# background it, which would otherwise leave Helix in a broken state)
if command -v yazi >/dev/null 2>&1 || command -v ya >/dev/null 2>&1; then
    mkdir -p "$CONFIG_HOME/yazi"
    ln -sf "$DOTFILES_DIR/yazi/yazi.toml" "$CONFIG_HOME/yazi/yazi.toml"
fi

# lazygit: route diffs through delta in side-by-side mode (lazygit has
# no native side-by-side toggle of its own)
if command -v lazygit >/dev/null 2>&1; then
    mkdir -p "$CONFIG_HOME/lazygit"
    ln -sf "$DOTFILES_DIR/lazygit/config.yml" "$CONFIG_HOME/lazygit/config.yml"
fi

if [[ -d "$DOTFILES_DIR/scripts" ]]; then
    chmod +x "$DOTFILES_DIR"/scripts/*.sh
fi

# Add zellij layout aliases to rc files
add_alias() {
    local rc_file="$1" alias_cmd="$2"
    if [[ -f "$rc_file" ]]; then
        if ! grep -Fq "$alias_cmd" "$rc_file"; then
            echo "==> Adding $alias_cmd to $rc_file"
            echo "$alias_cmd" >> "$rc_file"
        fi
    fi
}

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    add_alias "$rc" "alias dev='zellij --layout dev'"
    add_alias "$rc" "alias rsdev='zellij --layout rsdev'"
    add_alias "$rc" "alias pydev='zellij --layout pydev'"
done

# -------------------------------------------------------------------
# Rust / cargo aliases — compact-output build loop
# -------------------------------------------------------------------
# cb   - cargo build,  compact one-line diagnostics, no progress spam
# cc   - cargo check,  same but skips codegen (fastest feedback loop)
# ccl  - cargo clippy, compact diagnostics
# cw   - cargo-watch running `cargo check` on every save, compact format
# cbg  - bacon, the live always-on compact diagnostics panel
# ct   - run the full test suite via cargo-nextest
# cf   - cargo fmt
# cu   - cargo update (bump Cargo.lock within semver constraints)
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    add_alias "$rc" "alias cb='cargo build --quiet --message-format=short'"
    add_alias "$rc" "alias cc='cargo check --quiet --message-format=short'"
    add_alias "$rc" "alias ccl='cargo clippy --quiet --message-format=short'"
    add_alias "$rc" "alias cw='cargo watch -x \"check --message-format=short\"'"
    add_alias "$rc" "alias cbg='bacon'"
    add_alias "$rc" "alias ct='cargo nextest run'"
    add_alias "$rc" "alias cf='cargo fmt'"
    add_alias "$rc" "alias cu='cargo update'"
done

# -------------------------------------------------------------------
# Python / uv aliases — the cargo-equivalent workflow
# -------------------------------------------------------------------
# pvenv - create a .venv virtualenv in the current project (uv venv)
# pd    - sync/install the project's dependencies + env (uv sync)
# pa    - add a dependency (uv add <pkg>), mirrors `cargo add`
# prm   - remove a dependency (uv remove <pkg>), mirrors `cargo rm`
# pu    - upgrade locked dependencies within constraints (uv lock --upgrade)
# pf    - format code (ruff format)
# pl    - lint (ruff check)
# pcx   - lint with auto-fixes applied (ruff check --fix)
# pt    - run the full test suite (uv run pytest)
# pw    - run tests on every save (uv run ptw)
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    add_alias "$rc" "alias pvenv='uv venv'"
    add_alias "$rc" "alias pd='uv sync'"
    add_alias "$rc" "alias pa='uv add'"
    add_alias "$rc" "alias prm='uv remove'"
    add_alias "$rc" "alias pu='uv lock --upgrade'"
    add_alias "$rc" "alias pf='ruff format .'"
    add_alias "$rc" "alias pl='ruff check .'"
    add_alias "$rc" "alias pcx='ruff check --fix .'"
    add_alias "$rc" "alias pt='uv run pytest'"
    add_alias "$rc" "alias pw='uv run ptw'"
done

# y(): launch yazi, and if you cd'd somewhere inside it, land your shell
# there on quit (the standard wrapper recommended by yazi's own docs —
# without it, exiting yazi drops you back where you started).
add_yazi_function() {
    local rc_file="$1"
    local marker="# y(): launch yazi, cd to wherever you navigated to on quit"
    if [[ -f "$rc_file" ]]; then
        if grep -Fq "$marker" "$rc_file"; then
            sed -i.bak '/^# y(): launch yazi/,/^}$/d' "$rc_file"
        fi
        echo "==> Adding y() yazi wrapper to $rc_file"
        cat >> "$rc_file" <<'EOF'

# y(): launch yazi, cd to wherever you navigated to on quit
y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
        cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
EOF
    fi
}

add_yazi_function "$HOME/.bashrc"
add_yazi_function "$HOME/.zshrc"

# rt(): fuzzy-pick a single test and run it with cargo-nextest.
# Uses `cargo test -- --list` as the source of test names (nextest's own
# `list` output is grouped/indented per binary and isn't a clean match
# string) — any argument passed to rt pre-fills the fzf search query,
# e.g. `rt any_type`.
add_function() {
    local rc_file="$1"
    local marker="# rt(): fuzzy-pick and run a single test"
    if [[ -f "$rc_file" ]]; then
        # Remove an older/broken version of the function if present, so
        # re-running install.sh actually fixes it instead of leaving a
        # stale duplicate.
        if grep -Fq "$marker" "$rc_file"; then
            sed -i.bak '/^# rt(): fuzzy-pick/,/^}$/d' "$rc_file"
        fi
        echo "==> Adding rt() test-picker function to $rc_file"
        cat >> "$rc_file" <<'EOF'

# rt(): fuzzy-pick and run a single test (cargo-nextest + fzf)
rt() {
    local test
    test=$(cargo test --tests -- --list 2>/dev/null \
        | grep ': test$' \
        | sed 's/: test$//' \
        | fzf --height 40% --query "$*") || return
    cargo nextest run "$test"
}
EOF
    fi
}

add_function "$HOME/.bashrc"
add_function "$HOME/.zshrc"

# ptk(): fuzzy-pick a single pytest test and run it (uv run pytest + fzf).
# Any argument pre-fills the fzf search query, e.g. `ptk my_test`.
add_ptk_function() {
    local rc_file="$1"
    local marker="# ptk(): fuzzy-pick and run a single test"
    if [[ -f "$rc_file" ]]; then
        if grep -Fq "$marker" "$rc_file"; then
            sed -i.bak '/^# ptk(): fuzzy-pick/,/^}$/d' "$rc_file"
        fi
        echo "==> Adding ptk() test-picker function to $rc_file"
        cat >> "$rc_file" <<'EOF'

# ptk(): fuzzy-pick and run a single pytest test (uv run pytest + fzf)
ptk() {
    local test
    test=$(uv run pytest --collect-only -q 2>/dev/null \
        | grep '::' \
        | fzf --height 40% --query "$*") || return
    uv run pytest "$test"
}
EOF
    fi
}

add_ptk_function "$HOME/.bashrc"
add_ptk_function "$HOME/.zshrc"

echo ""
echo "==> Done. Run 'source ~/.bashrc' or 'source ~/.zshrc' to apply."
