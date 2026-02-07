<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { NButton, NCard, NForm, NFormItem, NInput } from 'naive-ui'

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

watch(
  () => props.url,
  (newUrl) => {
    localUrl.value = newUrl
  }
)

watch(localUrl, (newUrl) => {
  emit('update:url', newUrl)
})

const isValid = computed(() => {
  return localUrl.value.startsWith('ws://') || localUrl.value.startsWith('wss://')
})

const handleConnect = () => {
  if (!isValid.value) return
  emit('connect', localUrl.value)
}

const handleDisconnect = () => {
  emit('disconnect')
}
</script>

<template>
  <n-card size="small" title="客户端配置">
    <n-form label-placement="top" :disabled="isConnected">
      <n-form-item label="服务器地址">
        <n-input v-model:value="localUrl" placeholder="ws://server:8080/ws" />
      </n-form-item>
    </n-form>

    <n-button
      v-if="!isConnected"
      type="primary"
      block
      :disabled="!isValid"
      @click="handleConnect"
    >
      连接服务器
    </n-button>
    <n-button v-else type="error" block @click="handleDisconnect">断开连接</n-button>
  </n-card>
</template>
