# NextPaste Server

NextPaste 的 PC 服务端应用，基于 Wails 框架开发，提供 WebSocket 服务器和剪贴板监听功能。

## 功能特性

> 因为跨平台支持可能无法监听所有的图片写入，在Windows平台测试使用系统自带和QQ截图正常，微信截图无法监听变化。

### 🚀 核心功能

- **WebSocket 服务器**：支持多客户端连接，实现跨设备剪贴板同步
- **剪贴板监听**：实时监听系统剪贴板变化（文本和图片）
- **自动广播**：剪贴板变化自动同步到所有连接的客户端
- **协议支持**：完整实现 NextPaste 自定义协议（握手、同步、心跳）

### 💻 用户界面

- **服务器配置**：可配置监听地址和端口
- **连接信息**：自动检测并显示所有可用的 WebSocket 连接地址
- **一键复制**：快速复制连接地址到剪贴板
- **实时日志**：支持日志级别过滤和清空
- **状态监控**：实时显示服务运行状态和客户端数量

## 快速开始

### 前置要求

- Go 1.23+
- Node.js 16+
- Wails CLI v2

### 安装依赖

```bash
# 安装 Go 依赖
go get golang.design/x/clipboard
go mod tidy

# 安装前端依赖
cd frontend
npm install
cd ..
```

### 开发模式

```bash
wails dev
```

### 构建应用

```bash
wails build
```

## 使用说明

1. **启动应用**：运行构建后的可执行文件
2. **配置服务器**：监听地址默认 `0.0.0.0`，端口默认 `8080`
3. **启动服务**：点击"启动服务"按钮
4. **获取连接地址**：在"连接信息"区域查看所有可用的 WebSocket 地址
5. **连接客户端**：复制连接地址到 HarmonyOS 客户端
6. **开始同步**：剪贴板内容将自动在所有设备间同步

## 技术架构

### 后端技术栈

- **Go 1.23**：主要编程语言
- **Wails v2**：桌面应用框架
- **gorilla/websocket**：WebSocket 实现
- **golang.design/x/clipboard**：跨平台剪贴板库

### 前端技术栈

- **Vue 3**：渐进式 JavaScript 框架
- **TypeScript**：类型安全
- **Vite**：快速的前端构建工具

## 故障排除

### 端口被占用

如果默认端口 8080 被占用，请修改为其他端口（如 8081、9000 等）。

### 防火墙问题

确保 WebSocket 端口在 Windows 防火墙中开放：

```powershell
# 以管理员身份运行
netsh advfirewall firewall add rule name="NextPaste Server" dir=in action=allow protocol=TCP localport=8080
```

## 开发指南

详见 [SETUP.md](./SETUP.md)

## 相关链接

- [Wails 官方文档](https://wails.io/)
- [Vue 3 文档](https://vuejs.org/)
- [NextPaste 协议文档](../docs/protocol.md)
