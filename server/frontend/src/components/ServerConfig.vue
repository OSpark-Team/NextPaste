<template>
  <div class="server-config glass-card">
    <div class="section-header">
      <div class="section-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <circle cx="12" cy="12" r="3"/>
          <path d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 010 2.83 2 2 0 01-2.83 0l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-2 2 2 2 0 01-2-2v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 01-2.83 0 2 2 0 010-2.83l.06-.06a1.65 1.65 0 00.33-1.82 1.65 1.65 0 00-1.51-1H3a2 2 0 01-2-2 2 2 0 012-2h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 010-2.83 2 2 0 012.83 0l.06.06a1.65 1.65 0 001.82.33H9a1.65 1.65 0 001-1.51V3a2 2 0 012-2 2 2 0 012 2v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 012.83 0 2 2 0 010 2.83l-.06.06a1.65 1.65 0 00-.33 1.82V9a1.65 1.65 0 001.51 1H21a2 2 0 012 2 2 2 0 01-2 2h-.09a1.65 1.65 0 00-1.51 1z"/>
        </svg>
      </div>
      <h2 class="section-title">服务器配置</h2>
    </div>
    
    <div class="config-form">
      <div class="form-group">
        <label class="form-label">监听地址</label>
        <div class="input-wrapper">
          <input 
            v-model="localConfig.address" 
            type="text" 
            placeholder="0.0.0.0"
            :disabled="isRunning"
            class="input-field"
          />
          <div class="input-glow"></div>
        </div>
      </div>

      <div class="form-group">
        <label class="form-label">端口号</label>
        <div class="input-wrapper">
          <input 
            v-model.number="localConfig.port" 
            type="number" 
            placeholder="8080"
            :disabled="isRunning"
            class="input-field"
          />
          <div class="input-glow"></div>
        </div>
      </div>

      <div class="form-actions">
        <button 
          v-if="!isRunning"
          @click="handleStart" 
          class="btn btn-primary"
          :disabled="!isValid"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5 3 19 12 5 21 5 3"/>
          </svg>
          启动服务
        </button>
        <button 
          v-else
          @click="handleStop" 
          class="btn btn-danger"
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
            <rect x="6" y="6" width="12" height="12" rx="1"/>
          </svg>
          停止服务
        </button>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import { ref, computed, watch } from 'vue'
import type { ServerConfig } from '../types'

interface Props {
  config: ServerConfig
  isRunning: boolean
}

interface Emits {
  (e: 'start', config: ServerConfig): void
  (e: 'stop'): void
  (e: 'update:config', config: ServerConfig): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const localConfig = ref<ServerConfig>({ ...props.config })

watch(() => props.config, (newConfig) => {
  localConfig.value = { ...newConfig }
}, { deep: true })

watch(localConfig, (newConfig) => {
  emit('update:config', newConfig)
}, { deep: true })

const isValid = computed(() => {
  return localConfig.value.address.length > 0 && 
         localConfig.value.port > 0 && 
         localConfig.value.port <= 65535
})

const handleStart = () => {
  if (isValid.value) {
    emit('start', localConfig.value)
  }
}

const handleStop = () => {
  emit('stop')
}
</script>

<style scoped>
.server-config {
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
  background: linear-gradient(135deg, var(--color-primary) 0%, #a855f7 100%);
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
  border-color: var(--color-primary);
  box-shadow: 0 0 0 3px var(--color-primary-glow);
}

.input-field:disabled {
  background: rgba(0, 0, 0, 0.3);
  color: var(--text-muted);
  cursor: not-allowed;
}

.input-glow {
  position: absolute;
  inset: -1px;
  border-radius: var(--radius-md);
  background: linear-gradient(135deg, var(--color-primary), #a855f7);
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
  background: linear-gradient(135deg, var(--color-primary) 0%, #8b5cf6 100%);
  color: white;
  box-shadow: 0 4px 16px var(--color-primary-glow);
}

.btn-primary:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 24px var(--color-primary-glow);
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
