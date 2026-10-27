import { SITE_URL, OG_IMAGE, PAGE_URLS, SEO } from '../src/seo.js';

const escape = value => String(value).replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;');

export function renderHead(language) {
  const text = SEO[language];
  const url = PAGE_URLS[language];
  const alternate = language === 'en' ? 'fr_FR' : 'en_US';
  const graph = {
    '@context':'https://schema.org',
    '@type':'WebPage',
    '@id':`${url}#webpage`,
    url,
    name:text.title,
    description:text.description,
    inLanguage:language,
    about:{'@id':'https://github.com/franckdpt/keep-my-speakers-awake'},
    isPartOf:{'@type':'WebSite','@id':'https://franckdupont.com/#website',url:'https://franckdupont.com/',name:'Franck Dupont'},
    primaryImageOfPage:{'@type':'ImageObject',url:OG_IMAGE,width:1200,height:630,caption:text.imageAlt},
  };
  return [
    `<title>${escape(text.title)}</title>`,
    `<meta name="description" content="${escape(text.description)}" />`,
    '<meta name="robots" content="index,follow,max-image-preview:large" />',
    `<link rel="canonical" href="${url}" />`,
    `<link rel="alternate" hreflang="en" href="${PAGE_URLS.en}" />`,
    `<link rel="alternate" hreflang="fr" href="${PAGE_URLS.fr}" />`,
    `<link rel="alternate" hreflang="x-default" href="${SITE_URL}" />`,
    '<meta property="og:type" content="website" />',
    '<meta property="og:site_name" content="Keep My Speakers Awake" />',
    `<meta property="og:title" content="${escape(text.title)}" />`,
    `<meta property="og:description" content="${escape(text.description)}" />`,
    `<meta property="og:url" content="${url}" />`,
    `<meta property="og:locale" content="${text.locale}" />`,
    `<meta property="og:locale:alternate" content="${alternate}" />`,
    `<meta property="og:image" content="${OG_IMAGE}" />`,
    `<meta property="og:image:secure_url" content="${OG_IMAGE}" />`,
    '<meta property="og:image:type" content="image/jpeg" />',
    '<meta property="og:image:width" content="1200" />',
    '<meta property="og:image:height" content="630" />',
    `<meta property="og:image:alt" content="${escape(text.imageAlt)}" />`,
    '<meta name="twitter:card" content="summary_large_image" />',
    `<meta name="twitter:title" content="${escape(text.title)}" />`,
    `<meta name="twitter:description" content="${escape(text.description)}" />`,
    `<meta name="twitter:image" content="${OG_IMAGE}" />`,
    `<meta name="twitter:image:alt" content="${escape(text.imageAlt)}" />`,
    `<script type="application/ld+json">${JSON.stringify(graph).replaceAll('<','\\u003c')}</script>`,
  ].join('\n    ');
}

export function sitemap() {
  const alternates = `<xhtml:link rel="alternate" hreflang="en" href="${PAGE_URLS.en}"/><xhtml:link rel="alternate" hreflang="fr" href="${PAGE_URLS.fr}"/><xhtml:link rel="alternate" hreflang="x-default" href="${SITE_URL}"/>`;
  return `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${Object.values(PAGE_URLS).map(url=>`<url><loc>${url}</loc>${alternates}</url>`).join('')}</urlset>\n`;
}
