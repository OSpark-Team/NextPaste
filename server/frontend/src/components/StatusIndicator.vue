<template>
  <div class="status-indicator" :class="{ 'is-running': isRunning }">
    <div class="status-dot" :class="{ 'running': isRunning, 'stopped': !isRunning }"></div>
    <span class="status-text">{{ statusText }}</span>
  </div>
</template>

<script lang="ts" setup>
import { computed } from 'vue'

interface Props {
  isRunning: boolean
}

const props = defineProps<Props>()

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
  transition: all var(--transition-normal);
}

.status-indicator.is-running {
  background: rgba(34, 197, 94, 0.1);
  border-color: rgba(34, 197, 94, 0.3);
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  transition: all var(--transition-normal);
}

.status-dot.running {
  background-color: var(--color-success);
  box-shadow: 0 0 0 3px rgba(34, 197, 94, 0.2);
  animation: breathe 2s ease-in-out infinite;
}

.status-dot.stopped {
  background-color: var(--text-muted);
}

.status-text {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  transition: color var(--transition-normal);
}

.status-indicator.is-running .status-text {
  color: var(--color-success);
}
</style>
