#!/bin/bash

set -e

detect_platform() {
    local platform="unknown"
    
    if command -v npu-smi &> /dev/null; then
        local product_info=$(npu-smi info -t product -i 0 -c 0 2>/dev/null || echo "")
        if echo "$product_info" | grep -qi "A2"; then
            platform="A2"
        elif echo "$product_info" | grep -qi "A3"; then
            platform="A3"
        fi
    fi
    
    if [ "$platform" == "unknown" ] && command -v dmidecode &> /dev/null; then
        local system_info=$(sudo dmidecode -t system 2>/dev/null | grep -i "product" || echo "")
        if echo "$system_info" | grep -qi "A2"; then
            platform="A2"
        elif echo "$system_info" | grep -qi "A3"; then
            platform="A3"
        fi
    fi
    
    if [ "$platform" == "unknown" ]; then
        if [ -f "/etc/ascend_install.info" ]; then
            if grep -qi "A2" /etc/ascend_install.info; then
                platform="A2"
            elif grep -qi "A3" /etc/ascend_install.info; then
                platform="A3"
            fi
        fi
    fi
    
    echo "$platform"
}

get_npu_count() {
    local count=0
    if command -v npu-smi &> /dev/null; then
        count=$(npu-smi info -l 2>/dev/null | grep -c "NPU" || echo "0")
    fi
    
    if [ "$count" -eq 0 ]; then
        count=$(ls -1 /dev/davinci* 2>/dev/null | grep -c "davinci" || echo "0")
    fi
    
    echo "$count"
}

get_npu_memory() {
    local memory="unknown"
    if command -v npu-smi &> /dev/null; then
        memory=$(npu-smi info -t memory -i 0 -c 0 2>/dev/null | grep "Total" | awk '{print $3}' || echo "unknown")
    fi
    echo "$memory"
}

find_free_npu() {
    local free_devices=()
    
    if ! command -v npu-smi &> /dev/null; then
        echo "0"
        return
    fi
    
    local npu_info=$(npu-smi info 2>/dev/null)
    
    while IFS= read -r line; do
        if echo "$line" | grep -q "No running processes found in NPU"; then
            local device_num=$(echo "$line" | grep -oP 'No running processes found in NPU \K[0-9]+' || echo "$line" | sed -n 's/.*No running processes found in NPU \([0-9]*\).*/\1/p')
            if [ -n "$device_num" ]; then
                free_devices+=($device_num)
            fi
        fi
    done <<< "$npu_info"
    
    if [ ${#free_devices[@]} -eq 0 ]; then
        echo ""
    else
        echo "${free_devices[0]}"
    fi
}

main() {
    local platform=$(detect_platform)
    local npu_count=$(get_npu_count)
    local npu_memory=$(get_npu_memory)
    local free_device=$(find_free_npu)
    
    echo "PLATFORM=$platform"
    echo "NPU_COUNT=$npu_count"
    echo "NPU_MEMORY=$npu_memory"
    echo "FREE_DEVICE=$free_device"
    
    if [ "$platform" == "unknown" ]; then
        echo "WARNING: Could not detect NPU platform. Please ensure NPU drivers are installed." >&2
    fi
    
    if [ "$npu_count" -eq 0 ]; then
        echo "WARNING: No NPU devices detected." >&2
    fi
    
    if [ -z "$free_device" ]; then
        echo "WARNING: No free NPU devices available." >&2
    fi
    
    exit 0
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
