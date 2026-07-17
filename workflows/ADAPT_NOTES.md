# Workflow adaptation — reference (pose) → our geometry-locked concept-gen
# The concrete API-format JSON is finalized AGAINST THE LIVE ENDPOINT (introspect /object_info, export API),
# not authored blind. This is the diff to apply to flux2-fun-pose.reference.json.

## Reference graph (confirmed node class_types, FLUX.2 modern sampler path)
UNETLoader(flux2_dev_fp8mixed) ─┐
CLIPLoader(mistral_3_small_flux2_fp8, type=flux2) → CLIPTextEncode(prompt) → FluxGuidance → BasicGuider
VAELoader(flux2-vae) ─┐
Flux2FunControlNetLoader(FLUX.2-dev-Fun-Controlnet-Union.safetensors) → Flux2FunControlNetApply
  Flux2FunControlNetApply.inputs = { conditioning, controlnet, vae, strength(0.75), control_image, [mask, inpaint_image] }
EmptyFlux2LatentImage(w,h,batch) · Flux2Scheduler + KSamplerSelect + RandomNoise → SamplerCustomAdvanced → VAEDecode → SaveImage
LoadImage(control) → ImageResize+ (fit control to gen res)

## DIFF for our pipeline
1. CONTROL IMAGE = our depth (concept_conditioning depth_hero.png), NOT pose. The Union auto-detects control type,
   so feeding the DEPTH map "just works". strength ≈ 0.75 (README control range 0.65-0.80) → our geometry lock.
2. SECOND CONTROL (canny): chain a 2nd Flux2FunControlNetApply fed our silhouette→canny (control_image=canny),
   strength ≈ 0.30. Node supports chaining (README: "supports chaining controlnets"). depth locks form, canny locks edges.
   → conditioning: CLIPTextEncode → Apply(depth,0.75) → Apply(canny,0.30) → FluxGuidance → BasicGuider.
3. TURBO LoRA: insert LoraLoaderModelOnly(Flux2TurboComfyv2) between UNETLoader and BasicGuider model input →
   steps drop to ~8 (Flux2Scheduler steps). NOTE benchmark tension: ControlNet README likes 25-50 steps; Turbo wants 8.
   Test both — turbo-8 for cheap batch drafts, full-28 for the hero pass (recipe flavor_batch vs flavor_hero).
4. MULTI-REF: FLUX.2 native multi-reference — feed image_refs[] (refs/<gen>/*.jpg) as reference latents. Wire via the
   FLUX.2 reference-image input if exposed in object_info; else skip in v1 (depth+canny+prompt already lock hard).
5. BATCH N: EmptyFlux2LatentImage.batch_size = N (recipe n_batch=10) → N concepts/job. SaveImage → N pngs.
6. PROMPT/NEGATIVE: from concept_request.json (prompt from refs/<gen>/concept_prompt.txt; negative = SPEC failure-modes).
7. HERO pass (separate job): drop Turbo LoRA, steps 28, res 1536, batch 1 on the curated pick; optional UltimateSDUpscale tile.

## Job input contract (worker-comfyui)
{ "input": { "workflow": <API_JSON>,
             "images": [ {"name":"depth_hero.png","image":"<base64>"},
                         {"name":"canny_hero.png","image":"<base64>"},
                         {"name":"ref0.jpg","image":"<base64>"} ... ] } }
LoadImage nodes reference images by "name". Output = base64 pngs (default) OR S3 if configured.

## Finalization steps (against live endpoint, in the validation session)
a. run-endpoint a trivial txt2img → confirm FLUX.2 core loads models from /runpod-volume (paths correct).
b. GET /object_info (via an execute-style probe job or the reference) → confirm exact input key names for
   UNETLoader/CLIPLoader(type)/EmptyFlux2LatentImage/Flux2FunControlNetApply on THIS ComfyUI build.
c. build concept_controlnet_api.json from the diff above → submit with mining_equipment depth+canny → inspect geometry-lock.
d. save the working API json here as concept_controlnet_api.json (the burst_client loads it + patches prompt/images/batch/seed).
