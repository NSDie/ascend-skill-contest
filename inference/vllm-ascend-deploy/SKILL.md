# vLLM-Ascend Deployment Skill

## 概述

这个技能帮助用户在华为昇腾NPU（800I A2/A3）平台上部署vLLM推理服务。它会自动检测NPU平台、识别空闲设备、拉取正确的Docker镜像并启动vLLM服务。

## 核心功能

### 1. 自动平台检测
- 自动识别NPU平台类型（A2或A3）
- 检测NPU设备数量和内存信息
- **新增：自动检测空闲NPU设备**

### 2. 智能设备选择
- 使用`npu-smi info`命令检测NPU状态
- 正则匹配"No running processes found in NPU X"识别空闲设备
- 自动设置`ASCEND_RT_VISIBLE_DEVICES`环境变量
- 避免与其他进程冲突

### 3. Docker镜像管理
- **改进：使用`docker inspect`检查镜像是否存在**
- 避免重复下载，节省时间
- 根据平台自动选择正确的镜像标签
  - A2平台：`quay.io/ascend/vllm-ascend:v0.17.0rc1`
  - A3平台：`quay.io/ascend/vllm-ascend:v0.17.0rc1-a3`

### 4. 完整的部署流程
- 自动启动Docker容器
- 配置NPU设备映射
- 启动vLLM推理服务
- 健康检查和服务验证

## 使用方法

### 基本用法

```bash
cd /home/vllm-ascend-deploy/scripts
bash deploy_vllm.sh --model-path /path/to/model
```

### 完整参数

```bash
bash deploy_vllm.sh \
  --model-path /path/to/model \
  --image-tag v0.17.0rc1 \
  --container-name vllm-ascend \
  --port 8000
```

### 参数说明

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| --model-path | 是 | - | 模型权重的绝对路径 |
| --image-tag | 否 | v0.17.0rc1 | vLLM-Ascend镜像标签 |
| --container-name | 否 | vllm-ascend | Docker容器名称 |
| --port | 否 | 8000 | 服务端口 |
| --devices | 否 | 自动检测 | NPU设备ID（逗号分隔） |

## 部署示例

### 示例1：部署Qwen3-0.6B模型

```bash
bash deploy_vllm.sh --model-path /home/qwen3-0.6b
```

**执行流程**：
1. 检测NPU平台（A2或A3）
2. 检测空闲NPU设备（例如：NPU 7）
3. 检查Docker镜像是否存在
4. 启动Docker容器，映射NPU设备
5. 在容器内启动vLLM服务
6. 等待服务就绪

### 示例2：指定容器名称和端口

```bash
bash deploy_vllm.sh \
  --model-path /home/qwen3-0.6b \
  --container-name vllm-qwen3 \
  --port 8001
```

### 示例3：手动指定NPU设备

```bash
bash deploy_vllm.sh \
  --model-path /home/qwen3-0.6b \
  --devices 7
```

## 关键改进（基于实际部署经验）

### 1. 空闲NPU检测逻辑

**问题**：原逻辑硬编码使用设备7，可能与其他进程冲突

**解决方案**：
```bash
# 使用npu-smi info检测空闲设备
npu_info=$(npu-smi info 2>/dev/null)

# 正则匹配"No running processes found in NPU X"
while IFS= read -r line; do
    if echo "$line" | grep -q "No running processes found in NPU"; then
        device_num=$(echo "$line" | grep -oP 'No running processes found in NPU \K[0-9]+')
        FREE_DEVICES+=($device_num)
    fi
done <<< "$npu_info"
```

### 2. Docker镜像检查优化

**问题**：原逻辑使用grep匹配可能误判

**解决方案**：
```bash
# 使用docker inspect准确检查镜像是否存在
if docker inspect --type=image "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "Image already exists locally"
else
    docker pull "${IMAGE_NAME}"
fi
```

### 3. 环境变量设置

**关键**：在三个地方设置`ASCEND_RT_VISIBLE_DEVICES`

1. **宿主机**：
```bash
export ASCEND_RT_VISIBLE_DEVICES=${DEVICE_ID}
```

2. **Docker容器**：
```bash
-e ASCEND_RT_VISIBLE_DEVICES="${DEVICE_ID}"
```

3. **vLLM服务**：
```bash
docker exec -d "${CONTAINER_NAME}" bash -c "
    export ASCEND_RT_VISIBLE_DEVICES=${device_id} && \
    python -m vllm.entrypoints.openai.api_server ...
"
```

## 脚本结构

```
vllm-ascend-deploy/
├── SKILL.md                          # 本文档
├── scripts/
│   ├── detect_platform.sh            # 平台检测和空闲设备识别
│   ├── start_container.sh            # Docker容器管理
│   └── deploy_vllm.sh                # 主部署脚本
└── references/
    ├── configuration.md              # 配置参数参考
    └── troubleshooting.md            # 故障排查指南
```

## 验证部署

### 1. 检查服务状态

```bash
curl http://localhost:8000/v1/models
```

### 2. 测试推理

```bash
curl http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/home/qwen3-0.6b",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'
```

### 3. 查看日志

```bash
docker logs vllm-ascend
```

### 4. 检查NPU使用

```bash
npu-smi info
```

## 故障排查

### 问题1：没有空闲NPU设备

**错误信息**：
```
Error: No free NPU devices available
```

**解决方案**：
```bash
# 检查NPU进程
npu-smi info

# 停止占用设备的容器
docker stop vllm-ascend
docker rm vllm-ascend

# 或杀死进程
kill -9 <PID>
```

### 问题2：Docker镜像拉取失败

**解决方案**：
```bash
# 手动拉取镜像
docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1

# 或使用代理
export http_proxy=http://proxy:port
export https_proxy=http://proxy:port
```

### 问题3：服务启动失败

**解决方案**：
```bash
# 查看容器日志
docker logs vllm-ascend

# 检查NPU设备
ls -la /dev/davinci*

# 验证环境变量
docker exec vllm-ascend env | grep ASCEND_RT_VISIBLE_DEVICES
```

## 最佳实践

1. **部署前检查**：
   - 确认NPU驱动已安装
   - 确认Docker服务正常运行
   - 确认模型路径正确

2. **资源管理**：
   - 单卡部署使用默认配置
   - 多卡部署使用`--devices`参数
   - 监控NPU内存使用

3. **日志管理**：
   - 定期检查容器日志
   - 保存部署日志用于问题排查

4. **服务验证**：
   - 部署后立即测试API
   - 监控服务健康状态

## 更新日志

### v2.0 (2026-03-19)
- ✅ 新增自动检测空闲NPU设备功能
- ✅ 改进Docker镜像检查逻辑（使用docker inspect）
- ✅ 添加ASCEND_RT_VISIBLE_DEVICES环境变量设置
- ✅ 优化部署流程，避免设备冲突
- ✅ 基于实际部署经验全面优化

### v1.0 (初始版本)
- 基本的NPU平台检测
- Docker容器启动
- vLLM服务部署
