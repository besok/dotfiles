#!/usr/bin/env bash
#
# Installs Helix, Zed, Alacritty, Zellij, toolchains/LSPs/DAPs for
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
    brew)   # bash: macOS ships a frozen bash 3.2 at /bin/bash; install a
            # current bash 5.x (used as the Alacritty shell).
            # bash-completion@2: programmable completion for bash 4.2+ (make
            # targets, ssh hosts, git subcommands...). Without it bash only
            # completes filenames. Sourced from ~/.bashrc in step 9.
            install_pkgs bash bash-completion@2 helix alacritty zellij ;;
    apt)    install_pkgs alacritty bash-completion
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
    pacman) install_pkgs bash-completion helix alacritty zellij ;;
esac

# -------------------------------------------------------------------
# 2b. Zed: GUI editor alongside Helix. Makes sure the `zed` CLI is on
#     PATH so `zed .` / `zed file:line` work from a shell.
# -------------------------------------------------------------------
echo "==> Installing zed..."
mkdir -p "$LOCAL_BIN"
case "$PKG" in
    brew)
        # The cask links the bundled CLI as `zed` into Homebrew's bin. If
        # Zed.app was already downloaded from zed.dev the cask refuses to
        # overwrite it, so skip the install and link the CLI ourselves
        # (same thing Zed's "Install CLI" menu item does, minus sudo).
        if [[ -d /Applications/Zed.app ]]; then
            echo "   Zed.app already installed."
        else
            brew install --cask zed || echo "!! zed install failed — grab it from https://zed.dev/download"
        fi
        if ! command -v zed >/dev/null 2>&1 && [[ -x /Applications/Zed.app/Contents/MacOS/cli ]]; then
            ln -sf /Applications/Zed.app/Contents/MacOS/cli "$LOCAL_BIN/zed"
            echo "   Linked Zed CLI -> $LOCAL_BIN/zed"
        fi
        ;;
    pacman) install_pkgs zed ;;
    apt)
        # Zed renders through Vulkan. libvulkan1 is the loader; the Mesa
        # package adds the GPU drivers and a software fallback (lavapipe) so
        # Zed still starts in VMs / boxes without a working GPU driver.
        install_pkgs libvulkan1 mesa-vulkan-drivers || true
        # No apt package. Zed's official installer puts the app in
        # ~/.local/zed.app and symlinks the CLI to ~/.local/bin/zed.
        if ! command -v zed >/dev/null 2>&1; then
            curl -f https://zed.dev/install.sh | sh || echo "!! zed install failed — see https://zed.dev/download"
        fi
        ;;
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
    brew)   install_pkgs git cmake llvm glow entr bear ;;
    apt)    install_pkgs git cmake build-essential clang clangd clang-tidy \
                          lldb bear entr
            if ! command -v glow >/dev/null 2>&1; then
                echo "   Installing glow via Charm's apt repo..."
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y glow
            fi ;;
    pacman) install_pkgs git cmake base-devel clang lldb glow entr bear ;;
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
# 5. Python: interpreter + pylsp (jedi/mypy/rope, Helix) + ruff
# -------------------------------------------------------------------
echo "==> Setting up Python tooling..."
case "$PKG" in
    brew)   install_pkgs python pipx ;;
    apt)    install_pkgs python3 python3-pip pipx ;;
    pacman) install_pkgs python python-pipx ;;
esac
pipx ensurepath || true
# pylsp for Helix only; Zed uses basedpyright, which it downloads itself (and
# the Debugpy adapter on first debug). [rope] adds the rope_autoimport
# plugin, pylsp-mypy brings in mypy for type checking. python-lsp-server has
# no wheels for the newest CPython right after a release; fall back to 3.13.
pipx install "python-lsp-server[rope]" --force \
    || pipx install "python-lsp-server[rope]" --force --python 3.13 --fetch-missing-python \
    || echo "!! python-lsp-server install failed."
pipx inject python-lsp-server pylsp-mypy || echo "!! pylsp-mypy install failed."
pipx install ruff     --force

# uv: the cargo-equivalent for Python — manages virtualenvs, dependencies,
# and `uv run` in one fast tool (Rust-based). Installed via its official
# installer, which drops the binary in ~/.local/bin.
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# pytest + pytest-watcher (ptw): test runner and watch-mode for `pt`/`pw`/
# `ptk` (via prun: poetry run / uv run). pytest-watcher replaces the abandoned pytest-watch (same `ptw`
# command, but the watch path is a required argument: `ptw .`).
# Installed globally as a fallback; prefer adding them as project
# dev-deps via `uv add --dev pytest` for per-project environments.
pipx install pytest          --force || echo "!! pytest install failed."
# pytest-watcher's `watchdog` dep ships no CPython 3.14 wheel yet and its
# C-extension source build fails on macOS; fall back to a managed 3.13.
pipx install pytest-watcher  --force \
    || pipx install pytest-watcher --force --python 3.13 --fetch-missing-python \
    || echo "!! pytest-watcher install failed."

# -------------------------------------------------------------------
# 6. Rust: rustup toolchain + rust-analyzer + clippy + cargo subcommands
# -------------------------------------------------------------------
echo "==> Setting up Rust tooling..."
ensure_rust
rustup component add rust-analyzer rust-src clippy rustfmt

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

# -------------------------------------------------------------------
# 9b. Git diff/merge tooling: difftastic (structural diffs), mergiraf
#     (syntax-aware merge driver), rerere (replay past resolutions)
# -------------------------------------------------------------------
echo "==> Installing difftastic + mergiraf..."
case "$PKG" in
    brew)
        install_pkgs difftastic mergiraf
        ;;
    pacman)
        install_pkgs difftastic
        # mergiraf is in the AUR; build from source as a fallback
        command -v mergiraf >/dev/null 2>&1 || { ensure_rust; cargo install --locked mergiraf || echo "!! mergiraf install failed."; }
        ;;
    apt)
        ensure_rust
        command -v difft    >/dev/null 2>&1 || cargo install --locked difftastic || echo "!! difftastic install failed."
        command -v mergiraf >/dev/null 2>&1 || cargo install --locked mergiraf   || echo "!! mergiraf install failed."
        ;;
esac

# Wire up delta as git's pager for log/show/blame + interactive add
if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
fi

# rerere: reuse recorded conflict resolutions when the same conflict reappears
git config --global rerere.enabled true

# difftastic: structural (syntax-aware) diff for `git diff`/`show`/`log -p`.
# delta above stays as the pager; difftastic replaces the diff *algorithm*.
if command -v difft >/dev/null 2>&1; then
    git config --global diff.external "difft --color=always"
    git config --global alias.dlog  "log -p --ext-diff"
    git config --global alias.dshow "show --ext-diff"
fi

# mergiraf: syntax-aware merge driver. diff3 conflict style gives it the base
# revision it needs to reconstruct all three sides. The driver string is safe
# on git < 2.44 too — mergiraf detects the unexpanded %S/%X/%Y placeholders
# and falls back gracefully (see mergiraf docs).
if command -v mergiraf >/dev/null 2>&1; then
    git config --global merge.conflictStyle diff3
    git config --global merge.mergiraf.name mergiraf
    git config --global merge.mergiraf.driver 'mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L'
    mkdir -p "$CONFIG_HOME/git"
    if ! grep -Fq 'merge=mergiraf' "$CONFIG_HOME/git/attributes" 2>/dev/null; then
        echo '* merge=mergiraf' >> "$CONFIG_HOME/git/attributes"
    fi
fi

# The rc-file helpers below only append to files that already exist, so make
# sure they do — on a fresh macOS there's typically no ~/.bashrc or ~/.zshrc.
touch "$HOME/.bashrc" "$HOME/.zshrc"

# macOS quirk: bash *login* shells (what Alacritty/Terminal.app spawn) read
# ~/.bash_profile and never ~/.bashrc, so everything this script appends to
# .bashrc would be silently skipped. Chain them.
if [[ "$OS" == "Darwin" ]]; then
    if ! grep -Fq '.bashrc' "$HOME/.bash_profile" 2>/dev/null; then
        printf '\n[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"\n' >> "$HOME/.bash_profile"
        echo "==> Added ~/.bashrc sourcing to ~/.bash_profile"
    fi
fi

# macOS only exports LC_CTYPE=UTF-8 to terminals. bash 5.x then warns
# "setlocale: LC_COLLATE: cannot change locale ()" on every prompt, and any
# long-lived process started from that shell (the Zellij server) inherits the
# broken env. Export a full locale from the login shell; alacritty.toml [env]
# and zellij config.kdl env {} cover the terminals they spawn themselves.
LOCALE_LINE='[ -z "$LANG" ] && export LANG="en_US.UTF-8"  # dotfiles: full locale, silences bash setlocale warning'
if [[ "$OS" == "Darwin" ]]; then
    add_line "$HOME/.bash_profile" "$LOCALE_LINE"
else
    add_line "$HOME/.bashrc" "$LOCALE_LINE"
fi

add_line() {
    local rc_file="$1" line="$2"
    if [[ -f "$rc_file" ]] && ! grep -Fq "$line" "$rc_file"; then
        echo "$line" >> "$rc_file"
    fi
}

# bash-completion: make targets, ssh hosts, git subcommands, etc. Loaded
# first so tools that wrap existing completions (fzf --bash wraps ssh's)
# find the real one. The file lazy-loads per-command completions, so it is
# cheap at startup. Homebrew path on macOS; distro path on Linux.
BASH_COMPLETION_LINE='[[ -r "/opt/homebrew/etc/profile.d/bash_completion.sh" ]] && . "/opt/homebrew/etc/profile.d/bash_completion.sh"  # dotfiles: bash-completion (make/ssh/git tab completion)'
if [[ "$OS" != "Darwin" ]]; then
    BASH_COMPLETION_LINE='[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion  # dotfiles: bash-completion (make/ssh/git tab completion)'
fi
add_line "$HOME/.bashrc" "$BASH_COMPLETION_LINE"

if command -v starship >/dev/null 2>&1; then
    add_line "$HOME/.bashrc" 'eval "$(starship init bash)"'
    add_line "$HOME/.zshrc"  'eval "$(starship init zsh)"'
fi
# direnv: per-directory env (.envrc). Hooked after starship so the prompt
# sees the activated project venv; must run before zoxide (see below).
if command -v direnv >/dev/null 2>&1; then
    add_line "$HOME/.bashrc" 'command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"'
    add_line "$HOME/.zshrc"  'command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"'
fi
# zoxide wants to be initialized at the end of the rc file (after anything
# that installs prompt hooks, like starship), otherwise its doctor warns.
if command -v zoxide >/dev/null 2>&1; then
    add_line "$HOME/.bashrc" 'eval "$(zoxide init bash)"'
    add_line "$HOME/.zshrc"  'eval "$(zoxide init zsh)"'
fi

# ~/.local/bin holds the zed CLI (macOS/apt), uv, pipx apps and the
# mdp/llm/doctor scripts. Guarded so it isn't prepended twice when a login
# shell already exports it (e.g. ~/.bash_profile -> ~/.bashrc on macOS).
LOCAL_BIN_PATH_LINE='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac  # dotfiles: ~/.local/bin (zed, uv, pipx, mdp/llm/doctor)'
add_line "$HOME/.bashrc" "$LOCAL_BIN_PATH_LINE"
add_line "$HOME/.zshrc"  "$LOCAL_BIN_PATH_LINE"

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
mkdir -p "$CONFIG_HOME/helix" "$CONFIG_HOME/alacritty" "$CONFIG_HOME/zellij/layouts" "$CONFIG_HOME/zed" "$LOCAL_BIN"

ln -sf "$DOTFILES_DIR/helix/config.toml"        "$CONFIG_HOME/helix/config.toml"
ln -sf "$DOTFILES_DIR/helix/languages.toml"     "$CONFIG_HOME/helix/languages.toml"
ln -sf "$DOTFILES_DIR/alacritty/alacritty.toml" "$CONFIG_HOME/alacritty/alacritty.toml"

# Alacritty shell: macOS ships a frozen bash 3.2 at /bin/bash, so point it at
# Homebrew's bash 5.x there; Linux uses the system bash. Written to a separate
# file imported by alacritty.toml because the repo config is shared across
# machines and the path differs per-OS.
ALACRITTY_SHELL="/usr/bin/bash"
[[ "$OS" == "Darwin" ]] && ALACRITTY_SHELL="/opt/homebrew/bin/bash"
{
    printf '[terminal.shell]\n'
    printf 'program = "%s"\n' "$ALACRITTY_SHELL"
    printf 'args = ["-l"]\n'
} > "$CONFIG_HOME/alacritty/shell.toml"
ln -sf "$DOTFILES_DIR/zellij/config.kdl"        "$CONFIG_HOME/zellij/config.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/dev.kdl"   "$CONFIG_HOME/zellij/layouts/dev.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/rsdev.kdl" "$CONFIG_HOME/zellij/layouts/rsdev.kdl"
ln -sf "$DOTFILES_DIR/zellij/layouts/pydev.kdl" "$CONFIG_HOME/zellij/layouts/pydev.kdl"
ln -sf "$DOTFILES_DIR/starship/starship.toml"   "$CONFIG_HOME/starship.toml"

# zed: user settings (theme, JetBrains keymap, autosave, LSP tweaks), plus
# PyCharm-style run/debug configurations and the extra keybindings they use.
mkdir -p "$CONFIG_HOME/zed"
for zf in settings.json tasks.json debug.json keymap.json; do
    if [[ -f "$CONFIG_HOME/zed/$zf" && ! -L "$CONFIG_HOME/zed/$zf" ]]; then
        mv "$CONFIG_HOME/zed/$zf" "$CONFIG_HOME/zed/$zf.bak"
        echo "   Backed up existing zed $zf to $CONFIG_HOME/zed/$zf.bak"
    fi
    ln -sf "$DOTFILES_DIR/zed/$zf" "$CONFIG_HOME/zed/$zf"
done
ln -sf "$DOTFILES_DIR/scripts/mdp.sh"           "$LOCAL_BIN/mdp"
ln -sf "$DOTFILES_DIR/scripts/llm.sh"           "$LOCAL_BIN/llm"
ln -sf "$DOTFILES_DIR/scripts/doctor.sh"        "$LOCAL_BIN/doctor"
ln -sf "$DOTFILES_DIR/scripts/prun.sh"          "$LOCAL_BIN/prun"

# yazi: route Enter on text/code files to Helix instead of yazi's default
# opener (block=true hands the terminal fully to hx instead of trying to
# background it, which would otherwise leave Helix in a broken state)
if command -v yazi >/dev/null 2>&1 || command -v ya >/dev/null 2>&1; then
    mkdir -p "$CONFIG_HOME/yazi"
    ln -sf "$DOTFILES_DIR/yazi/yazi.toml" "$CONFIG_HOME/yazi/yazi.toml"
fi

# lazygit: render diffs through difftastic (structural diff)
if command -v lazygit >/dev/null 2>&1; then
    mkdir -p "$CONFIG_HOME/lazygit"
    ln -sf "$DOTFILES_DIR/lazygit/config.yml" "$CONFIG_HOME/lazygit/config.yml"
fi

if [[ -d "$DOTFILES_DIR/scripts" ]]; then
    chmod +x "$DOTFILES_DIR"/scripts/*.sh
fi

# has_func RC NAME: true if the rc file already defines a shell function NAME
# (`name() {` or `function name`). Used to keep our aliases/functions from
# shadowing hand-written ones — and to avoid a bash parse error: once an
# alias `pvenv` exists, re-sourcing a file that later defines `pvenv() {...}`
# expands the alias mid-definition and fails with "syntax error near `('".
has_func() {
    local rc_file="$1" name="$2"
    grep -Eq "^[[:space:]]*(function[[:space:]]+)?${name}[[:space:]]*\(\)" "$rc_file" 2>/dev/null
}

# Add zellij layout aliases to rc files
add_alias() {
    local rc_file="$1" alias_cmd="$2" name
    name="${alias_cmd#alias }"; name="${name%%=*}"
    if [[ -f "$rc_file" ]]; then
        if has_func "$rc_file" "$name"; then
            echo "   skip alias $name — $rc_file defines a $name() function"
        elif ! grep -Fq "$alias_cmd" "$rc_file"; then
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
# cr   - cargo run (build + run the project's binary), mirrors `pm`
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    add_alias "$rc" "alias cb='cargo build --quiet --message-format=short'"
    add_alias "$rc" "alias cc='cargo check --quiet --message-format=short'"
    add_alias "$rc" "alias ccl='cargo clippy --quiet --message-format=short'"
    add_alias "$rc" "alias cw='cargo watch -x \"check --message-format=short\"'"
    add_alias "$rc" "alias cbg='bacon'"
    add_alias "$rc" "alias ct='cargo nextest run'"
    add_alias "$rc" "alias cf='cargo fmt'"
    add_alias "$rc" "alias cu='cargo update'"
    add_alias "$rc" "alias cr='cargo run'"
done

# -------------------------------------------------------------------
# Python project tooling — the cargo-equivalent workflow, Poetry or uv
# -------------------------------------------------------------------
# One set of short names; `prun --tool` (scripts/prun.sh) decides per project
# whether they mean Poetry (poetry.lock or [tool.poetry] in pyproject.toml)
# or uv (everything else).
# pvenv - create the project env (poetry env use <py> | uv venv)
# pd    - install/sync the project's deps + env (poetry install | uv sync)
# pa    - add a dependency (poetry add | uv add), mirrors `cargo add`
# prm   - remove a dependency (poetry remove | uv remove), mirrors `cargo rm`
# pu    - upgrade locked dependencies (poetry update | uv lock --upgrade)
# prun  - run any command in the project env (poetry run | uv run)
# pf    - format code (ruff format)
# pl    - lint (ruff check)
# pcx   - lint with auto-fixes applied (ruff check --fix)
# pt    - run pytest, whole suite or the args you pass (prun pytest)
# pw    - run tests on every save (prun ptw ., via pytest-watcher)
# ptk   - fuzzy-pick one or more tests with fzf and run them (see below)
# ptf   - run all tests in one file, picked by file name (see below)
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    # Drop the uv-only aliases older versions of this script wrote; they are
    # functions now (an alias with the same name would break their parsing).
    if [[ -f "$rc" ]]; then
        sed -i.bak -e "/^alias pvenv='uv venv'$/d" -e "/^alias pd='uv sync'$/d" \
            -e "/^alias pa='uv add'$/d" -e "/^alias prm='uv remove'$/d" \
            -e "/^alias pu='uv lock --upgrade'$/d" -e "/^alias pt='uv run pytest'$/d" \
            -e "/^alias pw='uv run ptw .'$/d" "$rc"
    fi
    add_alias "$rc" "alias pf='ruff format .'"
    add_alias "$rc" "alias pl='ruff check .'"
    add_alias "$rc" "alias pcx='ruff check --fix .'"
done

# pyproj block: the pvenv/pd/pa/prm/pu/pt/pw functions plus ptk(), the fzf
# test picker, and ptf(), the per-file runner. ptk lists the tests pytest
# collects (`file::Class::test` node ids, parametrized ids included), lets
# you fuzzy-pick one or several (Tab to multi-select), and runs exactly
# those. Any argument pre-fills the fzf query, e.g. `ptk login`. ptf does the
# same over test files: `ptf login` runs all of tests/test_login.py. If
# collection fails (import error, missing pytest), pytest's own output is
# shown instead of an empty picker.
add_pyproj_function() {
    local rc_file="$1"
    local marker="# pyproj: Poetry/uv project tooling"
    if [[ -f "$rc_file" ]]; then
        if grep -Fq "$marker" "$rc_file"; then
            # Current layout ends with an explicit end marker; older installs
            # (ptk() as the last function) end at the first bare `}`.
            if grep -Fxq "# pyproj: end" "$rc_file"; then
                sed -i.bak '/^# pyproj: Poetry\/uv project tooling/,/^# pyproj: end$/d' "$rc_file"
            else
                sed -i.bak '/^# pyproj: Poetry\/uv project tooling/,/^}$/d' "$rc_file"
            fi
        fi
        # Older standalone ptk() from this script (uv-only): superseded.
        if grep -Fq "# ptk(): fuzzy-pick and run a single pytest test (uv run pytest + fzf)" "$rc_file"; then
            sed -i.bak '/^# ptk(): fuzzy-pick and run a single pytest test (uv run pytest + fzf)/,/^}$/d' "$rc_file"
        fi
        if has_func "$rc_file" "ptk" || has_func "$rc_file" "ptf" || has_func "$rc_file" "pt"; then
            echo "   skip pyproj block — $rc_file already defines its own pt()/ptk()/ptf()"
            return 0
        fi
        echo "==> Adding Poetry/uv project functions (pd, pt, ptk, ptf, ...) to $rc_file"
        cat >> "$rc_file" <<'EOF'

# pyproj: Poetry/uv project tooling (pvenv pd pa prm pu pt pw ptk ptf) — dotfiles
unalias pvenv pd pa prm pu prun pt pw ptk ptf 2>/dev/null
_pyt()  { command prun --tool 2>/dev/null || echo uv; }
pvenv() { if [[ $(_pyt) == poetry ]]; then poetry env use "${1:-python3}"; else uv venv "$@"; fi; }
pd()    { if [[ $(_pyt) == poetry ]]; then poetry install "$@"; else uv sync "$@"; fi; }
pa()    { if [[ $(_pyt) == poetry ]]; then poetry add "$@"; else uv add "$@"; fi; }
prm()   { if [[ $(_pyt) == poetry ]]; then poetry remove "$@"; else uv remove "$@"; fi; }
pu()    { if [[ $(_pyt) == poetry ]]; then poetry update "$@"; else uv lock --upgrade "$@"; fi; }
# pt: pytest in the project env. Adds --dis-vis when the repo's conftest
# defines that option (otherwise graphviz/matplotlib windows block the run).
pt()    { grep -qs 'dis-vis' tests/conftest.py && set -- --dis-vis "$@"; prun pytest "$@"; }
pw()    { prun ptw . "$@"; }
# ptk [query]: fuzzy-pick test(s) with fzf (Tab = multi-select) and run them.
# Collects and runs from the project root, so it sees the whole suite from
# any subdirectory and the picked node ids resolve.
ptk() {
    local root out ids line tests=()
    root=$(command prun --root 2>/dev/null) || root=$PWD
    out=$(cd "$root" && prun pytest --collect-only -q 2>&1)
    ids=$(printf '%s\n' "$out" | grep '::')
    if [[ -z "$ids" ]]; then
        printf '%s\n' "$out" >&2
        echo "ptk: pytest collected no tests under $root" >&2
        return 1
    fi
    ids=$(printf '%s\n' "$ids" | fzf --multi --height 40% --reverse \
        --prompt 'pytest> ' --query "$*") || return
    [[ -n "$ids" ]] || return
    while IFS= read -r line; do tests+=("$line"); done <<< "$ids"
    (cd "$root" && pt "${tests[@]}")
}
# ptf [name]: run every test in one test file, picked by file name.
# `ptf login` runs tests/test_login.py straight away when exactly one
# collected file matches; several matches (or no argument) open an fzf
# picker over the test files (Tab = multi-select). Paths to existing files
# are passed through as-is, so `ptf tests/test_x.py` also works.
ptf() {
    local root out files picked line tests=()
    if [[ $# -gt 0 && -f "$1" ]]; then pt "$@"; return; fi
    root=$(command prun --root 2>/dev/null) || root=$PWD
    out=$(cd "$root" && prun pytest --collect-only -q 2>&1)
    files=$(printf '%s\n' "$out" | grep '::' | cut -d: -f1 | sort -u)
    if [[ -z "$files" ]]; then
        printf '%s\n' "$out" >&2
        echo "ptf: pytest collected no tests under $root" >&2
        return 1
    fi
    if [[ $# -gt 0 ]]; then
        picked=$(printf '%s\n' "$files" | grep -F -- "$1")
        [[ $(printf '%s\n' "$picked" | grep -c .) -eq 1 ]] || picked=""
    fi
    if [[ -z "$picked" ]]; then
        picked=$(printf '%s\n' "$files" | fzf --multi --height 40% --reverse \
            --prompt 'test file> ' --query "$*") || return
    fi
    [[ -n "$picked" ]] || return
    while IFS= read -r line; do tests+=("$line"); done <<< "$picked"
    (cd "$root" && pt "${tests[@]}")
}
# pyproj: end
EOF
    fi
}

add_pyproj_function "$HOME/.bashrc"
add_pyproj_function "$HOME/.zshrc"

# y(): launch yazi, and if you cd'd somewhere inside it, land your shell
# there on quit (the standard wrapper recommended by yazi's own docs —
# without it, exiting yazi drops you back where you started).
add_yazi_function() {
    local rc_file="$1"
    local marker="# y(): launch yazi, cd to wherever you navigated to on quit"
    if [[ -f "$rc_file" ]]; then
        if grep -Fq "$marker" "$rc_file"; then
            sed -i.bak '/^# y(): launch yazi/,/^}$/d' "$rc_file"
        elif has_func "$rc_file" "y"; then
            echo "   skip y() — $rc_file already defines its own y()"
            return 0
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
        elif has_func "$rc_file" "rt"; then
            echo "   skip rt() — $rc_file already defines its own rt()"
            return 0
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

# pm(): run a Python entrypoint with the project's .venv interpreter.
# No args -> runs ./main.py if present. Otherwise pass the script (or
# `-m module`) to run, e.g. `pm src/app.py` or `pm -m mypkg.cli`.
add_pm_function() {
    local rc_file="$1"
    local marker="# pm(): run a Python entrypoint with the project .venv"
    if [[ -f "$rc_file" ]]; then
        if grep -Fq "$marker" "$rc_file"; then
            sed -i.bak '/^# pm(): run a Python/,/^}$/d' "$rc_file"
        elif has_func "$rc_file" "pm"; then
            echo "   skip pm() — $rc_file already defines its own pm()"
            return 0
        fi
        echo "==> Adding pm() entrypoint runner to $rc_file"
        cat >> "$rc_file" <<'EOF'

# pm(): run a Python entrypoint with the project .venv
pm() {
    local py=".venv/bin/python"
    if [[ ! -x "$py" ]]; then
        echo "pm: no .venv/bin/python here — run 'pvenv' first." >&2
        return 1
    fi
    if [[ $# -eq 0 ]]; then
        if [[ -f main.py ]]; then
            "$py" main.py
        else
            echo "pm: no args and no ./main.py — pass a script, e.g. 'pm src/app.py'." >&2
            return 1
        fi
    else
        "$py" "$@"
    fi
}
EOF
    fi
}

add_pm_function "$HOME/.bashrc"
add_pm_function "$HOME/.zshrc"

echo ""
echo "==> Done. Run 'source ~/.bashrc' or 'source ~/.zshrc' to apply."
