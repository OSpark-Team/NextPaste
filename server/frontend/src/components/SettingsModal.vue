<script setup lang="ts">
import { computed } from 'vue'
import {
  NModal,
  NForm,
  NFormItem,
  NCheckbox,
  NRadio,
  NRadioGroup,
  NDivider,
  NText,
} from 'naive-ui'

// ... 类型定义保持不变 ...
type AutoStartMode = 'server' | 'client'
type Settings = {
  autoStartEnabled: boolean
  autoStartMode: AutoStartMode
  autoStartActionEnabled: boolean
  closeAction: 'minimize' | 'close'
}

interface Props {
  show: boolean
  settings: Settings
}

interface Emits {
  (e: 'update:show', value: boolean): void
  (e: 'update:settings', value: Settings): void
}

const props = defineProps<Props>()
const emit = defineEmits<Emits>()

const show = computed({
  get: () => props.show,
  set: (v: boolean) => emit('update:show', v)
})

const settings = computed({
  get: () => props.settings,
  set: (v: Settings) => emit('update:settings', v)
})
</script>

<template>
  <n-modal 
    v-model:show="show" 
    preset="card" 
    title="系统设置" 
    style="width: 480px"
    :segmented="{ content: 'soft' }"
    size="medium"
  >
    <n-form
      label-placement="left"
      :label-width="120"
      label-align="left"
      :show-feedback="false"
      size="small"
    >
      <div class="settings-section">
        <n-text depth="3" strong class="section-title">启动行为</n-text>
        
        <!-- TODO: OS 级开机自启未接入，先隐藏该设置项 -->
        <!--
        <n-form-item label="开机启动">
          <n-checkbox v-model:checked="settings.autoStartEnabled">
            随操作系统自动启动
          </n-checkbox>
        </n-form-item>
        -->

        <n-form-item label="启动后自动执行">
          <n-checkbox v-model:checked="settings.autoStartActionEnabled">
            自动创建服务端 / 连接客户端
          </n-checkbox>
        </n-form-item>

        <n-form-item
          v-if="settings.autoStartActionEnabled"
          label="执行模式"
          style="margin-top: -8px"
        >
          <n-radio-group v-model:value="settings.autoStartMode" name="mode">
            <n-radio value="server">服务端</n-radio>
            <n-radio value="client">客户端</n-radio>
          </n-radio-group>
        </n-form-item>
      </div>

      <!-- TODO: OS 级托盘/关闭行为未接入，先隐藏该设置项 -->
      <!--
      <n-divider style="margin: 16px 0" />

      <div class="settings-section">
        <n-text depth="3" strong class="section-title">窗口行为</n-text>

        <n-form-item label="关闭按钮">
          <n-radio-group v-model:value="settings.closeAction" name="action">
            <n-space vertical :size="4">
              <n-radio value="minimize">最小化到系统托盘</n-radio>
              <n-radio value="close">退出应用程序</n-radio>
            </n-space>
          </n-radio-group>
        </n-form-item>
      </div>
      -->
    </n-form>

    <template #footer>
      <div style="display: flex; justify-content: flex-end">
        <n-text depth="3" style="font-size: 12px">
          修改将实时保存并生效
        </n-text>
      </div>
    </template>
  </n-modal>
</template>

<style scoped>
.section-title {
  display: block;
  font-size: 12px;
  margin-bottom: 12px;
  text-transform: uppercase;
  letter-spacing: 1px;
}

.settings-section {
  padding: 4px 8px;
}

:deep(.n-form-item) {
  margin-bottom: 12px;
}

:deep(.n-form-item:last-child) {
  margin-bottom: 0;
}
</style>