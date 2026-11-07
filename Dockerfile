# syntax=docker/dockerfile:1

# PyTorch 2.6 + CUDA 12.4 is a good default for most NVIDIA cards.
# For Blackwell / RTX 50-series, override PYTORCH_IMAGE at build time, e.g.:
#   PYTORCH_IMAGE=pytorch/pytorch:2.7.0-cuda12.8-cudnn9-runtime docker compose build
ARG PYTORCH_IMAGE=pytorch/pytorch:2.6.0-cuda12.4-cudnn9-runtime
FROM ${PYTORCH_IMAGE}

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TOKENIZERS_PARALLELISM=false \
    HF_HOME=/app/checkpoints/hf_home \
    TORCH_HOME=/app/checkpoints/torch_home \
    CUDA_CACHE_PATH=/app/checkpoints/cuda_cache \
    HOME=/home/crowd \
    XDG_CACHE_HOME=/home/crowd/.cache

RUN apt-get update \
 && apt-get install -y --no-install-recommends gosu ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install the same runtime dependencies the host installer uses.
# Strip torch (already provided by the PyTorch base image) and pywebview
# (unused in --headless container mode) just like installer.py does.
COPY requirements.txt /tmp/requirements.txt
RUN grep -Ev '^\s*(torch|torchvision|torchaudio|torch-directml|pywebview)(\s*[<>=!~].*)?$' /tmp/requirements.txt > /tmp/requirements.docker.txt \
 && python -m pip install --upgrade pip \
 && python -m pip install -r /tmp/requirements.docker.txt \
 && (python -m pip install bitsandbytes \
     || echo "WARNING: bitsandbytes install failed; 8-bit Adam will be unavailable") \
 && rm -f /tmp/requirements.txt /tmp/requirements.docker.txt

# Keep a pristine copy of the application in the image. The entrypoint copies
# it into the /app volume on first start (or when CROWDGPT_SYNC_CODE=1), so
# auto-updates and checkpoints survive container rebuilds.
COPY . /opt/crowdgpt

RUN mkdir -p /app/checkpoints \
 && (id -u crowd >/dev/null 2>&1 || useradd -m -s /bin/bash crowd) \
 && groupadd -f render \
 && usermod -aG video,render crowd \
 && chown -R crowd:crowd /app /opt/crowdgpt /home/crowd

# Runtime state (code updates, checkpoints, weights, auth) lives here.
VOLUME ["/app"]

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["--headless"]
