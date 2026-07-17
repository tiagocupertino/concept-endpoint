#!/usr/bin/env bash
# Idempotent model bootstrap for the concept-gen worker.
# Runs at container start BEFORE the worker-comfyui handler. Downloads FLUX.2 weights onto the
# network volume the first time only (subsequent boots see the files and skip = fast). This is
# also what makes the endpoint PORTABLE: point it at a fresh volume in any datacenter and the
# first boot repopulates it automatically — the image and config stay identical.
set -uo pipefail

VOL="${RUNPOD_VOLUME_PATH:-/runpod-volume}"
M="$VOL/models"
export HF_HUB_ENABLE_HF_TRANSFER=1

echo "[boot] model bootstrap → $M"
mkdir -p "$M/diffusion_models" "$M/text_encoders" "$M/vae" "$M/loras" "$M/controlnet"

dl () {  # $1=repo  $2=repo_path  $3=dest_abs
  local repo="$1" path="$2" dest="$3"
  if [ -s "$dest" ]; then echo "[boot] ✓ have $(basename "$dest")"; return 0; fi
  echo "[boot] ↓ $repo :: $path"
  # --local-dir keeps the repo subpath; download into a scratch dir on the SAME fs then move (rename, instant)
  hf download "$repo" "$path" --local-dir "$VOL/.hf_scratch" >/dev/null 2>&1 || \
    huggingface-cli download "$repo" "$path" --local-dir "$VOL/.hf_scratch" >/dev/null 2>&1
  if [ -s "$VOL/.hf_scratch/$path" ]; then
    mv -f "$VOL/.hf_scratch/$path" "$dest"
    echo "[boot] ✓ $(basename "$dest")"
  else
    echo "[boot] ✗ FAILED $repo :: $path"
  fi
}

# Sequential (hf_transfer already parallelizes chunks internally → the 35GB file dominates, ~few min once).
dl Comfy-Org/flux2-dev split_files/diffusion_models/flux2_dev_fp8mixed.safetensors      "$M/diffusion_models/flux2_dev_fp8mixed.safetensors"
dl Comfy-Org/flux2-dev split_files/text_encoders/mistral_3_small_flux2_fp8.safetensors  "$M/text_encoders/mistral_3_small_flux2_fp8.safetensors"
dl Comfy-Org/flux2-dev split_files/vae/flux2-vae.safetensors                            "$M/vae/flux2-vae.safetensors"
dl Comfy-Org/flux2-dev split_files/loras/Flux2TurboComfyv2.safetensors                  "$M/loras/Flux2TurboComfyv2.safetensors"
dl alibaba-pai/FLUX.2-dev-Fun-Controlnet-Union FLUX.2-dev-Fun-Controlnet-Union.safetensors "$M/controlnet/FLUX.2-dev-Fun-Controlnet-Union.safetensors"

rm -rf "$VOL/.hf_scratch" 2>/dev/null || true
echo "[boot] models ready → starting worker-comfyui"
exec /start.sh
