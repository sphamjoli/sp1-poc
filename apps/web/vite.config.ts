import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/postcss";
import path from "node:path";

export default defineConfig({
  plugins: [vue()],
  css: {
    postcss: { plugins: [tailwindcss()] },
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
    extensions: [".ts", ".tsx", ".vue", ".js", ".jsx", ".mjs", ".json"],
  },
  server: {
    port: 5173,
    fs: {
      allow: [path.resolve(__dirname, "../..")],
    },
  },
  test: {
    globals: true,
    environment: "jsdom",
    include: ["tests/unit/**/*.test.ts"],
  },
});
