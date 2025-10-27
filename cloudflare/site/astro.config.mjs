// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import tailwind from '@astrojs/tailwind';

// https://astro.build/config
export default defineConfig({
  site: 'https://era-agent.yawnxyz.workers.dev',
  output: 'static', // Static site generation
  base: '/', // Serve from root
  integrations: [
    tailwind(),
    starlight({
      title: 'ERA Agent',
      description: 'ERA Runtime Agent Documentation',
      customCss: [
        './src/styles/custom.scss',
      ],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/anthropics/claude-code',
        },
      ],
      sidebar: [
        {
          label: 'Getting Started',
          items: [
            { label: 'Quickstart - Hosted (Cloudflare)', slug: 'docs/quickstart-hosted' },
            { label: 'Quickstart - Local (Go/CLI)', slug: 'docs/quickstart-local' },
            { label: 'API Reference', slug: 'docs/api-reference' },
          ],
        },
        {
          label: 'Hosted / Cloudflare',
          autogenerate: { directory: 'docs/hosted' },
        },
        {
          label: 'Local / Self-Hosted',
          autogenerate: { directory: 'docs/local' },
        },
        {
          label: 'Guides',
          autogenerate: { directory: 'docs/guides' },
        },
        {
          label: 'Examples',
          autogenerate: { directory: 'docs/examples' },
        },
        {
          label: 'Tools',
          autogenerate: { directory: 'docs/tools' },
        },
      ],
    }),
  ],
});
