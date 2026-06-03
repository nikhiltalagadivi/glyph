#!/usr/bin/env bash
set -euo pipefail

MODEL="qwen2.5-coder:0.5b"

if ! command -v ollama >/dev/null 2>&1; then
  cat <<MSG
Ollama is not installed.

Install it from https://ollama.com/download, then run:
  scripts/setup-ollama-model.sh
MSG
  exit 1
fi

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Starting Ollama..."
  open -a Ollama >/dev/null 2>&1 || true
  sleep 3
fi

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  cat <<MSG
Ollama is installed, but its local server is not responding.

Open the Ollama app, or run this in another terminal:
  ollama serve

Then rerun:
  scripts/setup-ollama-model.sh
MSG
  exit 1
fi

ollama pull "$MODEL"
echo "Ready: TabNote will use $MODEL through http://127.0.0.1:11434"
