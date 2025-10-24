// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  site: 'https://era-agent.yawnxyz.workers.dev',
  output: 'static', // Static site generation (no adapter needed)
  build: {
    // Output to parent dist folder so Worker can serve it
    outDir: '../dist-astro'
  },
  base: '/', // Serve from root
  integrations: [
    starlight({
      title: 'ERA Agent',
      description: 'Ephemeral Runtime Agent Documentation',
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
            { label: 'Quickstart', slug: 'docs/quickstart' },
            { label: 'API Reference', slug: 'docs/api-reference' },
          ],
        },
        {
          label: 'Guides',
          autogenerate: { directory: 'docs/guides' },
        },
      ],
    }),
  ],
});
