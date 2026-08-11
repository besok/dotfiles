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

# -------------------------------------------------------------------
# 6. Rust: rustup toolchain + rust-analyzer + clippy + cargo-watch + cargo-nextest
# -------------------------------------------------------------------
echo "==> Setting up Rust tooling..."
ensure_rust
rustup component add rust-analyzer clippy rustfmt
cargo install cargo-watch --locked   || echo "!! cargo-watch install failed — you can retry manually later."
cargo install cargo-nextest --locked || echo "!! cargo-nextest install failed — 'test' tab falls back to 'cargo test'."

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
                      hyperfine starship tealdeer
        ;;
    pacman)
        install_pkgs ripgrep fd fzf zoxide bat eza jq git-delta \
                      btop dust procs github-cli lazygit just direnv \
                      hyperfine starship tealdeer
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
ln -sf "$DOTFILES_DIR/starship/starship.toml"   "$CONFIG_HOME/starship.toml"
ln -sf "$DOTFILES_DIR/scripts/mdp.sh"           "$LOCAL_BIN/mdp"

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
done

# rt(): fuzzy-pick a single test (via fzf) and run it with cargo-nextest,
# instead of typing the full test path by hand.
add_function() {
    local rc_file="$1"
    local marker="# rt(): fuzzy-pick and run a single test"
    if [[ -f "$rc_file" ]] && ! grep -Fq "$marker" "$rc_file"; then
        echo "==> Adding rt() test-picker function to $rc_file"
        cat >> "$rc_file" <<'EOF'

# rt(): fuzzy-pick and run a single test (cargo-nextest + fzf)
rt() {
    local test
    test=$(cargo nextest list 2>/dev/null | fzf --height 40%) || return
    cargo nextest run "$test"
}
EOF
    fi
}

add_function "$HOME/.bashrc"
add_function "$HOME/.zshrc"

echo ""
echo "==> Done. Run 'source ~/.bashrc' or 'source ~/.zshrc' to apply."
