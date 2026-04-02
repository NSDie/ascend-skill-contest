#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_PATH=""
IMAGE_TAG="v0.17.0rc1"
CONTAINER_NAME="vllm-ascend"
PORT="8000"
DEVICES=""

usage() {
    echo "Usage: $0 --model-path <path> [options]"
    echo ""
    echo "Required:"
    echo "  --model-path <path>       Absolute path to model directory"
    echo ""
    echo "Optional:"
    echo "  --image-tag <tag>         vllm-ascend Docker image tag (default: v0.17.0rc1)"
    echo "  --container-name <name>   Container name (default: vllm-ascend)"
    echo "  --port <port>             Service port (default: 8000)"
    echo "  --devices <ids>           NPU device IDs, comma-separated (auto-detect if not specified)"
    echo "  -h, --help                Show this help message"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --model-path)
                MODEL_PATH="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --container-name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --devices)
                DEVICES="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    if [ -z "$MODEL_PATH" ]; then
        echo "Error: --model-path is required"
        usage
    fi
    
    if [ ! -d "$MODEL_PATH" ]; then
        echo "Error: Model path does not exist: $MODEL_PATH"
        exit 1
    fi
}

detect_environment() {
    echo "Step 1: Detecting NPU environment..." >&2
    
    local detect_output=$(bash "${SCRIPT_DIR}/detect_platform.sh" 2>&1)
    local platform=$(echo "$detect_output" | grep "^PLATFORM=" | cut -d'=' -f2)
    local npu_count=$(echo "$detect_output" | grep "^NPU_COUNT=" | cut -d'=' -f2)
    local free_device=$(echo "$detect_output" | grep "^FREE_DEVICE=" | cut -d'=' -f2)
    
    echo "Platform: $platform" >&2
    echo "NPU Count: $npu_count" >&2
    echo "Free Device: $free_device" >&2
    
    # Handle detection failures
    if [ -z "$platform" ] || [ "$platform" == "unknown" ]; then
        echo "Info: Using default platform A2 (could not detect)" >&2
        platform="A2"
    fi
    
    if [ -z "$free_device" ]; then
        echo "Info: Using default device 0 (no free devices detected)" >&2
        free_device="0"
    fi
    
    echo "$platform|$free_device"
}

start_container() {
    local platform=$1
    local device_id=$2
    
    echo "Step 2: Starting Docker container..."
    
    if [ -n "$DEVICES" ]; then
        bash "${SCRIPT_DIR}/start_container.sh" \
            --model-path "${MODEL_PATH}" \
            --image-tag "${IMAGE_TAG}" \
            --platform "${platform}" \
            --device-id "${device_id}" \
            --container-name "${CONTAINER_NAME}" \
            --port "${PORT}" \
            --devices "${DEVICES}"
    else
        bash "${SCRIPT_DIR}/start_container.sh" \
            --model-path "${MODEL_PATH}" \
            --image-tag "${IMAGE_TAG}" \
            --platform "${platform}" \
            --device-id "${device_id}" \
            --container-name "${CONTAINER_NAME}" \
            --port "${PORT}"
    fi
}

start_vllm_service() {
    local device_id=$1
    
    echo "Step 3: Starting vLLM service..."
    echo "Configuring for single NPU device..."
    
    local vllm_config="--dtype=float16 \
                       --tensor-parallel-size=1 \
                       --max-model-len=4096 \
                       --gpu-memory-utilization=0.9 \
                       --trust-remote-code"
    
    echo "Starting vLLM with config: $vllm_config"
    
    docker exec -d "${CONTAINER_NAME}" bash -c "
        export ASCEND_RT_VISIBLE_DEVICES=${device_id} && \
        cd /home && \
        python -m vllm.entrypoints.openai.api_server \
            --model ${MODEL_PATH} \
            --host 0.0.0.0 \
            --port ${PORT} \
            ${vllm_config}
    "
    
    if [ $? -eq 0 ]; then
        echo "vLLM service started successfully"
    else
        echo "Error: Failed to start vLLM service"
        exit 1
    fi
}

wait_for_service() {
    echo "Step 4: Waiting for service to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s "http://localhost:${PORT}/health" > /dev/null 2>&1; then
            echo "Service is ready!"
            echo ""
            echo "========================================="
            echo "Deployment Complete!"
            echo "========================================="
            echo "Container: $CONTAINER_NAME"
            echo "Model: $MODEL_PATH"
            echo "Port: $PORT"
            echo "API Endpoint: http://localhost:${PORT}"
            echo ""
            echo "Test the service:"
            echo "  curl http://localhost:${PORT}/v1/models"
            echo ""
            echo "View logs:"
            echo "  docker logs $CONTAINER_NAME"
            echo ""
            echo "Stop service:"
            echo "  docker stop $CONTAINER_NAME"
            echo "========================================="
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo "Waiting for service... (attempt $attempt/$max_attempts)"
        sleep 5
    done
    
    echo "Warning: Service health check timed out"
    echo "Check logs with: docker logs $CONTAINER_NAME"
    return 1
}

main() {
    echo "========================================="
    echo "vLLM-Ascend Deployment"
    echo "========================================="
    echo ""
    
    parse_args "$@"
    
    local env_info=$(detect_environment)
    local platform=$(echo "$env_info" | cut -d'|' -f1)
    local device_id=$(echo "$env_info" | cut -d'|' -f2)
    
    echo ""
    
    start_container "$platform" "$device_id"
    
    echo ""
    
    start_vllm_service "$device_id"
    
    echo ""
    
    wait_for_service
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
