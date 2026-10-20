import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import path from "path";

export default defineConfig({
  plugins: [
    RubyPlugin(),
    svelte({ emitCss: false })
  ],
  server: {
    allowedHosts: [ 'vite' ],
  },
  resolve: {
    alias: {
      $lib: path.resolve("app/javascript/src/lib"),
    },
  },
})