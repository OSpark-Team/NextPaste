<template>
  <div class="connection-info glass-card">
    <div class="section-header">
      <div class="section-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M5 12.55a11 11 0 0114.08 0"/>
          <path d="M1.42 9a16 16 0 0121.16 0"/>
          <path d="M8.53 16.11a6 6 0 016.95 0"/>
          <circle cx="12" cy="20" r="1"/>
        </svg>
      </div>
      <h2 class="section-title">连接信息</h2>
    </div>
    
    <div v-if="!isRunning" class="empty-state">
      <div class="empty-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
          <circle cx="12" cy="12" r="10"/>
          <path d="M12 6v6l4 2"/>
        </svg>
      </div>
      <p class="empty-text">服务器未运行</p>
      <p class="empty-hint">启动服务器后可查看连接信息</p>
    </div>

    <div v-else class="connection-list">
      <div class="stat-card">
        <div class="stat-label">已连接客户端</div>
        <div class="stat-value">{{ clientCount }}</div>
      </div>

      <div class="divider"></div>

      <div class="addresses-section">
        <p class="addresses-title">可用连接地址</p>
        <div v-if="addresses.length === 0" class="loading">
          <div class="loading-spinner"></div>
          <span>正在获取网络地址...</span>
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
              <svg v-if="copiedIndex !== index" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/>
              </svg>
              <svg v-else width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <polyline points="20 6 9 17 4 12"/>
              </svg>
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
  padding: var(--spacing-lg);
  animation: fadeIn 0.4s ease 0.1s backwards;
}

.section-header {
  display: flex;
  align-items: center;
  gap: var(--spacing-md);
  margin-bottom: var(--spacing-lg);
}

.section-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  background: linear-gradient(135deg, #10b981 0%, #06b6d4 100%);
  border-radius: var(--radius-md);
  color: white;
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: var(--spacing-xl) var(--spacing-lg);
  text-align: center;
}

.empty-icon {
  color: var(--text-muted);
  margin-bottom: var(--spacing-md);
  opacity: 0.5;
}

.empty-text {
  font-size: 15px;
  font-weight: 500;
  color: var(--text-secondary);
  margin: 0 0 var(--spacing-xs) 0;
}

.empty-hint {
  font-size: 13px;
  color: var(--text-muted);
  margin: 0;
}

.connection-list {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-md);
}

.stat-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--spacing-md);
  background: var(--surface-dark);
  border-radius: var(--radius-md);
}

.stat-label {
  font-size: 14px;
  color: var(--text-secondary);
}

.stat-value {
  font-size: 28px;
  font-weight: 700;
  background: linear-gradient(135deg, var(--color-primary) 0%, #a855f7 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.divider {
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--border-glass), transparent);
}

.addresses-section {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.addresses-title {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin: 0;
}

.loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--spacing-sm);
  padding: var(--spacing-lg);
  color: var(--text-muted);
  font-size: 14px;
}

.loading-spinner {
  width: 16px;
  height: 16px;
  border: 2px solid var(--border-glass);
  border-top-color: var(--color-primary);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

.address-list {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.address-item {
  display: flex;
  align-items: center;
  gap: var(--spacing-sm);
  padding: var(--spacing-sm) var(--spacing-md);
  background: var(--surface-dark);
  border-radius: var(--radius-md);
  border: 1px solid transparent;
  transition: all var(--transition-normal);
}

.address-item:hover {
  background: var(--surface-glass-hover);
  border-color: var(--border-glass);
}

.address-text {
  flex: 1;
  font-family: 'JetBrains Mono', 'Fira Code', 'Courier New', monospace;
  font-size: 12px;
  color: var(--text-secondary);
  background: transparent;
  padding: 0;
  word-break: break-all;
}

.btn-copy {
  display: flex;
  align-items: center;
  gap: var(--spacing-xs);
  padding: 6px 12px;
  border: 1px solid var(--border-glass);
  border-radius: var(--radius-sm);
  background: var(--surface-glass);
  font-size: 12px;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all var(--transition-fast);
  white-space: nowrap;
}

.btn-copy:hover {
  background: var(--color-primary);
  border-color: var(--color-primary);
  color: white;
}

.btn-copy.copied {
  background: var(--color-success);
  border-color: var(--color-success);
  color: white;
}
</style>
