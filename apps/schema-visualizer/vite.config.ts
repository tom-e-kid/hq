import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const __dirname = fileURLToPath(new URL('.', import.meta.url))

// YAML ファイルの検索パス（先にマッチした方を返す）
const yamlSearchPaths = [__dirname, resolve(__dirname, '../../docs')]

export default defineConfig({
  plugins: [
    react(),
    {
      name: 'serve-schema-yaml',
      configureServer(server) {
        server.middlewares.use((req, res, next) => {
          if (!req.url?.endsWith('.yaml')) return next()
          const filename = req.url.split('/').pop()!
          for (const dir of yamlSearchPaths) {
            const filePath = resolve(dir, filename)
            if (existsSync(filePath)) {
              const content = readFileSync(filePath, 'utf-8')
              res.setHeader('Content-Type', 'text/yaml')
              res.end(content)
              return
            }
          }
          next()
        })
      },
    },
  ],
})
