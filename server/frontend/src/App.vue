<script lang="ts" setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { EventsOn, EventsOff, WindowMinimise } from '../wailsjs/runtime/runtime'
import { StartServer, StopServer, GetServerStatus, GetLogs, ClearLogs, Quit, ConnectClient, DisconnectClient, GetClientStatus } from '../wailsjs/go/main/App'
import ServerConfig from './components/ServerConfig.vue'
import ClientConfig from './components/ClientConfig.vue'
import ConnectionInfo from './components/ConnectionInfo.vue'
import LogViewer from './components/LogViewer.vue'
import StatusIndicator from './components/StatusIndicator.vue'
import type { ServerConfig as ServerConfigType, ServerStatus, LogEntry } from './types'

type Mode = 'server' | 'client'

// 模式
const mode = ref<Mode>('server')

// 服务器配置
const config = ref<ServerConfigType>({
  address: '0.0.0.0',
  port: 8080
})

// 客户端配置
const clientUrl = ref('ws://localhost:8080/ws/my-room')

const status = ref<ServerStatus>({
  isRunning: false,
  clientCount: 0
})

// 客户端状态
const clientStatus = ref({
  isConnected: false,
  serverUrl: ''
})

const logs = ref<LogEntry[]>([])

// 计算当前是否有活动连接
const hasActiveConnection = computed(() => {
  return mode.value === 'server' ? status.value.isRunning : clientStatus.value.isConnected
})

// 加载配置
const loadConfig = () => {
  // 加载模式
  const savedMode = localStorage.getItem('mode')
  if (savedMode === 'server' || savedMode === 'client') {
    mode.value = savedMode
  }

  // 加载服务器配置
  const saved = localStorage.getItem('serverConfig')
  if (saved) {
    try {
      config.value = JSON.parse(saved)
    } catch (e) {
      console.error('加载配置失败:', e)
    }
  }

  // 加载客户端配置
  const savedClientUrl = localStorage.getItem('clientUrl')
  if (savedClientUrl) {
    clientUrl.value = savedClientUrl
  }
}

// 保存配置
const saveConfig = () => {
  localStorage.setItem('serverConfig', JSON.stringify(config.value))
}

const saveClientUrl = () => {
  localStorage.setItem('clientUrl', clientUrl.value)
}

const saveMode = () => {
  localStorage.setItem('mode', mode.value)
}

// 切换模式
const switchMode = (newMode: Mode) => {
  if (hasActiveConnection.value) {
    alert('请先停止当前连接')
    return
  }
  mode.value = newMode
  saveMode()
}

// 启动服务器
const handleStart = async (cfg: ServerConfigType) => {
  try {
    await StartServer(cfg.address, cfg.port)
    config.value = cfg
    saveConfig()
    await updateStatus()
  } catch (error) {
    console.error('启动服务器失败:', error)
    alert(`启动失败: ${error}`)
  }
}

// 停止服务器
const handleStop = async () => {
  try {
    await StopServer()
    await updateStatus()
  } catch (error) {
    console.error('停止服务器失败:', error)
    alert(`停止失败: ${error}`)
  }
}

// 更新状态
const updateStatus = async () => {
  try {
    const newStatus = await GetServerStatus()
    status.value = newStatus as ServerStatus
  } catch (error) {
    console.error('获取状态失败:', error)
  }
}

// 加载日志
const loadLogs = async () => {
  try {
    const logList = await GetLogs()
    logs.value = logList as LogEntry[]
  } catch (error) {
    console.error('加载日志失败:', error)
  }
}

// 清空日志
const handleClearLogs = async () => {
  try {
    await ClearLogs()
    logs.value = []
  } catch (error) {
    console.error('清空日志失败:', error)
  }
}

// 客户端连接
const handleConnect = async (url: string) => {
  try {
    await ConnectClient(url)
    clientUrl.value = url
    saveClientUrl()
    await updateClientStatus()
  } catch (error) {
    console.error('连接失败:', error)
    alert(`连接失败: ${error}`)
  }
}

// 客户端断开
const handleDisconnect = async () => {
  try {
    await DisconnectClient()
    await updateClientStatus()
  } catch (error) {
    console.error('断开失败:', error)
    alert(`断开失败: ${error}`)
  }
}

// 更新客户端状态
const updateClientStatus = async () => {
  try {
    const newStatus = await GetClientStatus()
    clientStatus.value = newStatus as any
  } catch (error) {
    console.error('获取客户端状态失败:', error)
  }
}

// 监听日志更新事件
const onLogsUpdated = (newLogs: LogEntry[]) => {
  logs.value = newLogs
}

// 窗口控制
const handleMinimize = () => {
  WindowMinimise()
}

const handleQuit = async () => {
  await Quit()
}

onMounted(() => {
  loadConfig()
  updateStatus()
  updateClientStatus()
  loadLogs()

  // 订阅日志更新事件
  EventsOn('logs:updated', onLogsUpdated)

  // 定时更新状态
  const statusInterval = setInterval(() => {
    updateStatus()
    updateClientStatus()
  }, 2000)

  onUnmounted(() => {
    clearInterval(statusInterval)
    EventsOff('logs:updated')
  })
})
</script>

<template>
  <div class="app-container">
    <!-- 自定义标题栏 -->
    <header class="app-header">
      <div class="header-drag-area"></div>
      <div class="header-content">
        <div class="header-left">
          <div class="app-logo">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M16 4H18C19.1046 4 20 4.89543 20 6V20C20 21.1046 19.1046 22 18 22H6C4.89543 22 4 21.1046 4 20V6C4 4.89543 4.89543 4 6 4H8" stroke="url(#logo-gradient)" stroke-width="2" stroke-linecap="round"/>
              <path d="M15 2H9C8.44772 2 8 2.44772 8 3V5C8 5.55228 8.44772 6 9 6H15C15.5523 6 16 5.55228 16 5V3C16 2.44772 15.5523 2 15 2Z" stroke="url(#logo-gradient)" stroke-width="2"/>
              <path d="M9 12H15M9 16H12" stroke="url(#logo-gradient)" stroke-width="2" stroke-linecap="round"/>
              <defs>
                <linearGradient id="logo-gradient" x1="4" y1="2" x2="20" y2="22" gradientUnits="userSpaceOnUse">
                  <stop stop-color="#6366f1"/>
                  <stop offset="1" stop-color="#a855f7"/>
                </linearGradient>
              </defs>
            </svg>
          </div>
          <h1 class="app-title">NextPaste Server</h1>
        </div>
        <div class="header-right">
          <StatusIndicator :is-running="hasActiveConnection" />
          <div class="window-controls">
            <button class="control-btn minimize-btn" @click="handleMinimize" title="最小化">
              <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
                <rect x="2" y="5.5" width="8" height="1" rx="0.5"/>
              </svg>
            </button>
            <button class="control-btn close-btn" @click="handleQuit" title="退出">
              <svg width="12" height="12" viewBox="0 0 12 12" fill="currentColor">
                <path d="M2.22 2.22a.75.75 0 011.06 0L6 4.94l2.72-2.72a.75.75 0 111.06 1.06L7.06 6l2.72 2.72a.75.75 0 11-1.06 1.06L6 7.06l-2.72 2.72a.75.75 0 01-1.06-1.06L4.94 6 2.22 3.28a.75.75 0 010-1.06z"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
    </header>

    <main class="app-main">
      <div class="left-panel">
        <!-- 模式切换 -->
        <div class="mode-switcher glass-card">
          <div class="mode-tabs">
            <button
              :class="['mode-tab', { active: mode === 'server' }]"
              @click="switchMode('server')"
              :disabled="hasActiveConnection"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
                <line x1="8" y1="21" x2="16" y2="21"/>
                <line x1="12" y1="17" x2="12" y2="21"/>
              </svg>
              服务器模式
            </button>
            <button
              :class="['mode-tab', { active: mode === 'client' }]"
              @click="switchMode('client')"
              :disabled="hasActiveConnection"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M17 8l4 4m0 0l-4 4m4-4H3"/>
              </svg>
              客户端模式
            </button>
          </div>
        </div>

        <!-- 服务器配置 -->
        <ServerConfig
          v-if="mode === 'server'"
          :config="config"
          :is-running="status.isRunning"
          @start="handleStart"
          @stop="handleStop"
          @update:config="saveConfig"
        />

        <!-- 客户端配置 -->
        <ClientConfig
          v-if="mode === 'client'"
          :url="clientUrl"
          :is-connected="clientStatus.isConnected"
          @connect="handleConnect"
          @disconnect="handleDisconnect"
          @update:url="saveClientUrl"
        />

        <!-- 连接信息（仅服务器模式显示） -->
        <ConnectionInfo
          v-if="mode === 'server'"
          :is-running="status.isRunning"
          :client-count="status.clientCount"
          :port="config.port"
        />
      </div>

      <div class="right-panel">
        <LogViewer
          :logs="logs"
          @clear="handleClearLogs"
        />
      </div>
    </main>
  </div>
</template>

<style scoped>
.app-container {
  width: 100%;
  height: 100vh;
  display: flex;
  flex-direction: column;
  background: linear-gradient(135deg, var(--bg-gradient-start) 0%, var(--bg-gradient-end) 100%);
  overflow: hidden;
}

.app-header {
  position: relative;
  background: var(--surface-glass);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border-bottom: 1px solid var(--border-glass);
  padding: 0 var(--spacing-lg);
  height: 60px;
  display: flex;
  align-items: center;
  --wails-draggable:drag;
}

/* 窗口拖拽区域 */
.header-drag-area {
  position: absolute;
  top: 0;
  left: 0;
  right: 120px;
  height: 100%;
  --wails-draggable: drag;
}

.header-content {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
  position: relative;
  z-index: 1;
}

.header-left {
  display: flex;
  align-items: center;
  gap: var(--spacing-md);
}

.app-logo {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  background: var(--surface-glass);
  border-radius: var(--radius-md);
  border: 1px solid var(--border-glass);
}

.app-title {
  font-size: 20px;
  font-weight: 700;
  background: linear-gradient(135deg, var(--color-primary) 0%, #a855f7 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  margin: 0;
  letter-spacing: -0.02em;
}

.header-right {
  display: flex;
  align-items: center;
  gap: var(--spacing-lg);
}

/* 窗口控制按钮 */
.window-controls {
  display: flex;
  gap: var(--spacing-sm);
}

.control-btn {
  width: 32px;
  height: 32px;
  border: none;
  border-radius: var(--radius-sm);
  background: var(--surface-glass);
  color: var(--text-secondary);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all var(--transition-fast);
}

.control-btn:hover {
  background: var(--surface-glass-hover);
  color: var(--text-primary);
}

.minimize-btn:hover {
  background: rgba(99, 102, 241, 0.2);
  color: var(--color-primary);
}

.close-btn:hover {
  background: rgba(239, 68, 68, 0.2);
  color: var(--color-error);
}

.app-main {
  flex: 1;
  display: grid;
  grid-template-columns: 380px 1fr;
  gap: var(--spacing-lg);
  padding: var(--spacing-lg);
  overflow: hidden;
}

.left-panel {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-lg);
  overflow-y: auto;
}

.right-panel {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* 模式切换器 */
.mode-switcher {
  padding: var(--spacing-md);
  animation: fadeIn 0.4s ease;
}

.mode-tabs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--spacing-sm);
  background: var(--surface-dark);
  padding: 4px;
  border-radius: var(--radius-md);
}

.mode-tab {
  padding: 12px 16px;
  border: none;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--spacing-sm);
  transition: all var(--transition-normal);
  position: relative;
}

.mode-tab:hover:not(:disabled):not(.active) {
  background: var(--surface-glass);
  color: var(--text-primary);
}

.mode-tab.active {
  background: linear-gradient(135deg, var(--color-primary) 0%, #8b5cf6 100%);
  color: white;
  box-shadow: 0 2px 8px var(--color-primary-glow);
}

.mode-tab:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
</style>
