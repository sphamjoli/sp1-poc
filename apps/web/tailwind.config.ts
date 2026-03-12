import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: {
        tide: {
          50: "#effcfb",
          100: "#cff7f3",
          200: "#9beee7",
          300: "#5bd8d2",
          400: "#28b8b4",
          500: "#0c9c9a",
          600: "#0d7d7d",
          700: "#105f61",
          800: "#134d50",
          900: "#153f42"
        },
        ember: {
          500: "#f97316",
          600: "#ea580c"
        }
      },
      boxShadow: {
        tide: "0 12px 32px rgba(12, 156, 154, 0.25)",
      },
      fontFamily: {
        display: ["Sora", "sans-serif"],
        mono: ["Space Mono", "monospace"],
      },
    },
  },
  plugins: [],
} satisfies Config;
