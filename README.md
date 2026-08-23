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
│       ├── dev.kdl         # files (yazi) + editor (hx + 2 shells) + llms + git
│       └── rsdev.kdl       # same as dev, plus a checks tab
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

Notes on packages it can't get from apt directly:
- **Helix** on Ubuntu — not in the default repos, so the script adds the
  official PPA (`ppa:maveonair/helix-editor`) and installs from there. On
  non-Ubuntu

## Day-to-day use

```bash
cd ~/some-project
dev
```

`dev` is a small wrapper (`scripts/dev.sh`) that opens a Zellij session
using the `dev` layout, named after the current folder — so each project
gets its own persistent session. Run `dev` again from the same folder later
and it reattaches instead of starting fresh; your panes, running builds,
and the `llms` tab pick up right where you left off.

If you'd rather launch straight from your desktop instead of an existing
terminal, open Alacritty (maximized, light Catppuccin Latte colors) and
run `dev` inside it — same result.

For Rust projects, use `rsdev` instead — it's the same wrapper but opens the
`rsdev` layout, which adds a `checks` tab with dedicated panes for a single
test, the full test suite, and `clippy` (all run manually).

Inside the session:

- **Tab 1 — `files`**: launches `y` (yazi) automatically — a terminal file
  manager for browsing, previewing, and editing files without leaving the
  session.
- **Tab 2 — `editor`**: Helix open on `.` across the top; underneath, two
  shells side by side — left one is meant for a build/watch loop
  (`cargo watch -x run`, `zig build run --watch`, `make`, `ptw` for
  pytest-watch, etc.), right one is a free scratch shell.
- **Tab 3 — `llms`**: launches `opencode` automatically. Swap the `command`
  in `zellij/layouts/dev.kdl` if you use a different LLM CLI.