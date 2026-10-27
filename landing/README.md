# KMSA landing

The live page is https://franckdupont.com/kmsa/; https://franckdpt.com/kmsa redirects
there. The download button uses the latest stable GitHub Release of this repository.

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4174
npm run build:kmsa
```

French / English follows the browser language, with a saved manual switch.
The French version also has a crawlable URL at `/kmsa/fr/`; the language switch
uses real links. Both versions are pre-rendered at build time, including content,
localized titles/descriptions, canonical/hreflang links, Open Graph, Twitter and
WebPage JSON-LD. `/kmsa/sitemap.xml` lists the two versions.
One download action, no app preview. Apple-inspired spacing and system typography,
17 px mobile supporting text, 14 px requirements, secondary contrast 5.07:1.

The speakers are a generated transparent composition based on user-supplied
Focal and KRK references. Inter is locally bundled with its license. The existing
Forge hosting is separate from app releases; new app versions need no site rebuild.

The OG card is `public/social/kmsa-og-v1.jpg` (1200 × 630). Art direction and
generation prompt: `design/og-prompt.md`. It is metadata-only, never loaded in the
visible hero. The hero uses WebP with a PNG fallback. `npm run build:kmsa` validates
SEO output and image dimensions automatically.
