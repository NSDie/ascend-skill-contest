# Troubleshooting Guide

This document provides solutions for common issues encountered during vLLM-Ascend deployment.

## Platform Detection Issues

### Issue: Platform detection fails

**Symptoms:**
- Error message: "Could not detect NPU platform"
- Script exits with error code 1

**Possible Causes:**
1. NPU drivers not installed
2. npu-smi tool not available
3. Insufficient permissions

**Solutions:**

1. **Check NPU drivers:**
   ```bash
   ls -la /dev/davinci*
   ```
   If no devices are listed, install Ascend NPU drivers.

2. **Verify npu-smi installation:**
   ```bash
   which npu-smi
   npu-smi info
   ```

3. **Check permissions:**
   ```bash
   groups $USER
   ```
   Ensure user is in the `ascend` or appropriate group.

### Issue: No NPU devices detected

**Symptoms:**
- Error message: "No NPU devices detected"
- NPU_COUNT=0

**Solutions:**

1. **Check device files:**
   ```bash
   ls -la /dev/davinci*
   ```

2. **Check driver status:**
   ```bash
   dmesg | grep -i davinci
   ```

3. **Restart NPU driver:**
   ```bash
   sudo /usr/local/Ascend/driver/tools/ascend-dmi -i
   ```

## Docker Issues

### Issue: Docker daemon not running

**Symptoms:**
- Error: "Docker daemon is not running"
- Docker commands fail

**Solutions:**

1. **Start Docker service:**
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

2. **Check Docker status:**
   ```bash
   sudo systemctl status docker
   ```

### Issue: Permission denied for Docker

**Symptoms:**
- Error: "permission denied while trying to connect to Docker daemon"

**Solutions:**

1. **Add user to docker group:**
   ```bash
   sudo usermod -aG docker $USER
   ```
   Log out and log back in for changes to take effect.

2. **Use sudo:**
   ```bash
   sudo docker ps
   ```

### Issue: Container fails to start

**Symptoms:**
- Container exits immediately
- Error in container logs

**Solutions:**

1. **Check container logs:**
   ```bash
   docker logs <container-name>
   ```

2. **Verify device permissions:**
   ```bash
   ls -la /dev/davinci*
   ls -la /dev/davinci_manager
   ls -la /dev/hisi_hdc
   ```

3. **Check mount points:**
   ```bash
   ls -la /usr/local/Ascend/driver
   ls -la /usr/local/dcmi
   ```

### Issue: Image pull fails

**Symptoms:**
- Error: "Failed to pull Docker image"
- Network timeout

**Solutions:**

1. **Check network connectivity:**
   ```bash
   ping quay.io
   ```

2. **Configure proxy:**
   ```bash
   export http_proxy=http://proxy.example.com:8080
   export https_proxy=http://proxy.example.com:8080
   ```

3. **Manually pull image:**
   ```bash
   # For A2 platform
   docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1
   
   # For A3 platform
   docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1-a3
   ```

4. **Use alternative registry:**
   Modify the image URL in `start_container.sh` to use a mirror registry.

## vLLM Service Issues

### Issue: Service fails to start

**Symptoms:**
- Container running but service not accessible
- Health check fails

**Solutions:**

1. **Check container logs:**
   ```bash
   docker logs <container-name>
   ```

2. **Verify model path:**
   ```bash
   ls -la <model-path>
   ```
   Ensure model files are accessible.

3. **Check Python environment:**
   ```bash
   docker exec -it <container-name> python -c "import vllm; print(vllm.__version__)"
   ```

### Issue: Out of memory error

**Symptoms:**
- Error: "CUDA out of memory" or "NPU out of memory"
- Service crashes during model loading

**Solutions:**

1. **Reduce memory utilization:**
   ```bash
   --gpu-memory-utilization 0.8
   ```

2. **Decrease max sequence length:**
   ```bash
   --max-model-len 2048
   ```

3. **Reduce batch size:**
   ```bash
   --max-num-seqs 64
   ```

4. **Use tensor parallelism:**
   ```bash
   --tensor-parallel-size 4
   ```

### Issue: Slow inference performance

**Symptoms:**
- High latency
- Low throughput

**Solutions:**

1. **Optimize tensor parallelism:**
   Match tensor-parallel-size with NPU count.

2. **Adjust batch size:**
   ```bash
   --max-num-seqs 256
   --max-num-batched-tokens 16384
   ```

3. **Use appropriate precision:**
   - A2: FP16
   - A3: BF16

### Issue: Model loading fails

**Symptoms:**
- Error during model initialization
- Unsupported model format

**Solutions:**

1. **Verify model format:**
   Ensure model is in HuggingFace format or compatible format.

2. **Check model files:**
   ```bash
   ls -la <model-path>
   ```
   Required files: config.json, pytorch_model.bin or model.safetensors

3. **Enable trust remote code:**
   ```bash
   --trust-remote-code
   ```

## Network Issues

### Issue: Service not accessible

**Symptoms:**
- Connection refused
- Timeout when accessing API

**Solutions:**

1. **Check service status:**
   ```bash
   curl http://localhost:8000/health
   ```

2. **Verify port binding:**
   ```bash
   netstat -tulpn | grep 8000
   ```

3. **Check firewall:**
   ```bash
   sudo firewall-cmd --list-ports
   sudo firewall-cmd --add-port=8000/tcp
   ```

### Issue: API requests fail

**Symptoms:**
- 500 Internal Server Error
- Invalid response format

**Solutions:**

1. **Check request format:**
   ```bash
   curl http://localhost:8000/v1/completions \
     -H "Content-Type: application/json" \
     -d '{"model": "<model-name>", "prompt": "Hello", "max_tokens": 50}'
   ```

2. **Verify model name:**
   Use the correct model name from the model directory.

3. **Check logs for errors:**
   ```bash
   docker logs <container-name> --tail 100
   ```

## Performance Tuning

### Optimize for Throughput

```bash
--max-num-seqs 256
--max-num-batched-tokens 16384
--gpu-memory-utilization 0.95
```

### Optimize for Latency

```bash
--max-num-seqs 1
--max-num-batched-tokens 2048
--gpu-memory-utilization 0.9
```

### Optimize for Large Models

```bash
--tensor-parallel-size 4
--pipeline-parallel-size 2
--max-model-len 2048
--gpu-memory-utilization 0.95
```

## Getting Help

If issues persist:

1. **Collect diagnostic information:**
   ```bash
   # System information
   uname -a
   cat /etc/os-release
   
   # NPU information
   npu-smi info -l
   npu-smi info -t board -i 0
   
   # Docker information
   docker version
   docker info
   
   # Container logs
   docker logs <container-name>
   ```

2. **Check official documentation:**
   - vLLM documentation: https://vllm.readthedocs.io/
   - Ascend documentation: https://www.hiascend.com/

3. **Contact support:**
   Provide the diagnostic information collected above.
