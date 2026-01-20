<script lang="ts" setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { EventsOn, EventsOff } from '../wailsjs/runtime/runtime'
import { StartServer, StopServer, GetServerStatus, GetLogs, ClearLogs } from '../wailsjs/go/main/App'
import ServerConfig from './components/ServerConfig.vue'
import ConnectionInfo from './components/ConnectionInfo.vue'
import LogViewer from './components/LogViewer.vue'
import StatusIndicator from './components/StatusIndicator.vue'
import type { ServerConfig as ServerConfigType, ServerStatus, LogEntry } from './types'

const config = ref<ServerConfigType>({
  address: '0.0.0.0',
  port: 8080
})

const status = ref<ServerStatus>({
  isRunning: false,
  clientCount: 0
})

const logs = ref<LogEntry[]>([])

// 加载配置
const loadConfig = () => {
  const saved = localStorage.getItem('serverConfig')
  if (saved) {
    try {
      config.value = JSON.parse(saved)
    } catch (e) {
      console.error('加载配置失败:', e)
    }
  }
}

// 保存配置
const saveConfig = () => {
  localStorage.setItem('serverConfig', JSON.stringify(config.value))
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

// 监听日志更新事件
const onLogsUpdated = (newLogs: LogEntry[]) => {
  logs.value = newLogs
}

onMounted(() => {
  loadConfig()
  updateStatus()
  loadLogs()

  // 订阅日志更新事件
  EventsOn('logs:updated', onLogsUpdated)

  // 定时更新状态
  const statusInterval = setInterval(updateStatus, 2000)

  onUnmounted(() => {
    clearInterval(statusInterval)
    EventsOff('logs:updated')
  })
})
</script>

<template>
  <div class="app-container">
    <header class="app-header">
      <div class="header-content">
        <h1 class="app-title">NextPaste Server</h1>
        <StatusIndicator :is-running="status.isRunning" />
      </div>
    </header>

    <main class="app-main">
      <div class="left-panel">
        <ServerConfig
          :config="config"
          :is-running="status.isRunning"
          @start="handleStart"
          @stop="handleStop"
          @update:config="saveConfig"
        />

        <ConnectionInfo
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
  background-color: #f5f5f5;
}

.app-header {
  background: white;
  border-bottom: 1px solid #e8e8e8;
  padding: 16px 24px;
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.app-title {
  font-size: 24px;
  font-weight: 600;
  color: #333;
  margin: 0;
}

.app-main {
  flex: 1;
  display: grid;
  grid-template-columns: 400px 1fr;
  gap: 24px;
  padding: 24px;
  overflow: hidden;
}

.left-panel {
  display: flex;
  flex-direction: column;
  gap: 24px;
  overflow-y: auto;
}

.right-panel {
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
</style>
