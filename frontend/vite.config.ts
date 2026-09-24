import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // Pas de proxy : en développement le frontend s'adresse directement à
    // FastAPI (port 8000), désigné par frontend/.env.development. En
    // production, les URL sont relatives et le backend sert lui-même la SPA
    // (cf. src/lib/config.ts).
    port: 5173,
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
