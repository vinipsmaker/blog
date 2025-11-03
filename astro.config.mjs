// @ts-check
import { defineConfig } from 'astro/config';
import { typst } from "astro-typst";
import sitemap from "@astrojs/sitemap";

// https://astro.build/config
export default defineConfig({
  site: 'https://vinipsmaker.github.io/blog',
  base: '/blog/',
  
  integrations: [
    sitemap({
      // Basic sitemap configuration
      changefreq: 'weekly',
      priority: 0.7,
      lastmod: new Date(),
    }),
    typst({
      target: (id) => {
        return "html";
      }
    }),
  ],
  
  // Build configuration
  build: {
    inlineStylesheets: 'auto',
  },
  
  // Vite configuration
  vite: {
    build: {
      cssCodeSplit: true,
      minify: 'esbuild',
      sourcemap: false,
    },
  },
  
  // Output configuration
  output: 'static',
  
  // Markdown configuration
  markdown: {
    shikiConfig: {
      theme: 'github-light',
      wrap: true,
    },
  },
});
