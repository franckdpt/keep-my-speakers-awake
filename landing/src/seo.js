export const SITE_URL = 'https://franckdupont.com/kmsa/';
export const OG_IMAGE = `${SITE_URL}social/kmsa-og-v1.jpg`;
export const PAGE_URLS = { en: SITE_URL, fr: `${SITE_URL}fr/` };

export const SEO = {
  en: {
    title: 'Keep My Speakers Awake — Stop Studio Monitor Standby on Mac',
    description: 'Prevent studio monitor standby with a tiny macOS menu bar app. Download Keep My Speakers Awake for Apple Silicon, macOS 14.2 or later.',
    locale: 'en_US',
    imageAlt: 'Keep My Speakers Awake for Mac, with Focal and KRK studio monitors on a clean white background.',
  },
  fr: {
    title: 'Keep My Speakers Awake — Enceintes sans veille sur Mac',
    description: 'Évitez la veille de vos enceintes de monitoring avec une petite app dans la barre de menus du Mac. Pour Apple Silicon, macOS 14.2 ou plus.',
    locale: 'fr_FR',
    imageAlt: 'Keep My Speakers Awake pour Mac, avec deux enceintes de monitoring Focal et KRK sur fond blanc.',
  },
};

export function routeLanguage(pathname) {
  return /\/fr\/?$/.test(pathname) ? 'fr' : 'en';
}
