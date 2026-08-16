import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "dist",
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, "index.html"),
        pet: path.resolve(__dirname, "pet.html"),
        panel: path.resolve(__dirname, "panel.html"),
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true,
  },
});
