# NextPaste Server 安装和运行指南

## 前置要求

- Go 1.23 或更高版本
- Node.js 16 或更高版本
- Wails CLI v2

## 安装步骤

### 1. 安装 Go 依赖

```bash
cd server
go get golang.design/x/clipboard
go mod tidy
```

### 2. 安装前端依赖

```bash
cd frontend
npm install
```

### 3. 开发模式运行

```bash
# 在 server 目录下
wails dev
```

### 4. 构建生产版本

```bash
# 在 server 目录下
wails build
```

## 功能说明

### 核心功能

1. **WebSocket 服务器**
   - 支持多客户端连接
   - 实现 NextPaste 自定义协议
   - 自动心跳保活

2. **剪贴板监听**
   - 实时监听系统剪贴板变化
   - 支持文本和图片类型
   - 自动广播给所有连接的客户端

3. **用户界面**
   - 服务器配置（地址、端口）
   - 连接信息显示（IP 地址列表、客户端数量）
   - 实时日志查看（支持级别过滤）

### 使用流程

1. 启动应用
2. 配置监听地址和端口（默认 0.0.0.0:8080）
3. 点击"启动服务"按钮
4. 在"连接信息"区域查看可用的 WebSocket 地址
5. 复制连接地址到 HarmonyOS 客户端
6. 开始使用跨设备剪贴板同步功能

## 技术架构

### 后端 (Go)

- `internal/protocol` - 协议定义和消息处理
- `internal/websocket` - WebSocket 服务器实现
- `internal/clipboard` - 剪贴板监听服务
- `app.go` - 主应用逻辑，集成所有服务

### 前端 (Vue 3 + TypeScript)

- `components/ServerConfig.vue` - 服务器配置组件
- `components/ConnectionInfo.vue` - 连接信息显示组件
- `components/LogViewer.vue` - 日志查看组件
- `components/StatusIndicator.vue` - 状态指示器组件

## 注意事项

1. **防火墙设置**：确保 WebSocket 端口（默认 8080）在防火墙中开放
2. **网络环境**：客户端和服务器需要在同一局域网内，或服务器有公网 IP
3. **剪贴板权限**：首次运行时可能需要授予剪贴板访问权限

## 故障排除

### 服务器无法启动

- 检查端口是否被占用
- 确保有足够的系统权限
- 查看日志中的错误信息

### 客户端无法连接

- 确认服务器正在运行
- 检查网络连接
- 验证 WebSocket 地址是否正确
- 检查防火墙设置

### 剪贴板不同步

- 确认剪贴板监听已启动
- 检查日志中是否有错误
- 验证客户端已成功握手

## 开发说明

### 添加新功能

1. 后端：在 `app.go` 中添加新方法，并在 `main.go` 的 `Bind` 中注册
2. 前端：在 `wailsjs/go/main/App.js` 中会自动生成对应的 TypeScript 绑定
3. 使用 `runtime.EventsEmit` 发送事件到前端
4. 使用 `EventsOn` 在前端监听事件

### 调试技巧

- 使用 `wails dev` 启动开发模式，支持热重载
- 在浏览器开发者工具中查看前端日志
- 在终端查看 Go 后端日志
- 使用 `console.log` 和 `fmt.Println` 进行调试

## 许可证

与 NextPaste 项目保持一致

