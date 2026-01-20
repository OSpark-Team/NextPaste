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
  gap: 8px;
}

.status-dot {
  width: 12px;
  height: 12px;
  border-radius: 50%;
  transition: background-color 0.3s ease;
}

.status-running {
  background-color: #52c41a;
  box-shadow: 0 0 8px rgba(82, 196, 26, 0.5);
}

.status-stopped {
  background-color: #d9d9d9;
}

.status-text {
  font-size: 14px;
  font-weight: 500;
  color: #333;
}
</style>

