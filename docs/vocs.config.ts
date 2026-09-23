import { defineConfig } from 'vocs/config'
import { sidebar } from './vocs.sidebar.ts'

export default defineConfig({
  title: "Credible Standard Library",
  renderStrategy: 'full-static',
  basePath: '/credible-std',
  codeHighlight: {
    fallbackLanguage: 'plaintext',
    langs: [
      'ansi', 'bash', 'diff', 'html', 'js', 'json', 'jsx',
      'markdown', 'md', 'mdx', 'plaintext', 'rust', 'sol', 'solidity',
      'toml', 'ts', 'tsx', 'yaml', 'zsh',
    ],
  },
  sidebar,
})
