import { useEffect, useState } from 'react';
import { DOWNLOAD_URL, REPOSITORY_URL } from './download.js';
import { SEO } from './seo.js';

const basePath = import.meta.env.BASE_URL;

const copy = {
  en: {
    title: 'Keep your speakers awake.',
    tagline: 'A tiny app that prevents speaker standby.',
    download: 'Download for Mac',
    speakersAlt: 'A Focal studio monitor and a KRK studio monitor with its yellow speaker cone.',
    language: 'Choose language',
    github: 'GitHub — star the project or open an issue',
  },
  fr: {
    title: 'Gardez vos enceintes éveillées.',
    tagline: 'Une petite app qui évite la veille des enceintes.',
    download: 'Télécharger pour Mac',
    speakersAlt: 'Une enceinte de monitoring Focal et une enceinte KRK avec son haut-parleur jaune.',
    language: 'Choisir la langue',
    github: 'GitHub — mettre une étoile ou ouvrir une issue',
  },
};

function initialLanguage() {
  try {
    const saved = localStorage.getItem('kmsa.language');
    if (saved === 'fr' || saved === 'en') return saved;
  } catch { /* Storage may be disabled by browser privacy settings. */ }
  return (navigator.languages?.[0] || navigator.language || 'en').toLowerCase().startsWith('fr') ? 'fr' : 'en';
}

export function App({ initialLanguage: seedLanguage = 'en', autoDetect = true }) {
  const [language, setLanguage] = useState(seedLanguage);
  const text = copy[language];

  useEffect(() => {
    if (autoDetect) setLanguage(initialLanguage());
  }, [autoDetect]);

  useEffect(() => {
    document.documentElement.lang = language;
    document.title = SEO[language].title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', SEO[language].description);
  }, [language, text]);

  function rememberLanguage(next) {
    try { localStorage.setItem('kmsa.language', next); } catch { /* Keep the selection for this visit. */ }
  }

  return (
    <div className="landing">
      <header className="site-header">
        <a className="wordmark" href={basePath} aria-label="Keep My Speakers Awake">KMSA<span className="status-dot" aria-hidden="true" /></a>
        <div className="header-links">
        <a className="github-link" href={REPOSITORY_URL} target="_blank" rel="noopener noreferrer" aria-label={text.github} title={text.github}>GitHub <span aria-hidden="true">↗</span></a>
        <nav className="language-switch" aria-label={text.language}>
          <a href={basePath} lang="en" aria-label="English" aria-current={language === 'en' ? 'page' : undefined} onClick={() => rememberLanguage('en')}>EN</a>
          <span aria-hidden="true">/</span>
          <a href={`${basePath}fr/`} lang="fr" aria-label="Français" aria-current={language === 'fr' ? 'page' : undefined} onClick={() => rememberLanguage('fr')}>FR</a>
        </nav>
        </div>
      </header>
      <main className="hero">
        <div className="hero-copy">
          <h1>{text.title}</h1>
          <p className="tagline">{text.tagline}</p>
        </div>
        <div className="speakers">
          <picture>
            <source srcSet={`${basePath}assets/speakers.webp`} type="image/webp" />
            <img src={`${basePath}assets/speakers.png`} width="1484" height="1060" alt={text.speakersAlt} fetchPriority="high" draggable="false" />
          </picture>
        </div>
        <div className="actions">
          <a className="download" href={DOWNLOAD_URL}>{text.download}</a>
          <p className="requirements">Apple Silicon <span aria-hidden="true">·</span> macOS 14.2+</p>
        </div>
      </main>
    </div>
  );
}
