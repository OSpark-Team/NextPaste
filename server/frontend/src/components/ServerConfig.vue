<template>
  <div class="server-config">
    <h2 class="section-title">服务器配置</h2>
    
    <div class="config-form">
      <div class="form-group">
        <label>监听地址</label>
        <input 
          v-model="localConfig.address" 
          type="text" 
          placeholder="0.0.0.0"
          :disabled="isRunning"
          class="input-field"
        />
      </div>

      <div class="form-group">
        <label>端口号</label>
        <input 
          v-model.number="localConfig.port" 
          type="number" 
          placeholder="8080"
          :disabled="isRunning"
          class="input-field"
        />
      </div>

      <div class="form-actions">
        <button 
          v-if="!isRunning"
          @click="handleStart" 
          class="btn btn-primary"
          :disabled="!isValid"
        >
          启动服务
        </button>
        <button 
          v-else
          @click="handleStop" 
          class="btn btn-danger"
        >
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

.config-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.form-group label {
  font-size: 14px;
  font-weight: 500;
  color: #666;
}

.input-field {
  padding: 10px 12px;
  border: 1px solid #d9d9d9;
  border-radius: 6px;
  font-size: 14px;
  transition: all 0.3s;
}

.input-field:focus {
  outline: none;
  border-color: #1890ff;
  box-shadow: 0 0 0 2px rgba(24, 144, 255, 0.1);
}

.input-field:disabled {
  background-color: #f5f5f5;
  cursor: not-allowed;
}

.form-actions {
  margin-top: 8px;
}

.btn {
  width: 100%;
  padding: 12px;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.3s;
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn-primary {
  background-color: #1890ff;
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: #40a9ff;
}

.btn-danger {
  background-color: #ff4d4f;
  color: white;
}

.btn-danger:hover {
  background-color: #ff7875;
}
</style>

