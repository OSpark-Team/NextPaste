<template>
  <div class="client-config glass-card">
    <div class="section-header">
      <div class="section-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M17 8l4 4m0 0l-4 4m4-4H3"/>
        </svg>
      </div>
      <h2 class="section-title">客户端配置</h2>
    </div>
    
    <div class="config-form">
      <div class="form-group">
        <label class="form-label">服务器地址</label>
        <div class="input-wrapper">
          <input 
            v-model="localUrl" 
            type="text" 
            placeholder="ws://server:8080/ws"
            :disabled="isConnected"
            class="input-field"
          />
          <div class="input-glow"></div>
        </div>
      </div>

      <div class="form-actions">
        <button 
          v-if="!isConnected"
          @click="handleConnect" 
          class="btn btn-primary"
          :disabled="!isValid"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z"/>
          </svg>
          连接服务器
        </button>
        <button 
          v-else
          @click="handleDisconnect" 
          class="btn btn-danger"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="6" width="12" height="12" rx="1"/>
          </svg>
          断开连接
        </button>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import { ref, computed, watch } from 'vue'

interface Props {
  url: string
  isConnected: boolean
}

interface Emits {
  (e: 'connect', url: string): void
  (e: 'disconnect'): void
  (e: 'update:url', url: string): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const localUrl = ref(props.url)

watch(() => props.url, (newUrl) => {
  localUrl.value = newUrl
})

watch(localUrl, (newUrl) => {
  emit('update:url', newUrl)
})

const isValid = computed(() => {
  return localUrl.value.startsWith('ws://') || localUrl.value.startsWith('wss://')
})

const handleConnect = () => {
  if (isValid.value) {
    emit('connect', localUrl.value)
  }
}

const handleDisconnect = () => {
  emit('disconnect')
}
</script>

<style scoped>
.client-config {
  padding: var(--spacing-lg);
  animation: fadeIn 0.4s ease;
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
  background: linear-gradient(135deg, var(--color-client) 0%, var(--color-client-hover) 100%);
  border-radius: var(--radius-md);
  color: white;
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.config-form {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-md);
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.form-label {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.input-wrapper {
  position: relative;
}

.input-field {
  width: 100%;
  padding: 12px 16px;
  background: var(--surface-dark);
  border: 1px solid var(--border-glass);
  border-radius: var(--radius-md);
  font-size: 14px;
  color: var(--text-primary);
  transition: all var(--transition-normal);
  outline: none;
}

.input-field::placeholder {
  color: var(--text-muted);
}

.input-field:focus {
  border-color: var(--color-client);
  box-shadow: 0 0 0 3px var(--color-client-glow);
}

.input-field:disabled {
  background: #f1f5f9;
  color: #475569;
  border-color: #e2e8f0;
  cursor: not-allowed;
}

.input-hint {
  font-size: 12px;
  color: var(--text-muted);
  margin: 0;
}

.input-glow {
  position: absolute;
  inset: -1px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-client), var(--color-client-hover));
  opacity: 0;
  z-index: -1;
  transition: opacity var(--transition-normal);
  filter: blur(8px);
}

.input-field:focus + .input-glow {
  opacity: 0.3;
}

.form-actions {
  margin-top: var(--spacing-sm);
}

.btn {
  width: 100%;
  padding: 14px 20px;
  border: none;
  border-radius: var(--radius-md);
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--spacing-sm);
  transition: all var(--transition-normal);
  position: relative;
  overflow: hidden;
}

.btn::before {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, transparent 0%, rgba(255,255,255,0.1) 100%);
  opacity: 0;
  transition: opacity var(--transition-normal);
}

.btn:hover::before {
  opacity: 1;
}

.btn:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.btn-primary {
  background: linear-gradient(135deg, var(--color-client) 0%, var(--color-client-hover) 100%);
  color: white;
  box-shadow: 0 4px 16px var(--color-client-glow);
}

.btn-primary:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 24px var(--color-client-glow);
}

.btn-primary:active:not(:disabled) {
  transform: translateY(0);
}

.btn-danger {
  background: linear-gradient(135deg, var(--color-error) 0%, #f97316 100%);
  color: white;
  box-shadow: 0 4px 16px var(--color-error-glow);
}

.btn-danger:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 24px var(--color-error-glow);
}

.btn-danger:active {
  transform: translateY(0);
}

</style>
