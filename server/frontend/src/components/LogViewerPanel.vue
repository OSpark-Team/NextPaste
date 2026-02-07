<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import {
  NButton,
  NCard,
  NDataTable,
  NSelect,
  NSpace,
  NTag,
  NText
} from 'naive-ui'
import type { DataTableColumns } from 'naive-ui'
import type { LogEntry } from '../types'

interface Props {
  logs: LogEntry[]
}

interface Emits {
  (e: 'clear'): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

type Level = 'ALL' | 'INFO' | 'SUCCESS' | 'WARNING' | 'ERROR'

const filterLevel = ref<Level>('ALL')

const filteredLogs = computed(() => {
  if (filterLevel.value === 'ALL') return props.logs
  return props.logs.filter((l) => l.level === filterLevel.value)
})

const formatTime = (timestamp: number) => {
  if (!timestamp) {
    const now = new Date()
    return now.toLocaleTimeString('zh-CN', { hour12: false })
  }
  const date = new Date(timestamp)
  return date.toLocaleTimeString('zh-CN', { hour12: false })
}

const levelTagType = (level: string) => {
  switch (level) {
    case 'SUCCESS':
      return 'success'
    case 'WARNING':
      return 'warning'
    case 'ERROR':
      return 'error'
    case 'INFO':
      return 'info'
    default:
      return 'default'
  }
}

const columns: DataTableColumns<LogEntry> = [
  {
    title: '级别',
    key: 'level',
    width: 110,
    render: (row) => {
      return h(
        NTag,
        { size: 'small', type: levelTagType(row.level) as any },
        { default: () => row.level }
      )
    }
  },
  {
    title: '内容',
    key: 'message',
    ellipsis: { tooltip: true }
  },
  {
    title: '时间',
    key: 'timestamp',
    width: 120,
    render: (row) => formatTime(row.timestamp)
  }
]

// avoid unused import for h by defining here
import { h } from 'vue'

watch(
  () => props.logs.length,
  () => {
    // DataTable itself handles scrolling; keep behavior unchanged (no forced scroll)
  }
)

const handleClear = () => emit('clear')
</script>

<template>
  <n-card size="small" title="应用日志">
    <template #header-extra>
      <n-space align="center" :size="8">
        <n-text depth="3">{{ filteredLogs.length }} 条</n-text>
        <n-select
          v-model:value="filterLevel"
          size="small"
          style="width: 120px"
          :options="[
            { label: '全部', value: 'ALL' },
            { label: '信息', value: 'INFO' },
            { label: '成功', value: 'SUCCESS' },
            { label: '警告', value: 'WARNING' },
            { label: '错误', value: 'ERROR' }
          ]"
        />
        <n-button size="small" @click="handleClear">清空</n-button>
      </n-space>
    </template>

    <n-data-table
      size="small"
      :columns="columns"
      :data="filteredLogs"
      :bordered="true"
      :single-line="false"
      :max-height="520"
    />
  </n-card>
</template>
