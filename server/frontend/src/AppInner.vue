<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watchEffect } from 'vue'
import {
  EventsOff,
  EventsOn,
  WindowMinimise
} from '../wailsjs/runtime/runtime'
import {
  ClearLogs,
  ConnectClient,
  DisconnectClient,
  GetClientStatus,
  GetLogs,
  GetServerStatus,
  Quit,
  StartServer,
  StopServer
} from '../wailsjs/go/main/App'
import type { LogEntry, ServerConfig as ServerConfigType, ServerStatus } from './types'
import { useDialog, useMessage } from 'naive-ui'

import ServerConfigForm from './components/ServerConfigForm.vue'
import ClientConfigForm from './components/ClientConfigForm.vue'
import ConnectionInfoCard from './components/ConnectionInfoCard.vue'
import LogViewerPanel from './components/LogViewerPanel.vue'
import StatusIndicatorTag from './components/StatusIndicatorTag.vue'
import SettingsModal from './components/SettingsModal.vue'

import {
  CopyOutline,
  CloseOutline,
  ColorPaletteOutline,
  SettingsOutline as CogOutline,
  MoonOutline,
  RemoveOutline,
  ScanOutline,
  SunnyOutline
} from '@vicons/ionicons5'

type Mode = 'server' | 'client'

type ColorScheme = 'light' | 'dark' | 'auto'

interface Props {
  colorScheme?: ColorScheme
}

interface Emits {
  (e: 'update:colorScheme', value: ColorScheme): void
}

const props = withDefaults(defineProps<Props>(), {
  colorScheme: 'auto'
})

const emit = defineEmits<Emits>()

const message = useMessage()
const dialog = useDialog()

const mode = ref<Mode>('server')

const config = ref<ServerConfigType>({
  address: '0.0.0.0',
  port: 8080
})

const clientUrl = ref('ws://localhost:8080/ws/my-room')

const status = ref<ServerStatus>({
  isRunning: false,
  clientCount: 0
})

const clientStatus = ref({
  isConnected: false,
  serverUrl: ''
})

const logs = ref<LogEntry[]>([])

const hasActiveConnection = computed(() => {
  return mode.value === 'server' ? status.value.isRunning : clientStatus.value.isConnected
})

const loadConfig = () => {
  const savedMode = localStorage.getItem('mode')
  if (savedMode === 'server' || savedMode === 'client') {
    mode.value = savedMode
  }

  const saved = localStorage.getItem('serverConfig')
  if (saved) {
    try {
      config.value = JSON.parse(saved)
    } catch {
      // ignore
    }
  }

  const savedClientUrl = localStorage.getItem('clientUrl')
  if (savedClientUrl) {
    clientUrl.value = savedClientUrl
  }
}

const saveConfig = () => {
  localStorage.setItem('serverConfig', JSON.stringify(config.value))
}

const saveClientUrl = () => {
  localStorage.setItem('clientUrl', clientUrl.value)
}

const saveMode = () => {
  localStorage.setItem('mode', mode.value)
}

const switchMode = (newMode: Mode) => {
  if (hasActiveConnection.value) {
    message.warning('请先停止当前连接')
    return
  }
  mode.value = newMode
  saveMode()
}

const handleStart = async (cfg: ServerConfigType) => {
  try {
    await StartServer(cfg.address, cfg.port)
    config.value = cfg
    saveConfig()
    await updateStatus()
    message.success('服务已启动')
  } catch (error) {
    dialog.error({
      title: '启动失败',
      content: String(error)
    })
  }
}

const handleStop = async () => {
  try {
    await StopServer()
    await updateStatus()
    message.info('服务已停止')
  } catch (error) {
    dialog.error({
      title: '停止失败',
      content: String(error)
    })
  }
}

const updateStatus = async () => {
  try {
    const newStatus = await GetServerStatus()
    status.value = newStatus as ServerStatus
  } catch {
    // ignore
  }
}

const loadLogs = async () => {
  try {
    const logList = await GetLogs()
    logs.value = logList as LogEntry[]
  } catch {
    // ignore
  }
}

const handleClearLogs = async () => {
  try {
    await ClearLogs()
    logs.value = []
    message.success('已清空日志')
  } catch {
    // ignore
  }
}

const handleConnect = async (url: string) => {
  try {
    await ConnectClient(url)
    clientUrl.value = url
    saveClientUrl()
    await updateClientStatus()
    message.success('已连接')
  } catch (error) {
    dialog.error({
      title: '连接失败',
      content: String(error)
    })
  }
}

const handleDisconnect = async () => {
  try {
    await DisconnectClient()
    await updateClientStatus()
    message.info('已断开')
  } catch (error) {
    dialog.error({
      title: '断开失败',
      content: String(error)
    })
  }
}

const updateClientStatus = async () => {
  try {
    const newStatus = await GetClientStatus()
    clientStatus.value = newStatus as any
  } catch {
    // ignore
  }
}

const onLogsUpdated = (newLogs: LogEntry[]) => {
  logs.value = newLogs
}

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

  EventsOn('logs:updated', onLogsUpdated)

  const statusInterval = window.setInterval(() => {
    updateStatus()
    updateClientStatus()
  }, 2000)

  onUnmounted(() => {
    window.clearInterval(statusInterval)
    EventsOff('logs:updated')
  })
})

const colorScheme = computed<ColorScheme>({
  get: () => props.colorScheme,
  set: (v) => emit('update:colorScheme', v)
})

const settingsOpen = ref(false)

type AutoStartMode = 'server' | 'client'

type Settings = {
  autoStartEnabled: boolean
  autoStartMode: AutoStartMode
  autoStartActionEnabled: boolean
  closeAction: 'minimize' | 'close'
}

const SETTINGS_KEY = 'np:settings'

const settings = ref<Settings>({
  autoStartEnabled: false,
  autoStartMode: 'server',
  autoStartActionEnabled: false,
  closeAction: 'minimize'
})

watchEffect(() => {
  const raw = localStorage.getItem(SETTINGS_KEY)
  if (!raw) return
  try {
    const obj = JSON.parse(raw) as Partial<Settings>
    settings.value = {
      autoStartEnabled: Boolean(obj.autoStartEnabled),
      autoStartMode: obj.autoStartMode === 'client' ? 'client' : 'server',
      autoStartActionEnabled: Boolean(obj.autoStartActionEnabled),
      closeAction: obj.closeAction === 'close' ? 'close' : 'minimize'
    }
  } catch {
    // ignore
  }
})

const didAutoAction = ref(false)

onMounted(async () => {
  if (didAutoAction.value) return
  if (!settings.value.autoStartActionEnabled) return

  didAutoAction.value = true

  try {
    if (settings.value.autoStartMode === 'server') {
      mode.value = 'server'
      await StartServer(config.value.address, config.value.port)
      await updateStatus()
      message.success('已自动启动服务端')
    } else {
      mode.value = 'client'
      await ConnectClient(clientUrl.value)
      await updateClientStatus()
      message.success('已自动连接')
    }
  } catch (error) {
    dialog.error({
      title: '自动执行失败',
      content: String(error)
    })
  }
})

watchEffect(() => {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings.value))
})
</script>

<template>
  <n-layout embedded style="height: 100vh">
    <n-layout-header bordered style="height: 56px">
      <div class="header">
        <div class="header-drag" />
        <div class="header-left">
          <n-space align="center" :size="12">
            <n-text strong>NextPaste Server</n-text>
            <n-tag size="small" type="info" round>NPBP V1.1</n-tag>
          </n-space>
        </div>

        <div class="header-right">
          <n-space align="center" :size="12">
            <StatusIndicatorTag :is-running="hasActiveConnection" />

            <template v-if="mode === 'server' && status.isRunning">
              <n-tag size="small" round type="success">客户端 {{ status.clientCount }}</n-tag>
            </template>

            <n-radio-group v-model:value="colorScheme" size="small" name="theme">
              <n-radio-button value="auto">
                <n-tooltip trigger="hover">
                  <template #trigger>
                    <n-icon><ColorPaletteOutline /></n-icon>
                  </template>
                  跟随系统
                </n-tooltip>
              </n-radio-button>
              <n-radio-button value="light">
                <n-tooltip trigger="hover">
                  <template #trigger>
                    <n-icon><SunnyOutline /></n-icon>
                  </template>
                  浅色
                </n-tooltip>
              </n-radio-button>
              <n-radio-button value="dark">
                <n-tooltip trigger="hover">
                  <template #trigger>
                    <n-icon><MoonOutline /></n-icon>
                  </template>
                  深色
                </n-tooltip>
              </n-radio-button>
            </n-radio-group>

            <n-tooltip trigger="hover">
              <template #trigger>
                <n-button quaternary size="small" @click="settingsOpen = true">
                  <template #icon><n-icon><CogOutline /></n-icon></template>
                </n-button>
              </template>
              设置
            </n-tooltip>

            <n-tooltip trigger="hover">
              <template #trigger>
                <n-button quaternary size="small" @click="handleMinimize">
                  <template #icon><n-icon><RemoveOutline /></n-icon></template>
                </n-button>
              </template>
              最小化
            </n-tooltip>

            <n-tooltip trigger="hover">
              <template #trigger>
                <n-button quaternary size="small" type="error" @click="handleQuit">
                  <template #icon><n-icon><CloseOutline /></n-icon></template>
                </n-button>
              </template>
              退出
            </n-tooltip>
          </n-space>
        </div>
      </div>
    </n-layout-header>

    <n-layout has-sider style="height: calc(100vh - 56px)">
      <n-layout-sider bordered :width="420" content-style="padding: 16px">
        <n-space vertical :size="16">
          <n-card size="small" title="工作模式">
            <n-tabs
              type="segment"
              :value="mode"
              :disabled="hasActiveConnection"
              @update:value="(v: string | number) => switchMode(v as any)"
            >
              <n-tab name="server">服务器</n-tab>
              <n-tab name="client">客户端</n-tab>
            </n-tabs>
          </n-card>

          <ServerConfigForm
            v-if="mode === 'server'"
            :config="config"
            :is-running="status.isRunning"
            @start="handleStart"
            @stop="handleStop"
            @update:config="saveConfig"
          />

          <ClientConfigForm
            v-if="mode === 'client'"
            :url="clientUrl"
            :is-connected="clientStatus.isConnected"
            @connect="handleConnect"
            @disconnect="handleDisconnect"
            @update:url="saveClientUrl"
          />

          <ConnectionInfoCard
            v-if="mode === 'server' || (mode === 'client' && clientStatus.isConnected)"
            :is-running="hasActiveConnection"
            :client-count="status.clientCount"
            :port="config.port"
            :mode="mode"
            :server-url="clientUrl"
          />
        </n-space>
      </n-layout-sider>

      <n-layout-content content-style="padding: 16px">
        <LogViewerPanel :logs="logs" @clear="handleClearLogs" />
      </n-layout-content>
    </n-layout>

    <SettingsModal
      v-model:show="settingsOpen"
      v-model:settings="settings"
    />
  </n-layout>
</template>

<style scoped>
.header {
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 12px;
  position: relative;
}

.header-drag {
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  right: 220px;
  --wails-draggable: drag;
}

.header-left,
.header-right {
  position: relative;
  z-index: 1;
}
</style>
