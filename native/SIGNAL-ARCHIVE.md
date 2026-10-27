# Signaux KMSA : actif et essais conservés

Décision du 27 octobre 2026 : ne proposer qu’un signal dans l’application macOS,
**20 Hz ×2 · expérimental** (`sub2`). Franck indique que ce signal fonctionne sur
ses enceintes. Il n’y a plus de menu de sélection ; un ancien choix enregistré
est ignoré. Le test manuel et les lancements automatiques utilisent le même WAV.

## Signal actif

- Source originale conservée : `signals/sub2.wav`.
- Fichier embarqué : `Contents/Resources/Signals/sub2.wav`, copié sans modification.
- Sinusoïde 20 Hz, stéréo identique gauche/droite, 48 kHz, float 32 bits.
- Durée : 6 secondes ; montée et descente progressives de 1,5 seconde.
- Amplitude numérique de crête : 0,5, soit ×2 par rapport au 20 Hz de base
  (environ +6 dB). Le curseur « Volume du signal » reste disponible.
- Le fonctionnement rapporté concerne cette installation ; le niveau du Mac,
  l’entrée et la sensibilité des enceintes influencent le résultat.

## Essais archivés pour les prochaines versions

Ces WAV et leurs définitions restent dans le dépôt. Ils ne sont plus embarqués
ni accessibles dans l’application macOS. L’ancienne extension Chrome conserve
son catalogue distinct.

| Identifiant | Fréquence / variante | Crête numérique | Source conservée |
| --- | --- | --- | --- |
| `original` | 45 Hz original | 0,25 | `tone.wav` |
| `soft` | 45 Hz progressif | 0,25 | `signals/soft.wav` |
| `low` | 30 Hz progressif | 0,25 | `signals/low.wav` |
| `sub` | 20 Hz progressif | 0,25 | `signals/sub.wav` |
| `sub4` | 20 Hz ×4 expérimental | 1,00 | `signals/sub4.wav` |
| `ultrasonic` | 21 kHz expérimental | 0,25 | `signals/ultrasonic.wav` |
| `ultrasonic2` | 21 kHz ×2 expérimental | 0,50 | `signals/ultrasonic2.wav` |
| `ultrasonic4` | 21 kHz ×4 expérimental | 1,00 | `signals/ultrasonic4.wav` |
| `high20` | 20 kHz expérimental | 0,25 | `signals/high20.wav` |
| `high19` | 19 kHz expérimental | 0,25 | `signals/high19.wav` |
| `high18` | 18 kHz expérimental | 0,25 | `signals/high18.wav` |

Tous durent 6 secondes, en stéréo 48 kHz float 32 bits. Les variantes générées
ont une enveloppe progressive de 1,5 seconde au début et à la fin. Le fichier
`tone.wav` original est conservé tel quel.

Les labels, fréquences, amplitudes et anciennes indications figurent dans
`lib/signal-profiles.js`. Le générateur est `scripts/generate-signals.mjs` et
les contrôles de forme d’onde sont dans `test/tone.test.js`.
Ne pas régénérer les WAV pour une simple reconstruction de l’application :
`node native/scripts/build.mjs` copie seulement le fichier actif et vérifie
qu’il reste identique octet pour octet.

Les versions précédentes ont permis de comparer les fréquences et amplitudes.
Le succès du 20 Hz ×2 est rapporté par Franck ; les autres variantes restent
des essais, sans garantie de réveil ou d’inaudibilité. Une éventuelle remise
à disposition devra faire l’objet d’un nouvel essai sur les enceintes réelles.

## Réactiver un essai lors d’une prochaine version

Mettre à jour explicitement le filtre du build natif, la sélection fixe du modèle,
les contrôles `--self-check` et l’interface prévue pour cette version. Les fichiers
originaux permettent de reprendre les essais sans reconstruire les signaux.
