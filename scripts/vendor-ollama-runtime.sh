#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/vendor"
OLLAMA_DIR="$VENDOR_DIR/ollama"
MODELS_DIR="$VENDOR_DIR/ollama-models"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tabnote-vendor.XXXXXX")"
MODEL="qwen2.5-coder:0.5b"
PORT="11435"
OLLAMA_ZIP_URL="${OLLAMA_ZIP_URL:-https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip}"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OLLAMA_DIR" "$MODELS_DIR"

if [ ! -x "$OLLAMA_DIR/ollama" ]; then
  echo "Downloading bundled Ollama runtime..."
  curl --fail --location --show-error --progress-bar "$OLLAMA_ZIP_URL" -o "$TEMP_DIR/Ollama-darwin.zip"
  unzip -q "$TEMP_DIR/Ollama-darwin.zip" -d "$TEMP_DIR"
  cp "$TEMP_DIR/Ollama.app/Contents/Resources/ollama" "$OLLAMA_DIR/ollama"
  chmod +x "$OLLAMA_DIR/ollama"
fi

echo "Starting private Ollama runtime on 127.0.0.1:$PORT..."
OLLAMA_HOST="127.0.0.1:$PORT" \
OLLAMA_MODELS="$MODELS_DIR" \
"$OLLAMA_DIR/ollama" serve >/tmp/tabnote-ollama-vendor.log 2>&1 &
SERVER_PID="$!"

for _ in {1..60}; do
  if curl -fsS "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:$PORT/api/tags" >/dev/null 2>&1; then
  echo "Private Ollama runtime did not start. Log:"
  tail -80 /tmp/tabnote-ollama-vendor.log || true
  exit 1
fi

echo "Pulling bundled model: $MODEL"
OLLAMA_HOST="127.0.0.1:$PORT" \
OLLAMA_MODELS="$MODELS_DIR" \
"$OLLAMA_DIR/ollama" pull "$MODEL"

echo "Vendored runtime and model are ready under $VENDOR_DIR"
