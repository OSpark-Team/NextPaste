<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import {
  NButton,
  NCard,
  NCode,
  NEmpty,
  NList,
  NListItem,
  NModal,
  NScrollbar,
  NSpace,
  NText,
  NTooltip,
  useMessage
} from 'naive-ui'
import { GetLocalIPs } from '../../wailsjs/go/main/App'
import QRCode from 'qrcode'
import { CopyOutline, ScanOutline } from '@vicons/ionicons5'

interface Props {
  isRunning: boolean
  port?: number
  mode?: 'server' | 'client'
  serverUrl?: string
}

const props = withDefaults(defineProps<Props>(), {
  mode: 'server',
  serverUrl: '',
  port: 8080
})

const message = useMessage()

const addresses = ref<string[]>([])

const showQrModal = ref(false)
const qrCodeUrl = ref('')
const currentQrAddress = ref('')

const title = computed(() => (props.mode === 'client' ? '服务器地址' : '连接信息'))

const loadAddresses = async () => {
  if (props.mode === 'client') {
    addresses.value = props.serverUrl ? [props.serverUrl] : []
    return
  }

  if (!props.isRunning) {
    addresses.value = []
    return
  }

  try {
    const ips = await GetLocalIPs()
    addresses.value = ips.map((ip: string) => `ws://${ip}:${props.port}/ws`)
  } catch {
    addresses.value = []
  }
}

const copyAddress = async (addr: string) => {
  try {
    await navigator.clipboard.writeText(addr)
    message.success('已复制')
  } catch {
    message.error('复制失败')
  }
}

const showQrCode = async (addr: string) => {
  currentQrAddress.value = addr
  showQrModal.value = true
  qrCodeUrl.value = ''
  try {
    qrCodeUrl.value = await QRCode.toDataURL(addr, {
      margin: 2,
      width: 220,
      color: {
        dark: '#000000',
        light: '#ffffff'
      }
    })
  } catch {
    qrCodeUrl.value = ''
  }
}

watch(
  () => [props.isRunning, props.port, props.serverUrl, props.mode],
  () => {
    loadAddresses()
  }
)

onMounted(() => {
  if (props.isRunning || (props.mode === 'client' && props.serverUrl)) {
    loadAddresses()
  }
})
</script>

<template>
  <n-card size="small" :title="title">
    <template v-if="!isRunning && mode === 'server'">
      <n-empty description="服务器未运行" />
    </template>

    <template v-else-if="!isRunning && mode === 'client'">
      <n-empty description="未连接服务器" />
    </template>

    <template v-else>
      <n-space vertical :size="12">
        <div>
          <n-text depth="3">{{ mode === 'client' ? '服务器地址' : '可用连接地址' }}</n-text>
        </div>

        <n-scrollbar style="max-height: 220px">
          <n-list v-if="addresses.length" bordered>
            <n-list-item v-for="addr in addresses" :key="addr">
              <n-space align="center" justify="space-between" style="width: 100%">
                <n-code :code="addr" language="text" />
                <n-space :size="6">
                  <n-tooltip trigger="hover">
                    <template #trigger>
                      <n-button size="tiny" quaternary @click="showQrCode(addr)">
                        <template #icon>
                          <n-icon><ScanOutline /></n-icon>
                        </template>
                      </n-button>
                    </template>
                    二维码
                  </n-tooltip>

                  <n-tooltip trigger="hover">
                    <template #trigger>
                      <n-button size="tiny" quaternary type="primary" @click="copyAddress(addr)">
                        <template #icon>
                          <n-icon><CopyOutline /></n-icon>
                        </template>
                      </n-button>
                    </template>
                    复制
                  </n-tooltip>
                </n-space>
              </n-space>
            </n-list-item>
          </n-list>

          <n-empty v-else description="正在获取网络地址..." />
        </n-scrollbar>
      </n-space>
    </template>

    <n-modal v-model:show="showQrModal" preset="card" title="扫码连接" style="width: 360px">
      <n-space vertical align="center" :size="12">
        <img v-if="qrCodeUrl" :src="qrCodeUrl" alt="QR Code" style="width: 220px; height: 220px" />
        <n-empty v-else description="生成中..." />
      </n-space>
    </n-modal>
  </n-card>
</template>
