# concept-endpoint — FLUX.2 concept-gen worker (geometry-locked via ControlNet-Union)
# Base = RunPod worker-comfyui (ComfyUI as serverless API). CUDA 12.8.1 = REQUIRED for Blackwell (RTX PRO 6000).
# WHY custom image: network volumes hold MODELS but NOT custom nodes (worker-comfyui limitation) — and our
# ControlNet-Union geometry-lock NEEDS a custom node. So the nodes are baked here; models live on the volume.
FROM runpod/worker-comfyui:5.8.6-base-cuda12.8.1

# ── cutting-edge custom nodes (baked; volume can't carry these) ──────────────────────────────
# Pinned by clone at build time. Each justified for OUR geometry-locked concept-gen pipeline.
WORKDIR /comfyui/custom_nodes
RUN git clone --depth 1 -b master https://github.com/bryanmcguire/comfyui-flux2fun-controlnet.git && \
    git clone --depth 1 https://github.com/Fannovel16/comfyui_controlnet_aux.git && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git && \
    git clone --depth 1 https://github.com/cubiq/ComfyUI_essentials.git && \
    git clone --depth 1 https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git
#   comfyui-flux2fun-controlnet → the ControlNet-Union node = geometry lock (CORE, Apache-2.0)
#   comfyui_controlnet_aux      → depth/canny/lineart preprocessors (refine our local conditioning)
#   rgthree-comfy               → seed/batch/context nodes = clean bursts of N variants
#   ComfyUI-KJNodes             → advanced image/latent/mask utilities
#   ComfyUI_essentials          → resize/pad/mask helpers to fit conditioning to model res
#   ComfyUI_UltimateSDUpscale   → tiled hi-res upscale for the T4 hero pass

# install each node's python deps into the comfy env (hf_transfer for fast model pulls at boot)
RUN pip install --no-cache-dir --break-system-packages "huggingface_hub[hf_transfer]" || \
    pip install --no-cache-dir "huggingface_hub[hf_transfer]" ; \
    for d in */ ; do \
      if [ -f "$d/requirements.txt" ]; then \
        echo "== deps: $d ==" ; \
        pip install --no-cache-dir --break-system-packages -r "$d/requirements.txt" || \
        pip install --no-cache-dir -r "$d/requirements.txt" || echo "WARN reqs failed: $d" ; \
      fi ; \
    done

# ── boot wrapper: idempotently populate the network volume with models, then hand off to worker ──
COPY bootstrap_models.sh /pipeline_boot.sh
RUN chmod +x /pipeline_boot.sh
WORKDIR /
# worker-comfyui's original CMD is ["/start.sh"]; we prepend the model bootstrap and exec into it.
CMD ["/pipeline_boot.sh"]
