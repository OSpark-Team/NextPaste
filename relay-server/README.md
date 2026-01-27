# NextPaste 中继服务器

纯命令行的 WebSocket 中继服务器，支持房间隔离的剪贴板数据转发。

## 功能特性

- ✅ **房间隔离**：通过 roomID 实现多个独立的剪贴板共享空间 (V1 与 V2 物理隔离)
- ✅ **纯转发**：不处理剪贴板，只负责消息转发
- ✅ **无限房间**：支持无限数量的房间，自动创建和清理
- ✅ **多协议支持**：
  - **V1 (Legacy)**: 支持 JSON 协议 (`/ws/{roomID}`)
  - **V2 (Recommended)**: 支持二进制协议 V1.1 (`/v2/ws/{roomID}`)
- ✅ **自动清理**：房间为空时自动删除
- ✅ **并发安全**：支持高并发连接

## 使用场景

解决局域网内网限制问题，通过公网中继服务器实现跨网络的剪贴板共享。

**示例场景**：
- 公司内网电脑 A → 公网中继服务器（房间：team-123）← 家里电脑 B
- 手机 → 公网中继服务器（房间：my-devices）← 平板

## 安装

### 方式1：从源码编译

```bash
# 克隆仓库
git clone https://github.com/OSpark-Team/NextPaste.git
cd NextPaste/relay-server

# 下载依赖
go mod download

# 编译
go build -o nextpaste-relay

# 运行
./nextpaste-relay
```

### 方式2：直接运行

```bash
go run .
```

## 命令行参数

```
--host, -h    监听地址（默认：0.0.0.0）
--port, -p    监听端口（默认：8080）
--help        显示帮助信息
```

## 使用示例

### 启动服务器

```bash
# 使用默认配置（0.0.0.0:8080）
./nextpaste-relay

# 指定端口
./nextpaste-relay --port 9000

# 仅本地访问
./nextpaste-relay --host 127.0.0.1 --port 8080

# 公网访问（需要配置防火墙）
./nextpaste-relay --host 0.0.0.0 --port 8080
```

### 客户端连接

**V2 连接 (V1.1 二进制协议 - 推荐)**：
```
ws://<host>:<port>/v2/ws/<roomID>
```

**V1 连接 (V1.0 JSON协议 - 兼容)**：
```
ws://<host>:<port>/ws/<roomID>
```

**示例**：
```
ws://localhost:8080/v2/ws/my-room-123      (V2)
ws://example.com:8080/ws/team-workspace    (V1)
```

### 在 NextPaste 客户端中使用

1. **HarmonyOS 客户端**：
   - 打开应用
   - 输入服务器地址：`ws://your-server.com:8080/ws/your-room-id`
   - 点击连接

2. **Windows 客户端**：
   - 打开应用
   - 切换到"客户端模式"
   - 输入服务器地址：`ws://your-server.com:8080/ws/your-room-id`
   - 点击连接

## 房间隔离说明

- 每个 `roomID` 是一个独立的剪贴板共享空间
- 同一个 `roomID` 内的所有客户端可以互相共享剪贴板
- **版本隔离**：V1 接口 (`/ws/`) 和 V2 接口 (`/v2/ws/`) 即使使用相同的 `roomID`，实际上也是**完全隔离的两个房间**。V1 客户端无法与 V2 客户端通信。
- `roomID` 可以是任意字符串（建议使用有意义的名称）

**示例**：
```
房间 "team-dev" (V2)    → 客户端 A、B (V2协议)
房间 "team-dev" (V1)    → 客户端 C、D (V1协议) 
(A/B 与 C/D 互不通)
```

## API 端点

### V2 WebSocket 连接 (二进制协议)
- **路径**：`/v2/ws/{roomID}`
- **协议**：WebSocket (Binary Frames)
- **说明**：连接到指定房间 (V2隔离)

### V1 WebSocket 连接 (JSON协议)
- **路径**：`/ws/{roomID}`
- **协议**：WebSocket (Text Frames)
- **说明**：连接到指定房间 (V1隔离)

### 健康检查
- **路径**：`/health`
- **方法**：GET
- **响应**：`{"status":"ok","service":"nextpaste-relay"}`

### 首页
- **路径**：`/`
- **方法**：GET
- **说明**：显示服务器信息和使用说明

## 日志说明

服务器会输出以下日志：

```
🚀 NextPaste 中继服务器启动
📡 监听地址: 0.0.0.0:8080
🔗 连接格式: ws://0.0.0.0:8080/ws/<roomID>
💡 提示: 使用 Ctrl+C 停止服务器

🏠 创建新房间: my-room-123
✅ 新客户端连接 [房间: my-room-123] [客户端: a1b2c3d4] [来自: 192.168.1.100:54321]
📊 房间 [my-room-123] 当前客户端数: 1
📨 转发消息 [房间: my-room-123] [来自: a1b2c3d4] [大小: 1024 字节]
👋 客户端断开 [房间: my-room-123] [客户端: a1b2c3d4]
🗑️  删除空房间: my-room-123
```

## 部署建议

### 本地测试
```bash
./nextpaste-relay --host 127.0.0.1 --port 8080
```

### 局域网部署
```bash
./nextpaste-relay --host 0.0.0.0 --port 8080
```

### 公网部署（推荐使用 systemd）

创建 `/etc/systemd/system/nextpaste-relay.service`：

```ini
[Unit]
Description=NextPaste Relay Server
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/local/bin/nextpaste-relay --host 0.0.0.0 --port 8080
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

启动服务：
```bash
sudo systemctl daemon-reload
sudo systemctl enable nextpaste-relay
sudo systemctl start nextpaste-relay
sudo systemctl status nextpaste-relay
```

## 安全建议

1. **使用防火墙**：限制访问来源
2. **使用 HTTPS/WSS**：配置反向代理（Nginx/Caddy）
3. **房间密码**：使用复杂的 roomID（如 UUID）
4. **监控日志**：定期检查异常连接

## 性能

- 支持数千个并发连接
- 内存占用低（每个连接约 10KB）
- CPU 占用低（纯转发，无数据处理）

## 许可证

MIT License

## 相关链接

- [NextPaste 主项目](https://github.com/OSpark-Team/NextPaste)
- [协议文档](../docs/protocol.md)

