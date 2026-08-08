import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The bundle is written straight into the Go module so `go build` embeds it.
// Nothing is loaded from a CDN at runtime — the console has a strict CSP of
// 'self' and must keep working on a machine with no internet.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../server/internal/web/dist',
    emptyOutDir: true,
    sourcemap: false,
    // One vendor chunk keeps the cold load to two requests without splitting
    // the app into dozens of tiny fingerprinted files.
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom', 'react-router-dom'],
        },
      },
    },
  },
  server: {
    port: 5273,
    // `npm run dev` talks to a locally-run adminsrv; the cookie is same-origin
    // through this proxy, so the login flow works unchanged in dev.
    proxy: {
      '/api': { target: 'http://127.0.0.1:3025', changeOrigin: false },
    },
  },
})
