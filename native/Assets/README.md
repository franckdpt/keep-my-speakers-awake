# Prise jack

Le volet utilise désormais `jack-source.svg`, le SVG fourni le 27 octobre 2026,
conservé intact. `../scripts/import-jack-svg.mjs` importe ses cinq tracés et les
tourne de 45° pour placer la pointe à droite, à l’horizontale, sans étirement.
Il produit `jack-horizontal.svg` et `../Sources/KMSA/JackConnector.swift`.
La couleur d’origine `#262626` est conservée dans le volet.

## Ancienne référence conservée

`jack-reference.png` est la capture fournie par Franck le 27 octobre 2026.
Elle est conservée intacte. La silhouette est vectorisée directement, tournée de
45° pour placer la pointe en haut et le câble en bas, puis remplie en noir pur.
Les proportions de la source sont conservées, sans étirement.

- `jack-upright.svg` : tracé vectoriel vertical, fond transparent.
- `../scripts/vectorize-jack.mjs` : génération reproductible avec ImageMagick
  (masque à 50 %) et Potrace (contours), sans redessiner les détails à la main.

Le build de l’application utilise directement le tracé Swift. Les outils de
vectorisation ne sont nécessaires que pour régénérer le tracé depuis la source.
