# Running CrowdGPT in Docker (NVIDIA)

This runs the client in **headless** mode. All runtime state is kept in the
`crowdgpt-app` named volume mounted at `/app`:

- `client.py` / `client.html` (including signed auto-updates)
- `checkpoints/` (auth token, device id, selected backend/VRAM)
- `checkpoints/hf_weights/` (downloaded model and engram weights)
- Hugging Face / Torch / CUDA caches

The image itself keeps a pristine copy of the code in `/opt/crowdgpt`. On first
start the entrypoint copies it into the volume. Later starts reuse the volume,
so auto-updates and checkpoints survive container restarts and rebuilds.

## Prerequisites

- Docker Engine with Compose v2
- NVIDIA driver installed on the host (`nvidia-driver-580`, etc.) — `docker-compose.yml` mounts the host's `/dev/nvidia*` devices and user-space CUDA/NVML libraries directly, so `nvidia-container-toolkit` is not required.

## Start

```bash
docker compose build
docker compose up -d
docker compose logs -f
```

By default the client trains **anonymously**. To use an account, create `.env`
from `.env.example` and set either:

```dotenv
CROWDGPT_USER=your_username
CROWDGPT_PASSWORD=your_password
```

or:

```dotenv
CROWDGPT_TOKEN=your_token
```

Then restart:

```bash
docker compose up -d --force-recreate
```

## GPU check inside the container

```bash
docker compose run --rm crowdgpt python -c \
  "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

## Networking & DNS

`docker-compose.yml` configures both `build.network: host` and runtime
`network_mode: host` so that image builds (`apt-get`, `pip`) and the running
client use the host's network stack and DNS resolver directly

Verify from inside the container:

```bash
docker compose exec crowdgpt cat /etc/resolv.conf
docker compose exec crowdgpt python -c "import socket; print(socket.gethostbyname('huggingface.co'))"
```

## Common settings

Set these in `.env` or in your shell before `docker compose up`:

| Variable | Default | Meaning |
|---|---|---|
| `CROWDGPT_ANON` | `1` | Train without an account if no token/user is set |
| `CROWDGPT_USER` / `CROWDGPT_PASSWORD` | empty | Account login |
| `CROWDGPT_TOKEN` | empty | Existing auth token |
| `CROWDGPT_BACKEND` | auto | `cuda`, `cpu`, etc. |
| `CROWDGPT_VRAM_GB` | auto | VRAM budget |
| `CROWDGPT_ROUNDS` | `0` | Stop after N rounds (`0` = forever) |
| `CROWDGPT_ENGRAM` | `1` | Set `0` to disable engram training |
| `CROWDGPT_NO_UPDATE` | `0` | Set `1` to disable auto-update |
| `CROWDGPT_NO_TOKENIZER` | `1` | Headless default; set `0` to load the tokenizer (uses `trust_remote_code=True`) |
| `CROWDGPT_SYNC_CODE` | `0` | Set `1` for one start to refresh code from the image |
| `CROWDGPT_DEBUG` | `0` | Verbose client logging |
| `CROWDGPT_SERVER` | built-in | Coordinator URL |

## Updating the code

Because `/app` is a volume, rebuilding the image does **not** overwrite the
existing volume. To pull the new image code into the volume while keeping
checkpoints:

```bash
docker compose build
CROWDGPT_SYNC_CODE=1 docker compose up -d --force-recreate
```

After that one start, set `CROWDGPT_SYNC_CODE=0` again (or remove it from
`.env`). This overwrites `client.py` / `client.html` with the image version,
so it also discards any auto-update that landed in the volume.

To start completely fresh (deletes all checkpoints and weights):

```bash
docker compose down -v
```

## Shell / debugging

The container's main process runs as the unprivileged `crowd` user. `exec`
defaults to root, so use `--user crowd` for a normal shell:

```bash
docker compose exec --user crowd crowdgpt bash
docker compose exec crowdgpt nvidia-smi
```

## Notes

- `install.sh` is intentionally **not** used inside the image. It is a host
  bootstrap that clones/resets the repository, installs uv/Python/WebView, and
  launches `installer.py`. The Dockerfile mirrors the dependency steps instead.
- The Dockerfile installs `bitsandbytes` for the 8-bit optimizer. If that
  install fails, the client falls back to fp32 Adam.
- For Blackwell / RTX 50-series, override the base image:
  ```bash
  PYTORCH_IMAGE=pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime docker compose build
  ```
- `.env` is excluded from the image and should not be committed.
- The tokenizer is disabled by default because `client.py` loads it with
  `trust_remote_code=True`. Only enable it if you trust the model repository.
