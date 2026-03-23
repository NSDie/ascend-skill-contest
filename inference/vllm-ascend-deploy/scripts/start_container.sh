#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG=""
PLATFORM=""
DEVICE_ID=""
CONTAINER_NAME="vllm-ascend"
MODEL_PATH=""
PORT="8000"
DEVICES=""

usage() {
    echo "Usage: $0 --image-tag <tag> --model-path <path> --platform <A2|A3> --device-id <id> [options]"
    echo ""
    echo "Required:"
    echo "  --image-tag <tag>         vllm-ascend Docker image tag (will be modified for A3)"
    echo "  --model-path <path>       Absolute path to model directory"
    echo "  --platform <A2|A3>        NPU platform type"
    echo "  --device-id <id>          NPU device ID to use"
    echo ""
    echo "Optional:"
    echo "  --container-name <name>   Container name (default: vllm-ascend)"
    echo "  --port <port>             Service port (default: 8000)"
    echo "  --devices <ids>           NPU device IDs, comma-separated (default: all)"
    echo "  -h, --help                Show this help message"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --device-id)
                DEVICE_ID="$2"
                shift 2
                ;;
            --container-name)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            --model-path)
                MODEL_PATH="$2"
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
    
    if [ -z "$IMAGE_TAG" ]; then
        echo "Error: --image-tag is required"
        usage
    fi
    
    if [ -z "$MODEL_PATH" ]; then
        echo "Error: --model-path is required"
        usage
    fi
    
    if [ -z "$PLATFORM" ]; then
        echo "Error: --platform is required"
        usage
    fi
    
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: --device-id is required"
        usage
    fi
    
    if [ ! -d "$MODEL_PATH" ]; then
        echo "Error: Model path does not exist: $MODEL_PATH"
        exit 1
    fi
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running or you don't have permission"
        exit 1
    fi
}

pull_image() {
    local final_tag="${IMAGE_TAG}"
    
    if [ "$PLATFORM" == "A3" ]; then
        final_tag="${IMAGE_TAG}-a3"
        echo "A3 platform detected, using tag: ${final_tag}" >&2
    fi
    
    local image_name="quay.io/ascend/vllm-ascend:${final_tag}"
    
    if docker inspect --type=image "${image_name}" >/dev/null 2>&1; then
        echo "Image already exists locally: ${image_name}" >&2
    else
        echo "Image not found locally, pulling: ${image_name}" >&2
        docker pull "${image_name}" >&2
    fi
    
    echo "${image_name}"
}

get_device_mapping() {
    local device_mapping=""
    
    if [ -n "$DEVICES" ]; then
        IFS=',' read -ra DEVICE_ARRAY <<< "$DEVICES"
        for device_id in "${DEVICE_ARRAY[@]}"; do
            device_mapping="$device_mapping --device=/dev/davinci${device_id}"
        done
    else
        device_mapping="--device=/dev/davinci${DEVICE_ID}"
    fi
    
    echo "$device_mapping"
}

start_container() {
    local image_name="$1"
    local device_mapping=$(get_device_mapping)
    
    echo "DEBUG: Image name is: '${image_name}'" >&2
    echo "DEBUG: Image name length: ${#image_name}" >&2
    echo "DEBUG: Device ID is: '${DEVICE_ID}'" >&2
    echo "DEBUG: Device mapping is: '${device_mapping}'" >&2
    
    local existing_container=$(docker ps -a --filter "name=${CONTAINER_NAME}" --format "{{.ID}}")
    if [ -n "$existing_container" ]; then
        echo "Removing existing container: $CONTAINER_NAME"
        docker rm -f "$existing_container"
    fi
    
    echo "Starting container: $CONTAINER_NAME"
    
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --net=host \
        --shm-size=500g \
        --privileged=true \
        -w /home \
        --device=/dev/davinci_manager \
        --device=/dev/hisi_hdc \
        --device=/dev/devmm_svm \
        ${device_mapping} \
        -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
        -v /usr/local/dcmi:/usr/local/dcmi \
        -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
        -v /etc/ascend_install.info:/etc/ascend_install.info \
        -v /usr/local/sbin:/usr/local/sbin \
        -v "${MODEL_PATH}:${MODEL_PATH}" \
        -v /home:/home \
        -v /tmp:/tmp \
        -v /mnt:/mnt \
        -v /usr/share/zoneinfo/Asia/Shanghai:/etc/localtime \
        -e http_proxy="${http_proxy}" \
        -e https_proxy="${https_proxy}" \
        -e MODEL_PATH="${MODEL_PATH}" \
        -e PORT="${PORT}" \
        -e ASCEND_RT_VISIBLE_DEVICES="${DEVICE_ID}" \
        "${image_name}" \
        bash -c "while true; do sleep 3600; done"
    
    if [ $? -eq 0 ]; then
        echo "Container started successfully: $CONTAINER_NAME"
        echo "Model path: $MODEL_PATH"
        echo "Service port: $PORT"
        echo "NPU device: $DEVICE_ID"
        echo "ASCEND_RT_VISIBLE_DEVICES: $DEVICE_ID"
    else
        echo "Error: Failed to start container"
        exit 1
    fi
}

main() {
    parse_args "$@"
    check_docker
    
    local image_name=$(pull_image)
    start_container "$image_name"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
