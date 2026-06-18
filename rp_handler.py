import runpod
import json
import base64
import os
import urllib.request
import urllib.error
import time

COMFY_HOST = "127.0.0.1:8188"

# Load workflow template once at startup
WORKFLOW_PATH = os.path.join(os.path.dirname(__file__), "workflow.json")
with open(WORKFLOW_PATH) as f:
    WORKFLOW_TEMPLATE = json.load(f)


def wait_for_comfy(timeout=60):
    """Wait until ComfyUI is ready."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            urllib.request.urlopen(f"http://{COMFY_HOST}/system_stats")
            return True
        except Exception:
            time.sleep(1)
    raise RuntimeError("ComfyUI did not start in time")


def upload_image(image_b64, filename="input.png"):
    """Upload base64 image to ComfyUI input folder."""
    image_bytes = base64.b64decode(image_b64)
    import urllib.parse, io
    # Write directly to comfyui input folder
    input_path = f"/comfyui/input/{filename}"
    with open(input_path, "wb") as f:
        f.write(image_bytes)


def queue_workflow(workflow):
    """Submit workflow to ComfyUI and return prompt_id."""
    data = json.dumps({"prompt": workflow}).encode()
    req = urllib.request.Request(
        f"http://{COMFY_HOST}/prompt",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())["prompt_id"]


def wait_for_result(prompt_id, timeout=600):
    """Poll until job completes, return output images."""
    start = time.time()
    while time.time() - start < timeout:
        with urllib.request.urlopen(
            f"http://{COMFY_HOST}/history/{prompt_id}"
        ) as resp:
            history = json.loads(resp.read())
        if prompt_id in history:
            outputs = history[prompt_id]["outputs"]
            # Find SaveImage node output
            for node_id, node_output in outputs.items():
                if "images" in node_output:
                    return node_output["images"]
        time.sleep(2)
    raise RuntimeError(f"Job {prompt_id} timed out")


def get_image_b64(filename, subfolder="", img_type="output"):
    """Fetch output image from ComfyUI and return as base64."""
    import urllib.parse
    params = urllib.parse.urlencode({
        "filename": filename,
        "subfolder": subfolder,
        "type": img_type
    })
    with urllib.request.urlopen(
        f"http://{COMFY_HOST}/view?{params}"
    ) as resp:
        return base64.b64encode(resp.read()).decode()


def handler(job):
    job_input = job["input"]

    # Extract inputs with defaults
    image_b64   = job_input["image"]
    resolution  = int(job_input.get("resolution", 2000))
    sharp_prompt    = job_input.get("sharp_prompt", "person")
    sharp_intensity = float(job_input.get("sharp_intensity", 2.0))

    # Wait for ComfyUI to be ready
    wait_for_comfy()

    # Upload input image
    upload_image(image_b64, "input.png")

    # Deep copy workflow template
    workflow = json.loads(json.dumps(WORKFLOW_TEMPLATE))

    # Helper to find node by ID
    def node(node_id):
        return next(n for n in workflow["nodes"] if n["id"] == node_id)

    # Patch parameters
    node(63)["widgets_values"][0]  = "input.png"    # LoadImage
    node(65)["widgets_values"][0]  = resolution      # Upscale Resolution
    node(97)["widgets_values"][0]  = sharp_intensity  # Sharp Intensity
    node(102)["widgets_values"][0] = sharp_prompt     # Sharp Prompt

    # Submit to ComfyUI
    prompt_id = queue_workflow(workflow)

    # Wait for result
    images = wait_for_result(prompt_id)

    # Return first output image as base64
    img_info = images[0]
    result_b64 = get_image_b64(
        img_info["filename"],
        img_info.get("subfolder", ""),
        img_info.get("type", "output")
    )

    return {"image": result_b64, "prompt_id": prompt_id}


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
