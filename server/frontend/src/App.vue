<script setup lang="ts">
import { computed, ref, watchEffect } from "vue";
import {
  NConfigProvider,
  NMessageProvider,
  NNotificationProvider,
  NDialogProvider,
  NLoadingBarProvider,
  darkTheme,
  dateZhCN,
  zhCN,
  type GlobalTheme,
} from "naive-ui";
import AppInner from "./AppInner.vue";

type ColorScheme = "light" | "dark" | "auto";

const STORAGE_KEY = "np:colorScheme";

const colorScheme = ref<ColorScheme>("auto");

watchEffect(() => {
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved === "light" || saved === "dark" || saved === "auto") {
    colorScheme.value = saved;
  }
});

watchEffect(() => {
  localStorage.setItem(STORAGE_KEY, colorScheme.value);
});

const prefersDark = () => {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );
};

const naiveTheme = computed<GlobalTheme | null>(() => {
  if (colorScheme.value === "dark") return darkTheme;
  if (colorScheme.value === "light") return null;
  return prefersDark() ? darkTheme : null;
});
</script>

<template>
  <n-config-provider :locale="zhCN" :date-locale="dateZhCN" :theme="naiveTheme">
    <n-message-provider>
      <n-dialog-provider>
        <n-loading-bar-provider>
          <n-notification-provider>
            <AppInner v-model:color-scheme="colorScheme" />
          </n-notification-provider>
        </n-loading-bar-provider>
      </n-dialog-provider>
    </n-message-provider>
  </n-config-provider>
</template>
