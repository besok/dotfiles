#!/usr/bin/env bash
#
# Installs Helix, Alacritty, Zellij, and toolchains/LSPs/DAPs for
# Python, Rust, Zig, C++, and C — then symlinks the configs in
# this repo into the right XDG locations and sets shell aliases.
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
            if ! command -v hx >/dev/null 2>&1; then
                if [[ -f /etc/os-release ]] && grep -qi '^ID=ubuntu' /etc/os-release; then
                    command -v add-apt-repository >/dev/null 2>&1 || install_pkgs software-properties-common
                    sudo add-apt-repository -y ppa:maveonair/helix-editor
                    sudo apt update
                    sudo apt install -y helix
                elif command -v snap >/dev/null 2>&1; then
                    sudo snap install helix --classic || sudo snap install helix
                    if ! command -v hx >/dev/null 2>&1 && command -v helix.hx >/dev/null 2>&1; then
                        sudo snap alias helix.hx hx
                    fi
                else
                    echo "!! Not Ubuntu and no snap found. Grab a release from:"
                    echo "   https://github.com/helix-editor/helix/releases"
                fi
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
# 4. Common build tooling + notification/markdown-preview helpers
# -------------------------------------------------------------------
echo "==> Installing common build tools + notify-send/glow/entr..."
case "$PKG" in
    brew)   install_pkgs git cmake llvm glow entr
            echo "   (terminal-notifier is optional: brew install terminal-notifier — osascript works without it)" ;;
    apt)    install_pkgs git cmake build-essential clang clangd clang-tidy \
                          lldb libnotify-bin entr
            if ! command -v glow >/dev/null 2>&1; then
                echo "   Installing glow via Charm's apt repo..."
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y glow
            fi ;;
    pacman) install_pkgs git cmake base-devel clang lldb glow entr libnotify ;;
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
# 6. Rust: rustup toolchain + rust-analyzer + clippy + cargo-watch
# -------------------------------------------------------------------
echo "==> Setting up Rust tooling..."
ensure_rust
rustup component add rust-analyzer clippy rustfmt
cargo install cargo-watch --locked || echo "!! cargo-watch install failed — you can retry manually later."

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
# 9. Symlink configs + helper scripts + shell aliases
# -------------------------------------------------------------------
echo "==> Symlinking configs into $CONFIG_HOME ..."
mkdir -p "$CONFIG_HOME/helix" "$CONFIG_HOME/alacritty" "$CONFIG_HOME/zellij/layouts" "$LOCAL_BIN"

ln -sf "$DOTFILES_DIR/helix/config.toml"        "$CONFIG_HOME/helix/config.toml"
ln -sf "$DOTFILES_DIR/helix/languages.toml"     "$CONFIG_HOME/helix/languages.toml"
ln -sf "$DOTFILES_DIR/alacritty/alacritty.toml" "$CONFIG_HOME/alacritty/alacritty.toml"
ln -sf "$DOTFILES_DIR/alacritty/notify-bell.sh" "$CONFIG_HOME/alacritty/notify-bell.sh"
ln -sf "$DOTFILES_DIR/zellij/config.kdl"        "$CONFIG_HOME/zellij/config.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/dev.kdl"   "$CONFIG_HOME/zellij/layouts/dev.kdl"
ln -sf "$DOTFILES_DIR/scripts/mdp.sh"           "$LOCAL_BIN/mdp"

chmod +x "$DOTFILES_DIR/alacritty/notify-bell.sh"
if [[ -d "$DOTFILES_DIR/scripts" ]]; then
    chmod +x "$DOTFILES_DIR"/scripts/*.sh
fi

# Add alias dev='zellij --layout dev' to rc files
add_alias() {
    local rc_file="$1"
    local alias_cmd="alias dev='zellij --layout dev'"
    if [[ -f "$rc_file" ]]; then
        if ! grep -Fq "$alias_cmd" "$rc_file"; then
            echo "==> Adding alias dev='zellij --layout dev' to $rc_file"
            echo "$alias_cmd" >> "$rc_file"
        fi
    fi
}

add_alias "$HOME/.bashrc"
add_alias "$HOME/.zshrc"

echo ""
echo "==> Done. Run 'source ~/.bashrc' or 'source ~/.zshrc' to apply."