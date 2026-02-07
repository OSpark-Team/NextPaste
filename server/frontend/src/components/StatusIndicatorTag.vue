<script setup lang="ts">
import { computed } from 'vue'
import { NTag } from 'naive-ui'

interface Props {
  isRunning: boolean
}

const props = defineProps<Props>()

const text = computed(() => (props.isRunning ? '运行中' : '已停止'))
const type = computed(() => (props.isRunning ? 'success' : 'default'))
</script>

<template>
  <n-tag :type="type" size="small" round>{{ text }}</n-tag>
</template>
