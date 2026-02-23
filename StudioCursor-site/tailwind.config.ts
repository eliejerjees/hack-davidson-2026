import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        daw: {
          bg: "#111214",
          panel: "#18191d",
          border: "#2a2c32",
          borderBright: "#3d4048",
          surface: "#1e2026",
          surfaceHover: "#22242b",
          green: "#38bdf8",
          greenDim: "#0ea5e9",
          greenGlow: "#0284c7",
          meter: "#4ade80",
          amber: "#fbbf24",
          red: "#ef4444",
          blue: "#60a5fa",
          blueDim: "#3b82f6",
          text: "#e2e4ea",
          textMuted: "#6b7280",
          textDim: "#9ca3af",
        },
      },
      fontFamily: {
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      animation: {
        "meter-pulse": "meterPulse 2s ease-in-out infinite",
        "meter-slow": "meterPulse 3.5s ease-in-out infinite",
        "glow-pulse": "glowPulse 4s ease-in-out infinite",
      },
      keyframes: {
        meterPulse: {
          "0%, 100%": { transform: "scaleY(0.4)", opacity: "0.5" },
          "50%": { transform: "scaleY(1)", opacity: "1" },
        },
        glowPulse: {
          "0%, 100%": { opacity: "0.3" },
          "50%": { opacity: "0.7" },
        },
      },
      backgroundImage: {
        "grid-daw":
          "linear-gradient(rgba(42,44,50,0.4) 1px, transparent 1px), linear-gradient(90deg, rgba(42,44,50,0.4) 1px, transparent 1px)",
      },
      backgroundSize: {
        "grid-daw": "32px 32px",
      },
    },
  },
  plugins: [],
};

export default config;
