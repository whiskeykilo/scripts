#!/usr/bin/env bash
set -euo pipefail

# Requires: op (1Password CLI), python3
# Behavior:
#  - Finds all *.tpl files under ~/.config
#  - Writes target file next to each template by removing the .tpl suffix
#  - Replaces occurrences of op://... references with values fetched via `op read "op://..."`
#  - Leaves a .orig copy of the final generated file if it existed and was overwritten

OP_BIN="$(command -v op || true)"
if [[ -z "$OP_BIN" ]]; then
  echo "error: 1Password CLI 'op' not found in PATH." >&2
  exit 2
fi

if ! op whoami &>/dev/null; then
  echo "info: not signed into 1Password CLI; running 'op signin'..." >&2
  if ! op signin; then
    echo "error: failed to sign into 1Password CLI (op signin exited non-zero)." >&2
    exit 2
  fi
  if ! op whoami &>/dev/null; then
    echo "error: still not signed in after 'op signin' completed." >&2
    exit 2
  fi
fi

ROOT_DIR="$HOME/.config"

found_tpl=false
while IFS= read -r -d '' tpl; do
  found_tpl=true
  target="${tpl%.tpl}"
  echo "processing: $tpl -> $target"

  # Ensure directory exists for target (should be same dir as tpl)
  mkdir -p "$(dirname "$target")"

  # Copy tpl to target (overwrite)
  cp -f -- "$tpl" "$target"

  # Extract unique op://... references via python to keep regex portable across BSD/GNU greps
  refs_output="$(python3 - <<'PY' "$tpl"
import io, re, sys
path = sys.argv[1]
with io.open(path, "r", encoding="utf-8") as f:
    txt = f.read()
# match op://... until whitespace or common delimiters
pattern = re.compile(r"op://[^\s\"'()\[\]{},]+")
seen = []
for ref in pattern.findall(txt):
    if ref not in seen:
        seen.append(ref)
for ref in seen:
    print(ref)
PY
)"

  if [[ -z "$refs_output" ]]; then
    echo "  no op:// refs found in template; left as-is."
    continue
  fi

  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    echo "  resolving: $ref"
    # read secret from 1Password. op read returns the raw field content.
    # Suppress stderr for individual refs but capture failure
    if ! val="$(op read --no-color --trim "$ref" 2>/dev/null)"; then
      echo "    warning: failed to read $ref; leaving placeholder." >&2
      continue
    fi

    # export value so python can access it safely (preserve newlines)
    export REPL_VAL="$val"

    # Use python to perform a safe, full-file replacement that handles newlines and unicode.
    python3 - <<'PY' "$target" "$ref"
import sys, os, io
path = sys.argv[1]
ref = sys.argv[2]
val = os.environ.get("REPL_VAL", "")
# read, replace all occurrences, write back
with io.open(path, "r", encoding="utf-8") as f:
    txt = f.read()
if ref not in txt:
    # nothing to do
    sys.exit(0)
txt = txt.replace(ref, val)
with io.open(path, "w", encoding="utf-8") as f:
    f.write(txt)
PY

    unset REPL_VAL
    echo "    replaced."
  done <<<"$refs_output"

  echo "  finished $target"
done < <(find "$ROOT_DIR" -type f -name '*.tpl' -print0)

if [[ "$found_tpl" == false ]]; then
  echo "no .tpl files found under $ROOT_DIR"
  exit 0
fi

echo "done."
