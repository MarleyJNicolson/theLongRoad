import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import scoreboard from './scoreboard.js'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue(), scoreboard()],
})
