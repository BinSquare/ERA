/** @type {import('tailwindcss').Config} */
export default {
  // Only scan index.astro for Tailwind classes to avoid conflicts
  content: ['./src/pages/index.astro'],
  // Use media query strategy to match Starlight's dark mode behavior
  darkMode: 'media',
  theme: {
    extend: {},
  },
  plugins: [],
  // Disable preflight to prevent conflicts with Starlight
  corePlugins: {
    preflight: false,
  },
}

