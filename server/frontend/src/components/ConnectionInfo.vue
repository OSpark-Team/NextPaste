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
            <div class="action-buttons">
              <button 
                @click="showQrCode(addr)"
                class="btn-icon"
                title="显示二维码"
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3zM15 15h6v6h-6z"/>
                  <path d="M7 17l10-10"/>
                </svg>
              </button>
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

    <!-- 二维码弹窗 -->
    <div v-if="showQrModal" class="qr-modal" @click.self="closeQrModal">
      <div class="qr-content glass-card">
        <div class="qr-header">
          <h3>扫码连接</h3>
          <button class="close-btn-icon" @click="closeQrModal">×</button>
        </div>
        <div class="qr-body">
          <img :src="qrCodeUrl" alt="QR Code" v-if="qrCodeUrl" class="qr-image"/>
          <div v-else class="qr-loading">生成中...</div>
          <p class="qr-address">{{ currentQrAddress }}</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import { ref, watch, onMounted } from 'vue'
import { GetLocalIPs } from '../../wailsjs/go/main/App'
import QRCode from 'qrcode'

interface Props {
  isRunning: boolean
  clientCount: number
  port: number
}

const props = defineProps<Props>()

const addresses = ref<string[]>([])
const copiedIndex = ref<number>(-1)

// 二维码相关状态
const showQrModal = ref(false)
const qrCodeUrl = ref('')
const currentQrAddress = ref('')

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

const showQrCode = async (addr: string) => {
  currentQrAddress.value = addr
  showQrModal.value = true
  try {
    qrCodeUrl.value = await QRCode.toDataURL(addr, {
      margin: 2,
      width: 200,
      color: {
        dark: '#000000',
        light: '#ffffff'
      }
    })
  } catch (err) {
    console.error('生成二维码失败:', err)
  }
}

const closeQrModal = () => {
  showQrModal.value = false
  qrCodeUrl.value = ''
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

.action-buttons {
  display: flex;
  gap: 8px;
}

.btn-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: 1px solid var(--border-glass);
  border-radius: var(--radius-sm);
  background: var(--surface-glass);
  color: var(--text-secondary);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.btn-icon:hover {
  background: var(--color-primary);
  border-color: var(--color-primary);
  color: white;
}

.btn-copy {
  display: flex;
  align-items: center;
  gap: var(--spacing-xs);
  padding: 4px 10px;
  height: 28px;
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

/* Modal Styles */
.qr-modal {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  animation: fadeIn 0.2s ease;
}

.qr-content {
  background: var(--surface-dark);
  padding: 24px;
  border-radius: var(--radius-lg);
  width: 300px;
  display: flex;
  flex-direction: column;
  align-items: center;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
  transform: translateY(0);
  animation: slideUp 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

.qr-header {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
}

.qr-header h3 {
  margin: 0;
  font-size: 18px;
  color: var(--text-primary);
}

.close-btn-icon {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 24px;
  cursor: pointer;
  padding: 0;
  line-height: 1;
}

.close-btn-icon:hover {
  color: var(--text-primary);
}

.qr-body {
  display: flex;
  flex-direction: column;
  align-items: center;
  width: 100%;
}

.qr-image {
  border-radius: 8px;
  margin-bottom: 16px;
  background: white;
  padding: 8px;
}

.qr-address {
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  color: var(--text-secondary);
  text-align: center;
  word-break: break-all;
  margin: 0;
  padding: 8px;
  background: rgba(0, 0, 0, 0.2);
  border-radius: 6px;
  width: 100%;
}

@keyframes slideUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
