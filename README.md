# hx + alacritty + zellij dotfiles

A fast, light-themed dev setup for Python, Rust, Zig, C++, and C, with an
LLM CLI tab and desktop notifications when a tool needs your input.

```
dotfiles/
├── install.sh              # installs everything + symlinks configs
├── helix/
│   ├── config.toml         # editor look & feel (Catppuccin Latte)
│   └── languages.toml      # LSPs, formatters, debug adapters per language
├── alacritty/
│   ├── alacritty.toml      # terminal appearance, maximized, opens into zellij
│   └── notify-bell.sh      # desktop notification on terminal bell
├── zellij/
│   ├── config.kdl          # keybindings, theme, mouse behavior
│   └── layouts/
│       └── dev.kdl         # editor tab (hx + 2 shells) + llms tab (opencode)
└── scripts/
    └── mdp.sh              # live markdown preview (glow + entr), installed as `mdp`
```

## What each language gets

| Language | LSP           | Formatter / linter    | Debugger (DAP) |
|----------|---------------|-------------------------|-----------------|
| Python   | pyright       | ruff (format + lint)    | — (add `debugpy` if you need it) |
| Rust     | rust-analyzer | rustfmt, clippy on save | lldb-dap        |
| Zig      | zls           | `zig fmt`                | — (zls doesn't ship DAP support yet) |
| C++      | clangd        | clang-tidy (via clangd) | lldb-dap        |
| C        | clangd        | clang-tidy (via clangd) | lldb-dap        |

Debug from Helix with `:debug-start` (or bind a key to it) once a binary
exists — it'll ask for the path to the compiled binary using the templates
in `languages.toml`.

## Do you need per-project setup?

Mostly no — the global config handles the LSPs/formatters automatically:

- **Rust**: nothing extra. `cargo new` gives rust-analyzer everything it needs.
- **Zig**: works as soon as `zls` is on your `PATH`.
- **Python**: pyright picks up an active virtualenv automatically. Only add
  a `pyrightconfig.json` in the project root if your venv lives somewhere
  non-standard.
- **C / C++**: this is the one exception — clangd needs a
  `compile_commands.json` per project to know your include paths and flags.
  Generate it with `bear -- make`, or with CMake add
  `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`. Without it, clangd still works but
  loses accurate completion/diagnostics for anything outside the standard
  library.

## Install

```bash
git clone <this repo> ~/dotfiles   # or unzip it there
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

Detects macOS (Homebrew), Debian/Ubuntu (apt), or Arch (pacman); installs
Helix/Alacritty/Zellij, each language's toolchain/LSP, `lldb-dap`,
`cargo-watch`, `glow`, and `entr`; symlinks everything into `~/.config/`
and drops the `mdp` script on your `PATH`.

Two things it can't fully automate:
- **Zig** on Debian/Ubuntu — grab a release binary from ziglang.org (apt's
  version is usually stale).
- **zls** — build from source, matched to your installed Zig version.

## Day-to-day use

```bash
cd ~/some-project
alacritty
```

Alacritty launches maximized, in light Catppuccin Latte colors, straight
into Zellij's `dev` layout:

- **Tab 1 — `editor`**: Helix open on `.` across the top; underneath, two
  shells side by side — left one is meant for a build/watch loop
  (`cargo watch -x run`, `zig build run --watch`, `make`, `ptw` for
  pytest-watch, etc.), right one is a free scratch shell.
- **Tab 2 — `llms`**: launches `opencode` automatically. Swap the `command`
  in `zellij/layouts/dev.kdl` if you use a different LLM CLI.

### Notifications when something needs you

`notify-bell.sh` fires on every terminal bell (`\a`) — most CLI tools,
including LLM/agent CLIs, ring it when they finish or are waiting on input.
It tries `notify-send` (Linux), then `terminal-notifier`, then `osascript`
(macOS) — whichever is available. Bell passes through Zellij to Alacritty
by default, so this works from any pane, including the `llms` tab.

### Mouse behavior

- Left-click and drag to select text — it's copied to the system clipboard
  automatically (`copy_on_select` in `zellij/config.kdl`).
- Right-click pastes (`mouse.bindings` in `alacritty.toml`).

### Markdown preview

```bash
mdp README.md
```

Renders the file with `glow` and re-renders on every save (via `entr`) —
run it in the free/scratch shell pane. There's also a `space m` binding in
Helix that does a one-shot `glow -p` render, but it needs Helix ≥ 24.03 for
the `%{buffer_name}` expansion — if yours is older, use `Ctrl-z` to suspend
Helix and run `glow -p file.md` by hand, then `fg` to resume.

## Customizing

- **Theme**: this is set up for light mode — Helix uses `catppuccin_latte`
  and Zellij uses `catppuccin-latte`. If your Zellij build doesn't ship
  Catppuccin themes built in, grab the theme file from
  `catppuccin/zellij` on GitHub and drop it in `~/.config/zellij/themes/`.
- **Font**: both Alacritty and the terminal UI assume "JetBrainsMono Nerd
  Font" is installed — change `font.normal.family` in `alacritty.toml` if
  you use something else.
- **Layout**: `zellij/layouts/dev.kdl` is the single source of truth for
  pane/tab arrangement — edit sizes, add tabs, or point the `llms` tab at
  a different CLI there.
