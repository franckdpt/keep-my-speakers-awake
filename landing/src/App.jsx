import { useEffect, useState } from 'react';
import { DOWNLOAD_URL } from './download.js';

const basePath = import.meta.env.BASE_URL;

const copy = {
  en: {
    title: 'Keep your speakers awake.',
    tagline: 'A tiny app that prevents speaker standby.',
    download: 'Download for Mac',
    speakersAlt: 'A Focal studio monitor and a KRK studio monitor with its yellow speaker cone.',
    language: 'Choose language',
    pageDescription: 'A tiny Mac app that prevents studio monitor standby. Apple Silicon, macOS 14.2 or later.',
  },
  fr: {
    title: 'Gardez vos enceintes éveillées.',
    tagline: 'Une petite app qui évite la veille des enceintes.',
    download: 'Télécharger pour Mac',
    speakersAlt: 'Une enceinte de monitoring Focal et une enceinte KRK avec son haut-parleur jaune.',
    language: 'Choisir la langue',
    pageDescription: 'Une petite app Mac qui évite la veille des enceintes de monitoring. Pour Apple Silicon, macOS 14.2 ou ultérieur.',
  },
};

function initialLanguage() {
  try {
    const saved = localStorage.getItem('kmsa.language');
    if (saved === 'fr' || saved === 'en') return saved;
  } catch { /* Storage may be disabled by browser privacy settings. */ }
  return (navigator.languages?.[0] || navigator.language || 'en').toLowerCase().startsWith('fr') ? 'fr' : 'en';
}

export function App() {
  const [language, setLanguage] = useState(initialLanguage);
  const text = copy[language];

  useEffect(() => {
    document.documentElement.lang = language;
    document.title = `${text.title} — KMSA`;
    document.querySelector('meta[name="description"]')?.setAttribute('content', text.pageDescription);
  }, [language, text]);

  function changeLanguage(next) {
    setLanguage(next);
    try { localStorage.setItem('kmsa.language', next); } catch { /* Keep the selection for this visit. */ }
  }

  return (
    <div className="landing">
      <header className="site-header">
        <a className="wordmark" href={basePath} aria-label="Keep My Speakers Awake">KMSA<span className="status-dot" aria-hidden="true" /></a>
        <nav className="language-switch" aria-label={text.language}>
          <button type="button" lang="en" aria-label="English" aria-pressed={language === 'en'} onClick={() => changeLanguage('en')}>EN</button>
          <span aria-hidden="true">/</span>
          <button type="button" lang="fr" aria-label="Français" aria-pressed={language === 'fr'} onClick={() => changeLanguage('fr')}>FR</button>
        </nav>
      </header>
      <main className="hero">
        <div className="hero-copy">
          <h1>{text.title}</h1>
          <p className="tagline">{text.tagline}</p>
        </div>
        <div className="speakers">
          <img src={`${basePath}assets/speakers.png`} alt={text.speakersAlt} fetchPriority="high" draggable="false" />
        </div>
        <div className="actions">
          <a className="download" href={DOWNLOAD_URL}>{text.download}</a>
          <p className="requirements">Apple Silicon <span aria-hidden="true">·</span> macOS 14.2+</p>
        </div>
      </main>
    </div>
  );
}
