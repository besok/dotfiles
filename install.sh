#!/usr/bin/env bash
#
# Installs Helix, Alacritty, Zellij, and toolchains/LSPs/DAPs for
# Python, Rust, Zig, C++, and C — then symlinks the configs in
# this repo into the right XDG locations.
#
# Supports: macOS (Homebrew), Debian/Ubuntu (apt), Arch (pacman).
# Re-run any time; it's safe/idempotent where the package manager allows it.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"

echo "==> Detected dotfiles at: $DOTFILES_DIR"
echo "==> Config target: $CONFIG_HOME"

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

# -------------------------------------------------------------------
# 2. Core apps: helix, alacritty, zellij
# -------------------------------------------------------------------
echo "==> Installing helix, alacritty, zellij..."
case "$PKG" in
    brew)   install_pkgs helix alacritty zellij ;;
    apt)    install_pkgs alacritty zellij
            sudo apt install -y helix || {
                echo "!! 'helix' not found via apt — grab a release from:"
                echo "   https://github.com/helix-editor/helix/releases"
            } ;;
    pacman) install_pkgs helix alacritty zellij ;;
esac

# -------------------------------------------------------------------
# 3. Common build tooling + notification/markdown-preview helpers
# -------------------------------------------------------------------
echo "==> Installing common build tools + notify-send/glow/entr..."
case "$PKG" in
    brew)   install_pkgs git cmake llvm glow entr
            echo "   (terminal-notifier is optional: brew install terminal-notifier — osascript works without it)" ;;
    apt)    install_pkgs git cmake build-essential clang clangd clang-tidy \
                          lldb libnotify-bin entr
            # glow isn't in default apt repos on most releases
            if ! command -v glow >/dev/null 2>&1; then
                echo "   Installing glow via Charm's apt repo..."
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y glow
            fi ;;
    pacman) install_pkgs git cmake base-devel clang lldb glow entr libnotify ;;
esac

# lldb-dap was called lldb-vscode on older LLVM — symlink whichever exists
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
# 4. Python: interpreter + pyright + ruff
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
# 5. Rust: rustup toolchain + rust-analyzer + clippy + cargo-watch
# -------------------------------------------------------------------
echo "==> Setting up Rust tooling..."
if ! command -v rustup >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi
rustup component add rust-analyzer clippy rustfmt
cargo install cargo-watch --locked || echo "!! cargo-watch install failed — you can retry manually later."

# -------------------------------------------------------------------
# 6. Zig: compiler (includes fmt) + zls language server
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
# 7. C / C++: clangd + lldb-dap already installed above
# -------------------------------------------------------------------
echo "==> C/C++ tooling uses clangd + lldb-dap (installed above)."
echo "   Tip: generate compile_commands.json per project with 'bear -- make'"
echo "   or CMake's -DCMAKE_EXPORT_COMPILE_COMMANDS=ON so clangd has full context."

# -------------------------------------------------------------------
# 8. Symlink configs + helper scripts
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
chmod +x "$DOTFILES_DIR/alacritty/notify-bell.sh" "$DOTFILES_DIR/scripts/mdp.sh" "$LOCAL_BIN/mdp"

echo ""
echo "==> Done. Open 'hx --health' to confirm each language server is detected."
echo "==> Make sure 'opencode' (or whatever LLM CLI you use) is on PATH — it's"
echo "    launched automatically in the 'llms' tab of the zellij layout."
echo "==> Launch a project with:  cd ~/your-project && alacritty"
