import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default {
  preprocess: vitePreprocess(),
  // Don't force `runes: true` globally — Svelte 5 auto-detects runes per
  // file, and forcing it breaks legacy library components (svelte-sonner,
  // mode-watcher, etc) that still use `export let` / `$$props`.
};
