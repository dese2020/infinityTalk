#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# ---------------------------------------------------------------------------
# Validación de GPU
# ---------------------------------------------------------------------------
echo "Checking GPU availability..."

if ! command -v nvidia-smi > /dev/null 2>&1; then
    echo "FATAL: nvidia-smi not found. No NVIDIA driver present in this container/host."
    exit 1
fi

if ! nvidia-smi > /dev/null 2>&1; then
    echo "FATAL: nvidia-smi failed to run. GPU not visible to this container."
    echo "---- nvidia-smi output ----"
    nvidia-smi || true
    echo "----------------------------"
    exit 1
fi

echo "GPU detected:"
nvidia-smi --query-gpu=name,memory.total,driver_version,pstate --format=csv,noheader

# Verifica que PyTorch efectivamente vea la GPU (evita que el pod arranque
# "sano" y luego el primer prompt falle a mitad de sampling por CUDA no
# disponible, que es mucho más caro de diagnosticar que fallar aquí).
python - <<'PYEOF'
import sys
try:
    import torch
except Exception as e:
    print(f"FATAL: could not import torch: {e}")
    sys.exit(1)

if not torch.cuda.is_available():
    print("FATAL: torch.cuda.is_available() is False. PyTorch cannot see any GPU.")
    sys.exit(1)

try:
    name = torch.cuda.get_device_name(0)
    cap = torch.cuda.get_device_capability(0)
    print(f"PyTorch sees GPU 0: {name} (compute capability {cap[0]}.{cap[1]})")
    print(f"PyTorch version: {torch.__version__} | CUDA build: {torch.version.cuda}")
except Exception as e:
    print(f"FATAL: torch could not query the GPU: {e}")
    sys.exit(1)
PYEOF

echo "GPU validation OK."

# ---------------------------------------------------------------------------
# Arrancar ComfyUI en background
# ---------------------------------------------------------------------------
COMFYUI_LOG="/tmp/comfyui_startup.log"

echo "Starting ComfyUI in the background..."
python /ComfyUI/main.py --listen --use-sage-attention > "$COMFYUI_LOG" 2>&1 &
COMFYUI_PID=$!

# Wait for ComfyUI to be ready
echo "Waiting for ComfyUI to be ready..."
max_wait=120  # 최대 2분 대기
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    # Si el proceso de ComfyUI ya murió, no tiene sentido seguir esperando.
    if ! kill -0 "$COMFYUI_PID" 2>/dev/null; then
        echo "FATAL: ComfyUI process died during startup (pid $COMFYUI_PID)."
        echo "---- Last 100 lines of ComfyUI startup log ($COMFYUI_LOG) ----"
        tail -n 100 "$COMFYUI_LOG" || true
        echo "----------------------------------------------------------------"
        exit 1
    fi

    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "ComfyUI is ready!"
        break
    fi
    echo "Waiting for ComfyUI... ($wait_count/$max_wait)"
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "FATAL: ComfyUI failed to start within ${max_wait}s."
    echo "---- Last 100 lines of ComfyUI startup log ($COMFYUI_LOG) ----"
    tail -n 100 "$COMFYUI_LOG" || true
    echo "----------------------------------------------------------------"
    exit 1
fi

# Volcamos el log de arranque de ComfyUI al stdout del contenedor, para que
# quede en los logs del pod (útil para debug de CUDA OOM, mismatch de
# versiones de torch/xformers, etc. sin tener que entrar al contenedor).
cat "$COMFYUI_LOG"

# Seguimos apendeando el log de ComfyUI al stdout del contenedor durante el
# resto de la ejecución (para que los prints de sampling/errores en runtime
# también aparezcan en los logs del pod).
tail -n 0 -F "$COMFYUI_LOG" &

# Start the handler in the foreground
# 이 스크립트가 컨테이너의 메인 프로세스가 됩니다.
echo "Starting the handler..."
exec python handler.py
