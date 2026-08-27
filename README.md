# hx + alacritty + zellij dotfiles

A fast, light-themed dev setup for Python, Rust, Zig, C++, and C, with an
LLM CLI tab.

```
dotfiles/
├── install.sh              # installs everything + symlinks configs
├── helix/
│   ├── config.toml         # editor look & feel (Catppuccin Latte)
│   └── languages.toml      # LSPs, formatters, debug adapters per language
├── alacritty/
│   └── alacritty.toml      # terminal appearance, maximized, opens into zellij
├── zellij/
│   ├── config.kdl          # keybindings, theme, mouse behavior
│   └── layouts/
│       ├── dev.kdl         # files (yazi) + editor (hx) + console + llms + git
│       ├── rsdev.kdl       # same as dev, no console tab; 4-console Rust ops tab
│       └── pydev.kdl       # same as dev, no console tab; 4-console Python ops tab
├── lazygit/
│   └── config.yml          # difftastic as the diff renderer
└── scripts/
    ├── llm.sh              # picks the LLM CLI per machine, installed as `llm`
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

rust-analyzer shows inlay type hints (binding modes, elided lifetimes,
closure return types, full function signatures) — tune them under
`language-server.rust-analyzer.config` in `languages.toml`.

## Do you need per-project setup?

Mostly no — the global config handles the LSPs/formatters automatically:

- **Rust**: nothing extra. `cargo new` gives rust-analyzer everything it needs.
- **Zig**: works as soon as `zls` is on your `PATH`.
- **Python**: pyright picks up an active virtualenv automatically. Only add
  a `pyrightconfig.json` in the project root if your venv lives somewhere
  non-standard.
- **C / C++**: this is the one exception — clangd needs a
  `compile_commands.json` per project to know your include paths and flags.
  `bear` is installed for exactly this: run `bear -- make`, or with CMake add
  `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`. With it, clangd also auto-inserts
  missing `#include`s (`--header-insertion=iwyu`); without it, that and
  accurate completion/diagnostics for anything outside the standard library
  are lost.

## Install

```bash
git clone <this repo> ~/dotfiles   # or unzip it there
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

Detects macOS (Homebrew), Debian/Ubuntu (apt), or Arch (pacman); installs
Helix/Alacritty/Zellij, each language's toolchain/LSP, `lldb-dap`,
`cargo-watch`, `glow`, `entr`, `bear`, `difftastic`, `mergiraf`, and `resvg`
(SVG rasterizer); symlinks everything into `~/.config/` and drops the `mdp`
script on your `PATH`.

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
`rsdev` layout. There's no `console` tab; instead the `ops` tab is a 2×2 grid
of four consoles — single test (`rt`), run (`cr`), full test suite
(`ct`/`cargo test`), and `clippy` (`ccl`) — all run manually.

For Python projects, use `pydev` — the same idea, but its `ops` tab is a 2×2
grid of four consoles: single test (`ptk`), run (`pm`), full test suite
(`pt`), and lint (`pl`).

In both layouts the `editor` tab is just Helix (no console), like `dev`.

## Useful commands

These aliases and functions are added to `~/.bashrc` / `~/.zshrc` by
`install.sh`:

| Command | What it does |
|---------|--------------|
| `dev`   | Open a Zellij session with the `dev` layout (named after the current folder) |
| `rsdev` | Same, but with the `rsdev` layout (adds an `ops` tab) |
| `pydev` | Same, but with the `pydev` layout (adds a Python `ops` tab) |
| `y`     | Launch yazi; on quit, `cd` to wherever you navigated to |
| `mdp`   | Live markdown preview (glow + entr) |

Rust / cargo aliases:

| Command | What it does |
|---------|--------------|
| `cb`  | `cargo build` — compact one-line diagnostics, no progress spam |
| `cc`  | `cargo check` — same, but skips codegen (fastest feedback loop) |
| `ccl` | `cargo clippy` — compact diagnostics |
| `cw`  | `cargo watch` running `cargo check` on every save |
| `cbg` | `bacon` — live, always-on compact diagnostics panel |
| `ct`  | Run the full test suite via `cargo nextest run` |
| `cf`  | `cargo fmt` |
| `cu`  | `cargo update` (bump `Cargo.lock` within semver constraints) |
| `cr`  | `cargo run` (build + run the project binary), mirrors `pm` |
| `rt`  | Fuzzy-pick and run a single Rust test (cargo-nextest + fzf) |

Python / uv aliases (the cargo-equivalent workflow, powered by [uv](https://docs.astral.sh/uv/)):

| Command | What it does |
|---------|--------------|
| `pvenv` | Create a `.venv` in the current project (`uv venv`) |
| `pd`    | Sync/install the project's deps + env (`uv sync`) |
| `pa`    | Add a dependency (`uv add <pkg>`) |
| `prm`   | Remove a dependency (`uv remove <pkg>`) |
| `pu`    | Upgrade locked deps within constraints (`uv lock --upgrade`) |
| `pf`    | Format code (`ruff format .`) |
| `pl`    | Lint (`ruff check .`) |
| `pcx`   | Lint with auto-fixes (`ruff check --fix .`) |
| `pt`    | Run the full test suite (`uv run pytest`) |
| `pw`    | Run tests on every save (`uv run ptw .`, via pytest-watcher) |
| `ptk`   | Fuzzy-pick and run a single pytest test (uv + fzf) |
| `pm`    | Run a Python entrypoint via `.venv/bin/python` (defaults to `main.py`) |

To use `pt`/`pw`/`ptk`, add `pytest` as a project dev-dependency once:
`uv add --dev pytest` (add `pytest-watcher` too for `pw`).

## Git diffs, merges & conflict resolution

Three tools make reviewing and merging code less tedious, wired up by
`install.sh`:

| Tool        | Role                                                            |
|-------------|-----------------------------------------------------------------|
| [difftastic](https://difftastic.wilfred.me.uk/) | syntax-aware (structural) diffs — `git diff` and lazygit |
| [mergiraf](https://mergiraf.org/)  | syntax-aware merge driver — auto-resolves `merge`/`rebase`/`cherry-pick` conflicts |
| `rerere` (git built-in) | records how you resolved a conflict and replays it next time |

- **difftastic** is set as git's external diff (`diff.external`), so plain
  `git diff` shows structural diffs. `delta` stays on as the pager for
  `git log`/`show`/`blame` and `git add -p`. lazygit renders its diff pane
  through difftastic too.
- **mergiraf** is registered as the `mergiraf` merge driver and applied to all
  files via the global gitattributes (`~/.config/git/attributes`); `diff3`
  conflict style is enabled so it can reconstruct all three sides. When it
  auto-resolves a conflict it asks you to review with `mergiraf review <id>`.
- **rerere** is enabled (`rerere.enabled`), so conflicts you've solved once are
  re-applied automatically the next time they show up.

| Command               | What it does |
|-----------------------|--------------|
| `git diff`            | structural diff via difftastic (opt out with `--no-ext-diff`) |
| `git dlog`            | `git log -p` with difftastic |
| `git dshow`           | `git show` with difftastic |
| `mergiraf review <id>`| review a conflict mergiraf auto-resolved |
| `mergiraf solve <f>`  | attempt to auto-resolve an existing conflicted file |

Inside the session (`dev`):

- **Tab 1 — `files`**: launches `y` (yazi) automatically — a terminal file
  manager for browsing, previewing, and editing files without leaving the
  session.
- **Tab 2 — `editor`**: Helix open on `.`, full pane — no shell underneath.
- **Tab 3 — `console`**: a scratch shell for builds and ad-hoc commands.
- **Tab 4 — `llms`**: launches `llm` (`scripts/llm.sh`), which picks whichever
  LLM CLI this machine has — `claude` or `opencode`, in that order. Set
  `export LLM_CLI=<cmd>` in your shell rc to force a specific one, so the
  shared layouts stay identical across machines.
- **Tab 5 — `git`**: lazygit, for status/diff/stage/commit without leaving
  the session.

In `rsdev`/`pydev` there's no `console` tab: the `editor` tab is just Helix,
and the `ops` tab (a 2×2 grid of four consoles — single test, run, full test
suite, clippy/lint) sits between `editor` and `llms`.

## Helix keybindings

Line numbers are absolute (1-based from the top of the file, not relative to
the cursor) — see `line-number` in `helix/config.toml`. Extra bindings added
on top of the Helix defaults (in `helix/config.toml`):

| Key      | What it does |
|----------|--------------|
| `Ctrl-s` | Save (`:w`) |
| `Ctrl-q` | Quit (`:q`) |
| `space`  | Picker menu (`space` → file picker, `space b` → buffer picker, `w` → save, `q` → quit) |
| `space B`| Git blame the current line — prints the commit/author that last touched it to the statusline |
| `m`      | Render the current markdown file through `glow` |
| `Ctrl-e` | Open the current file in VS Code at the cursor line (`code -g`) |

Note: `Ctrl-e` runs in the foreground, so Helix suspends until you close
VS Code.