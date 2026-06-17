FROM runpod/worker-comfyui:5.8.4-base

ARG HF_TOKEN=""

# Custom nodes
RUN comfy node install --exit-on-fail comfyui-sam2@1.0.3 --mode remote || (echo "WARN: comfyui-sam2@1.0.3 unavailable in registry, falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-sam2 --mode remote)

RUN git clone https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler && cd /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler && (git checkout 690cc39379c1481159ddd451368dbf2295930fc6 2>/dev/null || echo "WARN: falling back to HEAD")

RUN git clone https://github.com/ALatentPlace/ComfyUI_yanc /comfyui/custom_nodes/ComfyUI_yanc && cd /comfyui/custom_nodes/ComfyUI_yanc && (git checkout 923c366c2937cf6ce55e8a808e29f23831281bb5 2>/dev/null || echo "WARN: falling back to HEAD")

RUN comfy node install --exit-on-fail comfyui-kjnodes@1.1.9 || (echo "WARN: falling back to latest" >&2 && comfy node install --exit-on-fail comfyui-kjnodes)

RUN comfy node install --exit-on-fail comfyui_essentials@1.1.0 || (echo "WARN: falling back to latest" >&2 && comfy node install --exit-on-fail comfyui_essentials)

# SAM2 model
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do \
    comfy model download \
    --url 'https://dl.fbaipublicfiles.com/segment_anything_2/072824/sam2_hiera_base_plus.pt' \
    --relative-path models/sam2 \
    --filename 'sam2_hiera_base_plus.pt' && break; \
    if [ $i -eq 5 ]; then echo "model-download failed" >&2; exit 1; fi; \
    SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && sleep $SLEEP; done

# GroundingDINO model
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do \
    comfy model download \
    --url 'https://huggingface.co/ShilongLiu/GroundingDINO/resolve/main/groundingdino_swint_ogc.pth' \
    --relative-path models/grounding-dino \
    --filename 'groundingdino_swint_ogc.pth' && break; \
    if [ $i -eq 5 ]; then echo "model-download failed" >&2; exit 1; fi; \
    SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && sleep $SLEEP; done

# SeedVR2 VAE
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do \
    HF_TOKEN=$HF_TOKEN comfy model download \
    --url 'https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors' \
    --relative-path models/SEEDVR2 \
    --filename 'ema_vae_fp16.safetensors' && break; \
    if [ $i -eq 5 ]; then echo "model-download failed" >&2; exit 1; fi; \
    SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && sleep $SLEEP; done

# SeedVR2 DiT
RUN BACKOFFS="10 20 30 60 90" && for i in 1 2 3 4 5; do \
    HF_TOKEN=$HF_TOKEN comfy model download \
    --url 'https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp16.safetensors' \
    --relative-path models/SEEDVR2 \
    --filename 'seedvr2_ema_7b_fp16.safetensors' && break; \
    if [ $i -eq 5 ]; then echo "model-download failed" >&2; exit 1; fi; \
    SLEEP=$(echo $BACKOFFS | cut -d ' ' -f $i) && sleep $SLEEP; done
