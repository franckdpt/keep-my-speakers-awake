import React from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import { App } from "./App.jsx";
import { routeLanguage } from './seo.js';
import "./styles.css";

const root = document.getElementById('root');
const prerendered = root.dataset.prerendered === 'true';
const language = prerendered ? document.documentElement.lang : routeLanguage(location.pathname);
const app = (
  <React.StrictMode>
    <App initialLanguage={language} autoDetect={routeLanguage(location.pathname) !== 'fr'} />
  </React.StrictMode>
);
if (prerendered) hydrateRoot(root, app);
else createRoot(root).render(app);
