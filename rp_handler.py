import runpod
import os
import websocket
import base64
import json
import uuid
import logging
import urllib.request
import urllib.parse
import urllib.error
import binascii
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SERVER_ADDRESS = os.getenv('SERVER_ADDRESS', '127.0.0.1')
CLIENT_ID = str(uuid.uuid4())

# Load api-workflow.json once at startup
WORKFLOW_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "api-workflow.json")
with open(WORKFLOW_PATH) as f:
    WORKFLOW_TEMPLATE = json.load(f)

# Node IDs
NODE_LOAD_IMAGE      = "63"   # LoadImage
NODE_RESOLUTION      = "65"   # PrimitiveInt — feeds new_resolution in node 53
NODE_SHARP_INTENSITY = "97"   # PrimitiveFloat — Sharp Intensity
NODE_SHARP_PROMPT    = "102"  # PrimitiveString — Sharp Prompt


def save_base64_to_file(b64_data, output_path):
    try:
        decoded = base64.b64decode(b64_data)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, 'wb') as f:
            f.write(decoded)
        logger.info(f"✅ Image saved to {output_path}")
    except (binascii.Error, ValueError) as e:
        raise Exception(f"Base64 decode failed: {e}")


def queue_prompt(prompt):
    url = f"http://{SERVER_ADDRESS}:8188/prompt"
    p = {"prompt": prompt, "client_id": CLIENT_ID}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(url, data=data)
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        logger.error(f"ComfyUI /prompt rejected: {error_body}")
        raise Exception(f"ComfyUI 400: {error_body}")


def get_image(filename, subfolder, folder_type):
    params = urllib.parse.urlencode({
        "filename": filename,
        "subfolder": subfolder,
        "type": folder_type
    })
    with urllib.request.urlopen(f"http://{SERVER_ADDRESS}:8188/view?{params}") as resp:
        return resp.read()


def get_history(prompt_id):
    with urllib.request.urlopen(
        f"http://{SERVER_ADDRESS}:8188/history/{prompt_id}"
    ) as resp:
        return json.loads(resp.read())


def get_images_via_websocket(ws, prompt):
    prompt_id = queue_prompt(prompt)['prompt_id']
    logger.info(f"Job queued with prompt_id: {prompt_id}")

    while True:
        out = ws.recv()
        if isinstance(out, str):
            message = json.loads(out)
            if message['type'] == 'executing':
                data = message['data']
                if data['node'] is None and data['prompt_id'] == prompt_id:
                    logger.info("✅ ComfyUI execution complete")
                    break
            elif message['type'] == 'execution_error':
                raise Exception(f"ComfyUI execution error: {message['data']}")
        else:
            continue  # binary frame, skip

    history = get_history(prompt_id)[prompt_id]
    output_images = {}
    for node_id, node_output in history['outputs'].items():
        if 'images' in node_output:
            images_output = []
            for image in node_output['images']:
                image_data = get_image(image['filename'], image['subfolder'], image['type'])
                if isinstance(image_data, bytes):
                    image_data = base64.b64encode(image_data).decode('utf-8')
                images_output.append(image_data)
            output_images[node_id] = images_output

    return output_images


def handler(job):
    job_input = job.get("input", {})
    logger.info(f"Received job input keys: {list(job_input.keys())}")

    task_id = f"task_{uuid.uuid4()}"
    image_path = f"/comfyui/input/{task_id}_input.png"

    # Resolve input image
    if "image_base64" in job_input:
        save_base64_to_file(job_input["image_base64"], image_path)
    elif "image" in job_input:
        save_base64_to_file(job_input["image"], image_path)
    elif "image_url" in job_input:
        import subprocess
        result = subprocess.run(
            ['wget', '-O', image_path, '--no-verbose', job_input["image_url"]],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            return {"error": f"Image download failed: {result.stderr}"}
        logger.info(f"✅ Image downloaded from URL to {image_path}")
    else:
        return {"error": "No image provided. Use 'image' (base64), 'image_url', or 'image_base64'."}

    # Parameters with defaults
    resolution      = int(job_input.get("resolution", 2000))
    sharp_intensity = float(job_input.get("sharp_intensity", 2.0))
    sharp_prompt    = job_input.get("sharp_prompt", "person")

    logger.info(f"Params: resolution={resolution}, sharp_intensity={sharp_intensity}, sharp_prompt={sharp_prompt}")

    # Deep copy and patch workflow
    workflow = json.loads(json.dumps(WORKFLOW_TEMPLATE))
    workflow[NODE_LOAD_IMAGE]["inputs"]["image"]      = image_path
    workflow[NODE_RESOLUTION]["inputs"]["value"]      = resolution
    workflow[NODE_SHARP_INTENSITY]["inputs"]["value"] = sharp_intensity
    workflow[NODE_SHARP_PROMPT]["inputs"]["value"]    = sharp_prompt

    # Connect WebSocket
    ws_url = f"ws://{SERVER_ADDRESS}:8188/ws?clientId={CLIENT_ID}"
    ws = websocket.WebSocket()

    for attempt in range(36):  # retry up to 3 min
        try:
            ws.connect(ws_url)
            logger.info(f"✅ WebSocket connected (attempt {attempt + 1})")
            break
        except Exception as e:
            logger.warning(f"WebSocket connect failed ({attempt + 1}/36): {e}")
            if attempt == 35:
                return {"error": "WebSocket connection timeout"}
            time.sleep(5)

    # Run workflow
    try:
        images = get_images_via_websocket(ws, workflow)
    finally:
        ws.close()

    if not images:
        return {"error": "No images returned from ComfyUI"}

    # Return first image found
    for node_id, node_images in images.items():
        if node_images:
            logger.info(f"✅ Returning image from node {node_id}")
            return {"image": node_images[0]}

    return {"error": "No output image found"}


runpod.serverless.start({"handler": handler})
