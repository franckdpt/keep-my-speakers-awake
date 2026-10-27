import { createServer } from 'vite';
import react from '@vitejs/plugin-react';
import React from 'react';
import { renderToString } from 'react-dom/server';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { renderHead, sitemap } from './seo-head.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const destination = join(root,'dist/client');
const template = await readFile(join(destination,'index.html'),'utf8');
if (!template.includes('<!-- KMSA_SEO -->')) throw new Error('SEO template marker is missing.');
const server = await createServer({
  configFile:false,
  root,
  base:process.env.KMSA_BASE_PATH || '/',
  plugins:[react()],
  optimizeDeps:{noDiscovery:true,include:[]},
  server:{middlewareMode:true,preTransformRequests:false},
  appType:'custom',
});
try {
  const { App } = await server.ssrLoadModule('/src/App.jsx');
  for (const language of ['en','fr']) {
    const markup = renderToString(React.createElement(App,{initialLanguage:language,autoDetect:language==='en'}));
    const html = template.replace('<html lang="en">',`<html lang="${language}">`)
      .replace('<!-- KMSA_SEO -->',renderHead(language))
      .replace('<div id="root"></div>',`<div id="root" data-prerendered="true">${markup}</div>`);
    const directory = language === 'fr' ? join(destination,'fr') : destination;
    await mkdir(directory,{recursive:true});
    await writeFile(join(directory,'index.html'),html);
  }
  await writeFile(join(destination,'sitemap.xml'),sitemap());
  console.log('Pre-rendered English and French content, static metadata and sitemap.');
} finally {
  await server.close();
}
