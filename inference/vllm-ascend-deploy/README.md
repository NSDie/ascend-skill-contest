# vLLM-Ascend Deploy Skill v2.0

## 快速开始

### 1. 解压技能包

```bash
tar -xzf vllm-ascend-deploy-v2.0.tar.gz
```

### 2. 部署模型

```bash
bash vllm-ascend-deploy/scripts/deploy_vllm.sh --model-path /path/to/model
```

## 核心功能

### ✅ 自动检测空闲NPU设备
- 使用`npu-smi info`检测NPU状态
- 正则匹配"No running processes found in NPU X"识别空闲设备
- 自动设置`ASCEND_RT_VISIBLE_DEVICES`环境变量
- 避免设备冲突

### ✅ 智能镜像管理
- 使用`docker inspect`准确检查镜像是否存在
- 避免重复下载，节省时间
- 根据平台自动选择正确的镜像标签

### ✅ 完整的部署流程
- 自动启动Docker容器
- 配置NPU设备映射
- 启动vLLM推理服务
- 健康检查和服务验证

## 使用示例

### 基本部署

```bash
bash vllm-ascend-deploy/scripts/deploy_vllm.sh \
    --model-path /home/Qwen3-0.6B/
```

### 自定义配置

```bash
bash vllm-ascend-deploy/scripts/deploy_vllm.sh \
    --model-path /home/Qwen3-0.6B/ \
    --container-name vllm-qwen3 \
    --port 8001
```

### 手动指定设备

```bash
bash vllm-ascend-deploy/scripts/deploy_vllm.sh \
    --model-path /home/Qwen3-0.6B/ \
    --devices 7
```

## 参数说明

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| --model-path | 是 | - | 模型权重的绝对路径 |
| --image-tag | 否 | v0.17.0rc1 | vLLM-Ascend镜像标签 |
| --container-name | 否 | vllm-ascend | Docker容器名称 |
| --port | 否 | 8000 | 服务端口 |
| --devices | 否 | 自动检测 | NPU设备ID（逗号分隔） |

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
    "model": "/home/Qwen3-0.6B/",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'
```

### 3. 查看日志

```bash
docker logs vllm-ascend
```

## 故障排查

### 问题：没有空闲NPU设备

```bash
# 检查NPU进程
npu-smi info

# 停止占用设备的容器
docker stop vllm-ascend
docker rm vllm-ascend
```

### 问题：Docker镜像拉取失败

```bash
# 设置代理
export http_proxy=http://proxy:port
export https_proxy=http://proxy:port

# 手动拉取镜像
docker pull quay.io/ascend/vllm-ascend:v0.17.0rc1
```

## 技术支持

- 详细文档：`vllm-ascend-deploy/SKILL.md`
- 配置参考：`vllm-ascend-deploy/references/configuration.md`
- 故障排查：`vllm-ascend-deploy/references/troubleshooting.md`

## 版本历史

### v2.0 (2026-03-19)
- ✅ 新增自动检测空闲NPU设备功能
- ✅ 改进Docker镜像检查逻辑
- ✅ 添加ASCEND_RT_VISIBLE_DEVICES环境变量设置
- ✅ 优化部署流程，避免设备冲突
- ✅ 基于实际部署经验全面优化

### v1.0 (初始版本)
- 基本的NPU平台检测
- Docker容器启动
- vLLM服务部署
