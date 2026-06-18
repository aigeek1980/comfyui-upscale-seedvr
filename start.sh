#!/bin/bash
set -e

# Hot-patch: always pull latest handler and workflow from GitHub
# This means rp_handler.py and api-workflow.json changes never need a rebuild
echo "Fetching latest files from GitHub..."
curl -sf -o /rp_handler.py \
    "https://raw.githubusercontent.com/aigeek1980/seedvr2-upscaler/main/rp_handler.py" \
    && echo "✅ rp_handler.py updated" \
    || echo "⚠️ Failed to fetch rp_handler.py — using baked-in version"

curl -sf -o /api-workflow.json \
    "https://raw.githubusercontent.com/aigeek1980/seedvr2-upscaler/main/api-workflow.json" \
    && echo "✅ api-workflow.json updated" \
    || echo "⚠️ Failed to fetch api-workflow.json — using baked-in version"

# Check CUDA
echo "Checking CUDA..."
if ! python3 -c "import torch; assert torch.cuda.is_available(), 'No CUDA'"; then
    echo "Error: CUDA not available. Exiting."
    exit 1
fi
echo "✅ CUDA available"

# Start ComfyUI in background
echo "Starting ComfyUI..."
python /comfyui/main.py --listen 127.0.0.1 --port 8188 > /var/log/comfyui.log 2>&1 &

# Wait for ComfyUI in bash
echo "Waiting for ComfyUI to be ready..."
max_wait=120
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "✅ ComfyUI is ready!"
        break
    fi
    echo "Waiting... ($wait_count/$max_wait)"
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "Error: ComfyUI failed to start within $max_wait seconds"
    exit 1
fi

# Start handler
echo "Starting handler..."
exec python -u /rp_handler.py
