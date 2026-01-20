<template>
  <div class="status-indicator">
    <div class="status-dot" :class="statusClass"></div>
    <span class="status-text">{{ statusText }}</span>
  </div>
</template>

<script lang="ts" setup>
import { computed } from 'vue'

interface Props {
  isRunning: boolean
}

const props = defineProps<Props>()

const statusClass = computed(() => ({
  'status-running': props.isRunning,
  'status-stopped': !props.isRunning
}))

const statusText = computed(() => 
  props.isRunning ? '运行中' : '已停止'
)
</script>

<style scoped>
.status-indicator {
  display: flex;
  align-items: center;
  gap: var(--spacing-sm);
  padding: 6px 14px;
  background: var(--surface-dark);
  border-radius: var(--radius-full);
  border: 1px solid var(--border-glass);
}

.status-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  transition: all var(--transition-normal);
}

.status-running {
  background-color: var(--color-success);
  box-shadow: 0 0 8px var(--color-success-glow),
              0 0 16px var(--color-success-glow);
  animation: breathe 2s ease-in-out infinite;
}

.status-stopped {
  background-color: var(--text-muted);
  animation: pulse 2s ease-in-out infinite;
}

.status-text {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  letter-spacing: 0.02em;
}

.status-running + .status-text {
  color: var(--color-success);
}
</style>
