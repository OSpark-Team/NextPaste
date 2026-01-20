<template>
  <div class="log-viewer glass-card">
    <div class="log-header">
      <div class="header-left">
        <div class="section-icon">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
            <polyline points="14 2 14 8 20 8"/>
            <line x1="16" y1="13" x2="8" y2="13"/>
            <line x1="16" y1="17" x2="8" y2="17"/>
            <polyline points="10 9 9 9 8 9"/>
          </svg>
        </div>
        <h2 class="section-title">应用日志</h2>
        <span class="log-count">{{ filteredLogs.length }} 条</span>
      </div>
      <div class="log-actions">
        <div class="filter-wrapper">
          <select v-model="filterLevel" class="filter-select">
            <option value="ALL">全部</option>
            <option value="INFO">信息</option>
            <option value="SUCCESS">成功</option>
            <option value="WARNING">警告</option>
            <option value="ERROR">错误</option>
          </select>
          <svg class="filter-arrow" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="6 9 12 15 18 9"/>
          </svg>
        </div>
        <button @click="handleClear" class="btn-clear">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="3 6 5 6 21 6"/>
            <path d="M19 6v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6m3 0V4a2 2 0 012-2h4a2 2 0 012 2v2"/>
          </svg>
          清空
        </button>
      </div>
    </div>

    <div class="log-content" ref="logContainer">
      <div v-if="filteredLogs.length === 0" class="empty-logs">
        <div class="empty-icon">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
            <polyline points="14 2 14 8 20 8"/>
          </svg>
        </div>
        <p>暂无日志</p>
      </div>
      <TransitionGroup name="log-list" tag="div" class="log-list">
        <div 
          v-for="log in filteredLogs" 
          :key="log.timestamp + log.message"
          class="log-item"
          :class="`log-${log.level.toLowerCase()}`"
        >
          <span class="log-level">
            <span class="level-dot"></span>
            {{ log.level }}
          </span>
          <span class="log-message">{{ log.message }}</span>
          <span class="log-time">{{ formatTime(log.timestamp) }}</span>
        </div>
      </TransitionGroup>
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
  padding: var(--spacing-lg);
  display: flex;
  flex-direction: column;
  height: 100%;
  animation: fadeIn 0.4s ease 0.2s backwards;
}

.log-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: var(--spacing-md);
  flex-shrink: 0;
}

.header-left {
  display: flex;
  align-items: center;
  gap: var(--spacing-md);
}

.section-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  background: linear-gradient(135deg, #f59e0b 0%, #ef4444 100%);
  border-radius: var(--radius-md);
  color: white;
}

.section-title {
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0;
}

.log-count {
  font-size: 12px;
  color: var(--text-muted);
  padding: 4px 10px;
  background: var(--surface-dark);
  border-radius: var(--radius-full);
}

.log-actions {
  display: flex;
  gap: var(--spacing-sm);
}

.filter-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.filter-select {
  appearance: none;
  padding: 8px 32px 8px 12px;
  background: var(--surface-dark);
  border: 1px solid var(--border-glass);
  border-radius: var(--radius-sm);
  font-size: 13px;
  color: var(--text-primary);
  cursor: pointer;
  transition: all var(--transition-fast);
  outline: none;
}

.filter-select:hover {
  border-color: var(--border-light);
}

.filter-select:focus {
  border-color: var(--color-primary);
}

.filter-arrow {
  position: absolute;
  right: 10px;
  pointer-events: none;
  color: var(--text-muted);
}

.btn-clear {
  display: flex;
  align-items: center;
  gap: var(--spacing-xs);
  padding: 8px 14px;
  border: 1px solid var(--border-glass);
  border-radius: var(--radius-sm);
  background: var(--surface-dark);
  font-size: 13px;
  color: var(--text-secondary);
  cursor: pointer;
  transition: all var(--transition-fast);
}

.btn-clear:hover {
  background: rgba(239, 68, 68, 0.15);
  border-color: var(--color-error);
  color: var(--color-error);
}

.log-content {
  flex: 1;
  overflow-y: auto;
  background: var(--surface-dark);
  border-radius: var(--radius-md);
  padding: var(--spacing-sm);
}

.empty-logs {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: var(--text-muted);
  gap: var(--spacing-sm);
}

.empty-icon {
  opacity: 0.3;
}

.log-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

/* 日志列表动画 */
.log-list-enter-active {
  animation: slideIn 0.3s ease;
}

.log-list-leave-active {
  animation: slideIn 0.2s ease reverse;
}

.log-item {
  display: flex;
  align-items: flex-start;
  gap: var(--spacing-md);
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  font-family: 'JetBrains Mono', 'Fira Code', 'Courier New', monospace;
  font-size: 12px;
  transition: background-color var(--transition-fast);
}

.log-item:hover {
  background: rgba(255, 255, 255, 0.03);
}

.log-level {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
  min-width: 80px;
  flex-shrink: 0;
  text-transform: uppercase;
  font-size: 11px;
  letter-spacing: 0.03em;
}

.level-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}

.log-message {
  flex: 1;
  word-break: break-word;
  color: var(--text-secondary);
  line-height: 1.5;
}

.log-time {
  color: var(--text-muted);
  font-size: 11px;
  flex-shrink: 0;
  opacity: 0.7;
}

/* 日志级别颜色 */
.log-info .log-level {
  color: var(--color-primary);
}
.log-info .level-dot {
  background: var(--color-primary);
  box-shadow: 0 0 6px var(--color-primary-glow);
}

.log-success .log-level {
  color: var(--color-success);
}
.log-success .level-dot {
  background: var(--color-success);
  box-shadow: 0 0 6px var(--color-success-glow);
}

.log-warning .log-level {
  color: var(--color-warning);
}
.log-warning .level-dot {
  background: var(--color-warning);
  box-shadow: 0 0 6px var(--color-warning-glow);
}

.log-error .log-level {
  color: var(--color-error);
}
.log-error .level-dot {
  background: var(--color-error);
  box-shadow: 0 0 6px var(--color-error-glow);
}
</style>
