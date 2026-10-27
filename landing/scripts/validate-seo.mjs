import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { PAGE_URLS, OG_IMAGE, SEO } from '../src/seo.js';
import { DOWNLOAD_URL } from '../src/download.js';

const root = fileURLToPath(new URL('../dist/client/', import.meta.url));
const count = (html, expression) => [...html.matchAll(expression)].length;
for (const language of ['en','fr']) {
  const html = await readFile(join(root,language==='fr'?'fr/index.html':'index.html'),'utf8');
  assert.ok(html.includes(`<html lang="${language}">`));
  assert.equal(count(html,/<title>/g),1);
  assert.equal(count(html,/name="description"/g),1);
  assert.equal(count(html,/rel="canonical"/g),1);
  assert.ok(html.includes(`rel="canonical" href="${PAGE_URLS[language]}"`));
  assert.ok(html.includes(`property="og:url" content="${PAGE_URLS[language]}"`));
  assert.ok(html.includes(`property="og:image" content="${OG_IMAGE}"`));
  assert.ok(html.includes(`property="og:locale" content="${SEO[language].locale}"`));
  assert.ok(html.includes('content="summary_large_image"'));
  assert.ok(html.includes('hreflang="en"') && html.includes('hreflang="fr"') && html.includes('hreflang="x-default"'));
  assert.ok(html.includes(DOWNLOAD_URL));
  assert.ok(html.includes('data-prerendered="true"'));
  assert.equal(count(html,/<h1[ >]/g),1);
  assert.ok(html.includes(language==='fr'?'Gardez vos enceintes éveillées.':'Keep your speakers awake.'));
  assert.ok(html.includes(language==='fr'?'Télécharger pour Mac':'Download for Mac'));
  assert.ok(!html.includes('KMSA_SEO') && !html.includes('noindex') && !html.includes('Voir l’app'));
  const graph = JSON.parse(html.match(/<script type="application\/ld\+json">([^<]+)<\/script>/)[1]);
  assert.equal(graph.url,PAGE_URLS[language]);
  assert.equal(graph.primaryImageOfPage.url,OG_IMAGE);
  assert.ok(SEO[language].description.length>=120 && SEO[language].description.length<=170);
}
const sitemap = await readFile(join(root,'sitemap.xml'),'utf8');
for (const url of Object.values(PAGE_URLS)) assert.ok(sitemap.includes(`<loc>${url}</loc>`));
const jpeg = await readFile(join(root,'social/kmsa-og-v1.jpg'));
assert.equal(jpeg.readUInt16BE(0),0xffd8);
let dimensions;
for (let i=2;i<jpeg.length;) {
  if (jpeg[i]!==0xff) { i++; continue; }
  const marker=jpeg[i+1]; i+=2;
  if ([0xd8,0xd9,0x01].includes(marker)) continue;
  const length=jpeg.readUInt16BE(i);
  if ([0xc0,0xc1,0xc2].includes(marker)) { dimensions=[jpeg.readUInt16BE(i+5),jpeg.readUInt16BE(i+3)]; break; }
  i+=length;
}
assert.deepEqual(dimensions,[1200,630]);
assert.ok(jpeg.length<300_000);
console.log('SEO checks passed: localized static HTML, canonical/hreflang, OG/Twitter, JSON-LD, sitemap, latest download and 1200×630 JPEG.');
