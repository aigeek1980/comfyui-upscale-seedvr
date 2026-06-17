# clean base image containing only comfyui, comfy-cli and comfyui-manager
FROM runpod/worker-comfyui:5.8.4-base

# build-time tokens for gated downloads — never baked into final image.
# pass via: docker build --build-arg HF_TOKEN=$HF_TOKEN ...
ARG HF_TOKEN=""

# install custom nodes into comfyui
RUN comfy node install --exit-on-fail comfyui-sam2@1.0.3 --mode remote || (echo "WARN: comfyui-sam2@1.0.3 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-sam2 --mode remote)
RUN git clone https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler && cd /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler && (git checkout 690cc39379c1481159ddd451368dbf2295930fc6 2>/dev/null || (git fetch origin 690cc39379c1481159ddd451368dbf2295930fc6 --depth=1 && git checkout 690cc39379c1481159ddd451368dbf2295930fc6) || echo "WARN: commit 690cc39379c1481159ddd451368dbf2295930fc6 unreachable in https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler, falling back to default branch HEAD")
RUN git clone https://github.com/ALatentPlace/ComfyUI_yanc /comfyui/custom_nodes/ComfyUI_yanc && cd /comfyui/custom_nodes/ComfyUI_yanc && (git checkout 923c366c2937cf6ce55e8a808e29f23831281bb5 2>/dev/null || (git fetch origin 923c366c2937cf6ce55e8a808e29f23831281bb5 --depth=1 && git checkout 923c366c2937cf6ce55e8a808e29f23831281bb5) || echo "WARN: commit 923c366c2937cf6ce55e8a808e29f23831281bb5 unreachable in https://github.com/ALatentPlace/ComfyUI_yanc, falling back to default branch HEAD")
RUN comfy node install --exit-on-fail comfyui-kjnodes@1.1.9 || (echo "WARN: comfyui-kjnodes@1.1.9 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-kjnodes)
RUN comfy node install --exit-on-fail comfyui_essentials@1.1.0 || (echo "WARN: comfyui_essentials@1.1.0 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui_essentials)

# download models into comfyui
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do comfy model download --url 'https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_base_plus.pt' --relative-path models/diffusion_models --filename 'sam2_hiera_base_plus.pt' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors' --relative-path models/Unknown --filename 'ema_vae_fp16.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do HF_TOKEN=$HF_TOKEN comfy model download --url 'https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp16.safetensors' --relative-path models/Unknown --filename 'seedvr2_ema_7b_fp16.safetensors' && break; if [ $i -eq 5 ]; then echo "model-download failed after 5 attempts" >&2; exit 1; fi; SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && echo "model-download attempt $i failed; retrying in $SLEEP seconds" >&2; sleep $SLEEP; done

# copy all input data (like images or videos) into comfyui (uncomment and adjust if needed)
# COPY input/ /comfyui/input/

# user-provided inputs override the auto-generated placeholders above.
RUN wget --progress=dot:giga -O '/comfyui/input/2116be21-0c89-49f3-8d1a-7aef34c2712c.png' "https://cool-anteater-319.convex.cloud/api/storage/fc3928ee-baa9-47b3-b225-05bd1e21bd0a"
