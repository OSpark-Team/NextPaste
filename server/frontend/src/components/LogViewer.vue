<template>
  <div class="log-viewer">
    <div class="log-header">
      <h2 class="section-title">应用日志</h2>
      <div class="log-actions">
        <select v-model="filterLevel" class="filter-select">
          <option value="ALL">全部</option>
          <option value="INFO">信息</option>
          <option value="SUCCESS">成功</option>
          <option value="WARNING">警告</option>
          <option value="ERROR">错误</option>
        </select>
        <button @click="handleClear" class="btn-clear">清空</button>
      </div>
    </div>

    <div class="log-content" ref="logContainer">
      <div v-if="filteredLogs.length === 0" class="empty-logs">
        暂无日志
      </div>
      <div 
        v-for="log in filteredLogs" 
        :key="log.timestamp"
        class="log-item"
        :class="`log-${log.level.toLowerCase()}`"
      >
        <span class="log-level">{{ log.level }}</span>
        <span class="log-message">{{ log.message }}</span>
        <span class="log-time">{{ formatTime(log.timestamp) }}</span>
      </div>
    </div>
  </div>
</template>

<script lang="ts" setup>
import { ref, computed, watch, nextTick } from 'vue'
import type { LogEntry } from '../types'

interface Props {
  logs: LogEntry[]
}

interface Emits {
  (e: 'clear'): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const filterLevel = ref('ALL')
const logContainer = ref<HTMLElement | null>(null)

const filteredLogs = computed(() => {
  if (filterLevel.value === 'ALL') {
    return props.logs
  }
  return props.logs.filter(log => log.level === filterLevel.value)
})

const formatTime = (timestamp: number) => {
  if (!timestamp) {
    const now = new Date()
    return now.toLocaleTimeString('zh-CN', { hour12: false })
  }
  const date = new Date(timestamp)
  return date.toLocaleTimeString('zh-CN', { hour12: false })
}

const handleClear = () => {
  emit('clear')
}

// 自动滚动到底部
watch(() => props.logs.length, async () => {
  await nextTick()
  if (logContainer.value) {
    logContainer.value.scrollTop = logContainer.value.scrollHeight
  }
})
</script>

<style scoped>
.log-viewer {
  background: white;
  border-radius: 12px;
  padding: 24px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
  display: flex;
  flex-direction: column;
  height: 100%;
}

.log-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: #333;
  margin: 0;
}

.log-actions {
  display: flex;
  gap: 8px;
}

.filter-select {
  padding: 6px 12px;
  border: 1px solid #d9d9d9;
  border-radius: 6px;
  font-size: 14px;
  cursor: pointer;
  transition: border-color 0.3s;
}

.filter-select:focus {
  outline: none;
  border-color: #1890ff;
}

.btn-clear {
  padding: 6px 16px;
  border: 1px solid #d9d9d9;
  border-radius: 6px;
  background-color: white;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.3s;
}

.btn-clear:hover {
  border-color: #ff4d4f;
  color: #ff4d4f;
}

.log-content {
  flex: 1;
  overflow-y: auto;
  background-color: #fafafa;
  border-radius: 8px;
  padding: 12px;
  font-family: 'Courier New', monospace;
  font-size: 13px;
  line-height: 1.6;
}

.empty-logs {
  text-align: center;
  padding: 40px 20px;
  color: #999;
}

.log-item {
  display: flex;
  gap: 12px;
  padding: 8px 12px;
  margin-bottom: 4px;
  border-radius: 4px;
  transition: background-color 0.2s;
}

.log-item:hover {
  background-color: rgba(0, 0, 0, 0.02);
}

.log-level {
  font-weight: 600;
  min-width: 70px;
  flex-shrink: 0;
}

.log-message {
  flex: 1;
  word-break: break-word;
}

.log-time {
  color: #999;
  font-size: 12px;
  flex-shrink: 0;
}

.log-info .log-level {
  color: #1890ff;
}

.log-success .log-level {
  color: #52c41a;
}

.log-warning .log-level {
  color: #faad14;
}

.log-error .log-level {
  color: #ff4d4f;
}
</style>

