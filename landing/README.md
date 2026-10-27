# KMSA landing

The live page is https://franckdupont.com/kmsa/; https://franckdpt.com/kmsa redirects
there. The download button uses the latest stable GitHub Release of this repository.

```sh
npm ci
npm run dev -- --host 127.0.0.1 --port 4174
npm run build:kmsa
```

French / English follows the browser language, with a saved manual switch.
One download action, no app preview. Apple-inspired spacing and system typography,
17 px mobile supporting text, 14 px requirements, secondary contrast 5.07:1.

The speakers are a generated transparent composition based on user-supplied
Focal and KRK references. Inter is locally bundled with its license. The existing
Forge hosting is separate from app releases; new app versions need no site rebuild.
