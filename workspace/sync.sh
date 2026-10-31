#!/usr/bin/env bash
# Clone or fast-forward every repo in workspace/repos.json into workspace/<name>/.
# Stdlib only (python3 parses the JSON); safe to re-run; never touches a dirty checkout.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${1:-$here/repos.json}"

python3 - "$manifest" <<'PY' | while IFS=$'\t' read -r name url branch; do
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
for r in m["repos"]:
    print(f'{r["name"]}\t{r["url"]}\t{r.get("branch", "main")}')
PY
  dest="$here/$name"
  if [ -d "$dest/.git" ]; then
    if [ -n "$(git -C "$dest" status --porcelain)" ]; then
      echo "skip  $name (dirty checkout)" >&2
      continue
    fi
    git -C "$dest" fetch --quiet origin "$branch"
    git -C "$dest" checkout --quiet "$branch"
    git -C "$dest" merge --ff-only --quiet "origin/$branch"
    echo "pull  $name @ $(git -C "$dest" rev-parse --short HEAD)"
  else
    git clone --quiet --branch "$branch" "$url" "$dest"
    echo "clone $name @ $(git -C "$dest" rev-parse --short HEAD)"
  fi
done
