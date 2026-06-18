# SeedVR2 Upscaler — RunPod Serverless Worker

ComfyUI-based image upscaler using SeedVR2 7B, with SAM2-guided selective sharpening before upscaling.

## What it does

- Upscales an input image using **SeedVR2 7B fp16**
- Applies **SAM2 + GroundingDINO** selective sharpening on a masked region before upscaling
- Exposes a clean API — no workflow JSON required from the caller

## API inputs

| Field | Type | Default | Description |
|---|---|---|---|
| `image` | string (base64) | required* | Input image as base64 |
| `image_base64` | string (base64) | required* | Alternative base64 key |
| `image_url` | string (URL) | required* | Input image as a URL |
| `resolution` | int | `2000` | Target upscale resolution |
| `sharp_prompt` | string | `"person"` | SAM2 mask target — what region to sharpen |
| `sharp_intensity` | float | `2.0` | Sharpening strength |

*One of `image`, `image_base64`, or `image_url` is required.

## API output

```json
{
  "image": "<base64 encoded result PNG>"
}
```

## Example API call

```python
import requests, base64

with open("photo.jpg", "rb") as f:
    image_b64 = base64.b64encode(f.read()).decode()

response = requests.post(
    "https://api.runpod.io/v2/YOUR_ENDPOINT_ID/runsync",
    headers={"Authorization": "Bearer YOUR_API_KEY"},
    json={
        "input": {
            "image": image_b64,
            "resolution": 2000,
            "sharp_prompt": "person",
            "sharp_intensity": 1.5
        }
    }
)

result = response.json()
with open("result.png", "wb") as f:
    f.write(base64.b64decode(result["output"]["image"]))
```

## Models (downloaded at build time)

| Model | Source | Size |
|---|---|---|
| `seedvr2_ema_7b_fp16.safetensors` | `numz/SeedVR2_comfyUI` on HuggingFace | 16.5 GB |
| `ema_vae_fp16.safetensors` | `numz/SeedVR2_comfyUI` on HuggingFace | ~1 GB |
| `sam2_hiera_base_plus.pt` | Meta (fbaipublicfiles) | ~160 MB |
| `groundingdino_swint_ogc.pth` | `ShilongLiu/GroundingDINO` on HuggingFace | 694 MB |

## Custom nodes

- `comfyui-sam2` — SAM2 segmentation
- `ComfyUI-SeedVR2_VideoUpscaler` — SeedVR2 upscaler nodes
- `ComfyUI_yanc` — sharpening node
- `comfyui-kjnodes` — KJNodes utilities
- `comfyui_essentials` — ImageComposite+

## GPU requirements

Minimum **24GB VRAM** (RTX 4090). Recommended: A100 or H100.

## Deploy on RunPod

1. Go to https://runpod.io/console/serverless
2. New endpoint → **Deploy from GitHub**
3. Select this repo, branch `main`
4. Select GPU with 24GB+ VRAM
5. Set Min workers: `0`, Max workers: `1`
6. Deploy — first build takes 20–40 min (downloading ~20GB of models)

## Build locally

```bash
docker build -t seedvr2-upscaler .
docker run --rm --gpus all seedvr2-upscaler
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the full environment, installs custom nodes, downloads all models |
| `rp_handler.py` | RunPod serverless handler — patches workflow with API inputs, uses WebSocket for result retrieval |
| `api-workflow.json` | ComfyUI API-format workflow used by the handler at runtime |
| `workflow.json` | Raw ComfyUI workflow — for reference and editing in ComfyUI desktop |
