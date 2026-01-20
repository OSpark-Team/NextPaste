<template>
  <div class="connection-info">
    <h2 class="section-title">连接信息</h2>
    
    <div v-if="!isRunning" class="empty-state">
      <p>服务器未运行</p>
    </div>

    <div v-else class="connection-list">
      <div class="info-item">
        <span class="label">连接的客户端</span>
        <span class="value">{{ clientCount }}</span>
      </div>

      <div class="divider"></div>

      <div class="addresses-section">
        <p class="addresses-title">可用连接地址：</p>
        <div v-if="addresses.length === 0" class="loading">
          正在获取网络地址...
        </div>
        <div v-else class="address-list">
          <div 
            v-for="(addr, index) in addresses" 
            :key="index"
            class="address-item"
          >
            <code class="address-text">{{ addr }}</code>
            <button 
              @click="copyAddress(addr)" 
              class="btn-copy"
              :class="{ 'copied': copiedIndex === index }"
            >
              {{ copiedIndex === index ? '已复制' : '复制' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import { ref, watch, onMounted } from 'vue'
import { GetLocalIPs } from '../../wailsjs/go/main/App'

interface Props {
  isRunning: boolean
  clientCount: number
  port: number
}

const props = defineProps<Props>()

const addresses = ref<string[]>([])
const copiedIndex = ref<number>(-1)

const loadAddresses = async () => {
  if (!props.isRunning) {
    addresses.value = []
    return
  }

  try {
    const ips = await GetLocalIPs()
    addresses.value = ips.map(ip => `ws://${ip}:${props.port}/ws`)
  } catch (error) {
    console.error('获取 IP 地址失败:', error)
    addresses.value = []
  }
}

const copyAddress = async (addr: string) => {
  try {
    await navigator.clipboard.writeText(addr)
    const index = addresses.value.indexOf(addr)
    copiedIndex.value = index
    setTimeout(() => {
      copiedIndex.value = -1
    }, 2000)
  } catch (error) {
    console.error('复制失败:', error)
  }
}

watch(() => props.isRunning, () => {
  loadAddresses()
})

watch(() => props.port, () => {
  if (props.isRunning) {
    loadAddresses()
  }
})

onMounted(() => {
  if (props.isRunning) {
    loadAddresses()
  }
})
</script>

<style scoped>
.connection-info {
  background: white;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: #333;
  margin: 0 0 20px 0;
}

.empty-state {
  text-align: center;
  padding: 40px 20px;
  color: #999;
}

.connection-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.info-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.label {
  font-size: 14px;
  color: #666;
}

.value {
  font-size: 18px;
  font-weight: 600;
  color: #1890ff;
}

.divider {
  height: 1px;
  background-color: #f0f0f0;
}

.addresses-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.addresses-title {
  font-size: 14px;
  font-weight: 500;
  color: #666;
  margin: 0;
}

.loading {
  text-align: center;
  padding: 20px;
  color: #999;
  font-size: 14px;
}

.address-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.address-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background-color: #f5f5f5;
  border-radius: 6px;
}

.address-text {
  flex: 1;
  font-family: 'Courier New', monospace;
  font-size: 13px;
  color: #333;
  background-color: transparent;
  padding: 0;
}

.btn-copy {
  padding: 6px 12px;
  border: 1px solid #d9d9d9;
  border-radius: 4px;
  background-color: white;
  font-size: 12px;
  cursor: pointer;
  transition: all 0.3s;
  white-space: nowrap;
}

.btn-copy:hover {
  border-color: #1890ff;
  color: #1890ff;
}

.btn-copy.copied {
  background-color: #52c41a;
  border-color: #52c41a;
  color: white;
}
</style>

