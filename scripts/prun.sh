#!/usr/bin/env bash
# prun — run a command inside the current Python project's environment,
# via `poetry run` in Poetry projects and `uv run` everywhere else.
# Linked to ~/.local/bin/prun by install.sh; used by the pd/pt/pw/ptk shell
# functions and by the Zed run configurations in zed/tasks.json.
#
#   prun pytest -q tests/test_x.py     # poetry run pytest ... | uv run pytest ...
#   prun --tool                        # print "poetry" or "uv" and exit
#   prun --root                        # print the project root (dir of pyproject.toml)
#
# Detection walks up from the current directory to the first pyproject.toml /
# poetry.lock / uv.lock and picks Poetry when it finds poetry.lock or a
# [tool.poetry] table. Never falls through to `uv sync`-style commands in a
# Poetry repo: uv ignores [tool.poetry.*] and would build a wrong .venv.
set -euo pipefail

tool=uv
root=""
dir=$PWD
while :; do
    if [[ -f "$dir/poetry.lock" ]] || grep -qs '^\[tool\.poetry\]' "$dir/pyproject.toml"; then
        tool=poetry; root=$dir; break
    fi
    if [[ -f "$dir/uv.lock" || -f "$dir/pyproject.toml" ]]; then
        tool=uv; root=$dir; break
    fi
    [[ "$dir" == / ]] && break
    dir=$(dirname "$dir")
done

case "${1:-}" in
    --tool) echo "$tool"; exit 0 ;;
    --root)
        if [[ -n "$root" ]]; then echo "$root"; exit 0; fi
        echo "prun: no pyproject.toml / poetry.lock / uv.lock found above $PWD" >&2
        exit 1 ;;
esac
if ! command -v "$tool" >/dev/null 2>&1; then
    echo "prun: this looks like a $tool project but '$tool' is not installed" >&2
    exit 127
fi
if [[ "$tool" == poetry ]]; then
    exec poetry run "$@"
else
    exec uv run "$@"
fi
