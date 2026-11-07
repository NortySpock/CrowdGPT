#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/app
IMAGE_APP_DIR=/opt/crowdgpt
USER_NAME=crowd
SELF=/usr/local/bin/docker-entrypoint.sh

# The volume mounted at /app starts empty. Seed it from the image, and allow
# an explicit refresh when the image contains newer code.
if [ "$(id -u)" = "0" ]; then
    # Ensure NVIDIA device nodes exist inside the container when running
    # without nvidia-container-toolkit.
    if [ -e /proc/driver/nvidia/version ]; then
        nv_major=$(awk '$2=="nvidia" {print $1; exit}' /proc/devices)
        uvm_major=$(awk '$2=="nvidia-uvm" {print $1; exit}' /proc/devices)
        if [ -n "$nv_major" ]; then
            [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$nv_major" 255 || true
            [ -e /dev/nvidia0 ]   || mknod -m 666 /dev/nvidia0 c "$nv_major" 0 || true
        fi
        if [ -n "$uvm_major" ]; then
            [ -e /dev/nvidia-uvm ]       || mknod -m 666 /dev/nvidia-uvm c "$uvm_major" 0 || true
            [ -e /dev/nvidia-uvm-tools ] || mknod -m 666 /dev/nvidia-uvm-tools c "$uvm_major" 1 || true
        fi
    fi

    mkdir -p "$APP_DIR/checkpoints" "/home/$USER_NAME/.cache"

    if [ ! -f "$APP_DIR/client.py" ] || [ "${CROWDGPT_SYNC_CODE:-0}" = "1" ]; then
        echo "[entrypoint] seeding $APP_DIR from $IMAGE_APP_DIR"
        cp -a "$IMAGE_APP_DIR/." "$APP_DIR/"
    fi

    if [ "$(stat -c '%U' "$APP_DIR")" != "$USER_NAME" ] \
        || [ "$(stat -c '%U' "$APP_DIR/checkpoints")" != "$USER_NAME" ]; then
        chown -R "$USER_NAME:$USER_NAME" "$APP_DIR"
    fi
    chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME"

    # Drop root before running the client.
    exec gosu "$USER_NAME" "$SELF" "$@"
fi

cd "$APP_DIR"

# If the caller passed a real command (python, bash, nvidia-smi, ...), run it
# directly. Otherwise treat the arguments as client.py flags.
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi

args=(python client.py --headless)

[ -n "${CROWDGPT_SERVER:-}" ]       && args+=(--server "$CROWDGPT_SERVER")
[ -n "${CROWDGPT_BACKEND:-}" ]      && args+=(--backend "$CROWDGPT_BACKEND")
[ -n "${CROWDGPT_VRAM_GB:-}" ]      && args+=(--vram-gb "$CROWDGPT_VRAM_GB")
[ -n "${CROWDGPT_ROUNDS:-}" ]       && args+=(--rounds "$CROWDGPT_ROUNDS")
[ -n "${CROWDGPT_USER:-}" ]         && args+=(--user "$CROWDGPT_USER")
[ "${CROWDGPT_NO_UPDATE:-0}" = "1" ]    && args+=(--no-update)
[ "${CROWDGPT_NO_TOKENIZER:-1}" = "1" ] && args+=(--no-tokenizer)
[ "${CROWDGPT_DEBUG:-0}" = "1" ]        && args+=(--debug)

# Prefer an explicit token/account. If neither is configured and there is no
# saved session in the volume, fall back to anonymous training.
if [ -n "${CROWDGPT_TOKEN:-}" ]; then
    :
elif [ -n "${CROWDGPT_USER:-}" ]; then
    :
elif [ "${CROWDGPT_ANON:-0}" = "1" ] && [ ! -f "$APP_DIR/checkpoints/auth_token.json" ]; then
    args+=(--anon)
fi

exec "${args[@]}" "$@"
