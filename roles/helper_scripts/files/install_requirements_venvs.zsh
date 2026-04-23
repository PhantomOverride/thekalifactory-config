#!/usr/bin/env zsh

# Iterate each directory under /opt/github-repos
# If a requirements.txt exists, create (or reuse) a venv at .venv and install requirements

set -eu
set -o pipefail

PYTHON_CMD=${PYTHON_CMD:-python3}
REPOS_DIR=${1:-/opt/github-repos}

if ! command -v "$PYTHON_CMD" >/dev/null 2>&1; then
  echo "Error: $PYTHON_CMD not found. Set PYTHON_CMD to a valid python executable." >&2
  exit 1
fi

if [ ! -d "$REPOS_DIR" ]; then
  echo "Repos directory '$REPOS_DIR' not found." >&2
  exit 1
fi

for repo in "$REPOS_DIR"/*; do
  [ -d "$repo" ] || continue
  req="$repo/requirements.txt"
  if [ -f "$req" ]; then
    echo "--- Processing: $repo"
    venv_dir="$repo/.venv"
    if [ ! -d "$venv_dir" ]; then
      echo "Creating venv at $venv_dir"
      "$PYTHON_CMD" -m venv "$venv_dir"
    else
      echo "Using existing venv at $venv_dir"
    fi

    # Ensure pip and packaging tools are up-to-date then install requirements
    if [ -x "$venv_dir/bin/python" ]; then
      "$venv_dir/bin/python" -m pip install --upgrade pip setuptools wheel
      "$venv_dir/bin/pip" install -r "$req"
    else
      echo "Warning: expected python at $venv_dir/bin/python not found; skipping $repo" >&2
    fi
  else
    echo "Skipping $repo (no requirements.txt)"
  fi
done

echo "Done."
