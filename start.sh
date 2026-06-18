#!/bin/bash
set -e

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
