import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import path from "path";

export default defineConfig({
  plugins: [svelte({ hot: false })],
  resolve: {
    alias: [
      { find: "$lib", replacement: path.resolve("app/javascript/src/lib") },
      {
        find: "https://cdn.jsdelivr.net/gh/Linguistic-Data-Consortium/ldcjs@0.0.3/src/getp.js",
        replacement: path.resolve("test/javascript/mocks/getp.ts"),
      },
      // Stub heavy modules so focused component tests don't drag in AWS SDK / bits-ui.
      {
        find: /.*\/lib\/ldcjs\/getp(\.js)?$/,
        replacement: path.resolve("test/javascript/mocks/ldcjs-getp.ts"),
      },
      {
        find: /^\.\/users\.svelte$/,
        replacement: path.resolve("test/javascript/mocks/users-stub.svelte"),
      },
    ],
    conditions: ["browser"],
  },
  test: {
    environment: "jsdom",
    globals: true,
    include: ["app/javascript/**/*.{test,spec}.{js,ts}"],
    setupFiles: ["test/javascript/setup.ts"],
  },
});
