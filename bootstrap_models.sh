#!/usr/bin/env bash
# Idempotent model bootstrap for the concept-gen worker.
# Runs at container start BEFORE the worker-comfyui handler. Downloads FLUX.2 weights onto the
# network volume the first time only (subsequent boots see the files and skip = fast). This is
# also what makes the endpoint PORTABLE: point it at a fresh volume in any datacenter and the
# first boot repopulates it automatically — the image and config stay identical.
#
# ROBUST download: python hf_hub_download (NOT the hf CLI + hf_transfer, which failed silently when
# hf_transfer wasn't importable in the runtime env → left the volume empty → ComfyUI 'not in []').
set -uo pipefail
VOL="${RUNPOD_VOLUME_PATH:-/runpod-volume}"
echo "[boot] model bootstrap → $VOL/models"

python3 - <<'PY'
import os, shutil, sys
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "0"   # robust plain download, no hf_transfer dependency
try:
    from huggingface_hub import hf_hub_download
except Exception as e:
    print("[boot] FATAL: huggingface_hub missing in this python:", e, flush=True); sys.exit(1)
VOL = os.environ.get("RUNPOD_VOLUME_PATH", "/runpod-volume")
JOBS = [
 ("Comfy-Org/flux2-dev","split_files/diffusion_models/flux2_dev_fp8mixed.safetensors","diffusion_models"),
 ("Comfy-Org/flux2-dev","split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors","text_encoders"),
 ("Comfy-Org/flux2-dev","split_files/vae/flux2-vae.safetensors","vae"),
 ("Comfy-Org/flux2-dev","split_files/loras/Flux2TurboComfyv2.safetensors","loras"),
 ("alibaba-pai/FLUX.2-dev-Fun-Controlnet-Union","FLUX.2-dev-Fun-Controlnet-Union.safetensors","controlnet"),
]
for repo, path, sub in JOBS:
    dest = f"{VOL}/models/{sub}/{os.path.basename(path)}"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 1_000_000:
        print("[boot] HAVE", dest, flush=True); continue
    print("[boot] DL", repo, path, flush=True)
    f = hf_hub_download(repo, path)
    shutil.copy(f, dest)
    print("[boot] SAVED", dest, os.path.getsize(dest), flush=True)
print("[boot] ALL_MODELS_DONE", flush=True)
PY

echo "[boot] starting worker-comfyui handler"
exec /start.sh
