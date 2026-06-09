import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const env = (globalThis as unknown as { process?: { env?: Record<string, string | undefined> } }).process?.env || {};
const apiTarget = env.SYMPHONY_DEV_API_TARGET || 'http://127.0.0.1:4004';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    host: '0.0.0.0',
    proxy: {
      '/api': { target: apiTarget, changeOrigin: true },
      '/healthz': { target: apiTarget, changeOrigin: true }
    }
  },
  clearScreen: false
});
