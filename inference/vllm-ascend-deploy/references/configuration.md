# vLLM-Ascend 配置参数参考

## 环境变量

### 核心环境变量

| 变量名 | 说明 | 示例值 | 必需 |
|--------|------|--------|------|
| `ASCEND_RT_VISIBLE_DEVICES` | 指定使用的NPU设备ID | `0`, `1`, `0,1,2,3` | 是 |
| `MODEL_PATH` | 模型权重路径 | `/home/user/model` | 是 |
| `PORT` | 服务端口 | `8000` | 否 |

### 代理设置

| 变量名 | 说明 | 示例值 |
|--------|------|--------|
| `http_proxy` | HTTP代理地址 | `http://proxy.example.com:8080` |
| `https_proxy` | HTTPS代理地址 | `http://proxy.example.com:8080` |

## Docker镜像配置

### 镜像版本

| 平台 | 镜像标签 | 完整镜像名称 |
|------|----------|--------------|
| Atlas 800I A2 | `v0.17.0rc1` | `quay.io/ascend/vllm-ascend:v0.17.0rc1` |
| Atlas 800I A3 | `v0.17.0rc1-a3` | `quay.io/ascend/vllm-ascend:v0.17.0rc1-a3` |

### 镜像拉取

```bash
# A2平台
docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1

# A3平台
docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1-a3
```

### 镜像检查

**推荐方法**：使用`docker inspect`准确检查
```bash
if docker inspect --type=image "quay.io/ascend/vllm-ascend:v0.17.0rc1" >/dev/null 2>&1; then
    echo "镜像已存在"
else
    echo "镜像不存在，需要拉取"
fi
```

**不推荐方法**：使用`docker images | grep`（可能误判）
```bash
# ❌ 不推荐：可能匹配到其他版本
docker images | grep vllm-ascend
```

## Docker容器配置

### 必需的设备映射

```bash
--device=/dev/davinci_manager    # NPU管理设备
--device=/dev/hisi_hdc           # HDC设备
--device=/dev/devmm_svm          # SVM设备
--device=/dev/davinci${DEVICE_ID} # NPU计算设备
```

### 必需的卷挂载

```bash
-v /usr/local/Ascend/driver:/usr/local/Ascend/driver     # NPU驱动
-v /usr/local/dcmi:/usr/local/dcmi                       # DCMI工具
-v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi         # NPU管理工具
-v /etc/ascend_install.info:/etc/ascend_install.info     # 安装信息
-v /usr/local/sbin:/usr/local/sbin                       # 系统工具
-v ${MODEL_PATH}:${MODEL_PATH}                           # 模型权重
-v /home:/home                                           # 工作目录
-v /tmp:/tmp                                             # 临时文件
-v /mnt:/mnt                                             # 数据挂载点
```

### 容器资源配置

```bash
--net=host              # 使用主机网络
--shm-size=500g         # 共享内存大小
--privileged=true       # 特权模式
-w /home                # 工作目录
```

## vLLM服务配置

### 基本参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--model` | - | 模型路径（必需） |
| `--host` | `0.0.0.0` | 监听地址 |
| `--port` | `8000` | 服务端口 |
| `--dtype` | `float16` | 数据类型 |

### 性能优化参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--tensor-parallel-size` | `1` | 张量并行大小 |
| `--max-model-len` | `4096` | 最大序列长度 |
| `--gpu-memory-utilization` | `0.9` | GPU内存利用率 |
| `--trust-remote-code` | - | 信任远程代码 |

### 配置示例

**单卡部署**：
```bash
python -m vllm.entrypoints.openai.api_server \
    --model /path/to/model \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype float16 \
    --tensor-parallel-size 1 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.9 \
    --trust-remote-code
```

**多卡部署**：
```bash
export ASCEND_RT_VISIBLE_DEVICES=0,1,2,3

python -m vllm.entrypoints.openai.api_server \
    --model /path/to/model \
    --host 0.0.0.0 \
    --port 8000 \
    --dtype float16 \
    --tensor-parallel-size 4 \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.9 \
    --trust-remote-code
```

## NPU设备选择

### 自动检测空闲设备

**原理**：使用`npu-smi info`命令检测空闲设备

```bash
# 获取NPU信息
npu_info=$(npu-smi info 2>/dev/null)

# 解析空闲设备
while IFS= read -r line; do
    if echo "$line" | grep -q "No running processes found in NPU"; then
        device_num=$(echo "$line" | grep -oP 'No running processes found in NPU \K[0-9]+')
        echo "空闲设备: $device_num"
    fi
done <<< "$npu_info"
```

### 手动指定设备

```bash
# 单设备
export ASCEND_RT_VISIBLE_DEVICES=7

# 多设备
export ASCEND_RT_VISIBLE_DEVICES=0,1,2,3
```

### 设备检查命令

```bash
# 查看所有NPU设备
npu-smi info -l

# 查看特定设备进程
npu-smi info proc -i 0 -c 0

# 查看设备内存
npu-smi info -t memory -i 0 -c 0

# 查看设备利用率
npu-smi info -t usages -i 0 -c 0
```

## 部署脚本参数

### deploy_vllm.sh 参数

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `--model-path` | 是 | - | 模型权重绝对路径 |
| `--image-tag` | 否 | `v0.17.0rc1` | Docker镜像标签 |
| `--container-name` | 否 | `vllm-ascend` | 容器名称 |
| `--port` | 否 | `8000` | 服务端口 |
| `--devices` | 否 | 自动检测 | NPU设备ID（逗号分隔） |

### start_container.sh 参数

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `--image-tag` | 是 | - | Docker镜像标签 |
| `--model-path` | 是 | - | 模型权重绝对路径 |
| `--platform` | 是 | - | NPU平台（A2/A3） |
| `--device-id` | 是 | - | NPU设备ID |
| `--container-name` | 否 | `vllm-ascend` | 容器名称 |
| `--port` | 否 | `8000` | 服务端口 |
| `--devices` | 否 | - | NPU设备ID（逗号分隔） |

## 平台检测

### 检测方法

1. **使用npu-smi**（推荐）：
```bash
npu-smi info -t product -i 0 -c 0
```

2. **使用dmidecode**：
```bash
sudo dmidecode -t system | grep -i "product"
```

3. **检查安装信息**：
```bash
cat /etc/ascend_install.info
```

### 平台标识

| 平台 | 标识字符串 | 镜像后缀 |
|------|-----------|---------|
| Atlas 800I A2 | `A2`, `Ascend 910B1` | 无 |
| Atlas 800I A3 | `A3`, `Ascend 910B2` | `-a3` |

## 完整部署示例

### 示例1：基本部署

```bash
#!/bin/bash

# 设置模型路径
MODEL_PATH="/home/y30015289/qwen3-0.6b"

# 执行部署
cd /home/y30015289/vllm-ascend-deploy/scripts
bash deploy_vllm.sh --model-path ${MODEL_PATH}
```

### 示例2：自定义配置

```bash
#!/bin/bash

# 配置参数
MODEL_PATH="/home/y30015289/qwen3-0.6b"
CONTAINER_NAME="vllm-qwen3"
PORT="8001"
IMAGE_TAG="v0.17.0rc1"

# 执行部署
cd /home/y30015289/vllm-ascend-deploy/scripts
bash deploy_vllm.sh \
    --model-path ${MODEL_PATH} \
    --container-name ${CONTAINER_NAME} \
    --port ${PORT} \
    --image-tag ${IMAGE_TAG}
```

### 示例3：手动指定设备

```bash
#!/bin/bash

# 配置参数
MODEL_PATH="/home/y30015289/qwen3-0.6b"
DEVICES="7"  # 使用NPU 7

# 执行部署
cd /home/y30015289/vllm-ascend-deploy/scripts
bash deploy_vllm.sh \
    --model-path ${MODEL_PATH} \
    --devices ${DEVICES}
```

## 常见配置问题

### 问题1：设备冲突

**症状**：
```
Error: No free NPU devices available
```

**解决方案**：
```bash
# 检查设备使用情况
npu-smi info

# 停止占用设备的容器
docker stop vllm-ascend
docker rm vllm-ascend

# 或手动指定其他设备
bash deploy_vllm.sh --model-path /path/to/model --devices 5
```

### 问题2：内存不足

**症状**：
```
RuntimeError: NPU out of memory
```

**解决方案**：
```bash
# 降低内存利用率
--gpu-memory-utilization 0.8

# 或减少最大序列长度
--max-model-len 2048
```

### 问题3：镜像拉取失败

**解决方案**：
```bash
# 设置代理
export http_proxy=http://proxy:port
export https_proxy=http://proxy:port

# 手动拉取镜像
docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1
```

## 性能调优建议

### 单卡部署

```bash
--tensor-parallel-size 1
--max-model-len 4096
--gpu-memory-utilization 0.9
```

### 多卡部署

```bash
export ASCEND_RT_VISIBLE_DEVICES=0,1,2,3
--tensor-parallel-size 4
--max-model-len 8192
--gpu-memory-utilization 0.9
```

### 大模型部署

```bash
--max-model-len 2048        # 减少序列长度
--gpu-memory-utilization 0.95  # 提高内存利用率
--dtype float16              # 使用半精度
```
