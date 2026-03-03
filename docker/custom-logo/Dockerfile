ARG DIFY_WEB_VERSION=1.11.4
FROM langgenius/dify-web:${DIFY_WEB_VERSION}

# Override default Dify logos with custom ones
COPY logo.svg /app/web/public/logo/logo.svg
COPY logo-monochrome-white.svg /app/web/public/logo/logo-monochrome-white.svg

# Override favicon and PWA icons
COPY favicon.ico /app/web/public/favicon.ico
COPY apple-touch-icon.png /app/web/public/apple-touch-icon.png
COPY icon-72x72.png /app/web/public/icon-72x72.png
COPY icon-96x96.png /app/web/public/icon-96x96.png
COPY icon-128x128.png /app/web/public/icon-128x128.png
COPY icon-144x144.png /app/web/public/icon-144x144.png
COPY icon-152x152.png /app/web/public/icon-152x152.png
COPY icon-192x192.png /app/web/public/icon-192x192.png
COPY icon-256x256.png /app/web/public/icon-256x256.png
COPY icon-384x384.png /app/web/public/icon-384x384.png
COPY icon-512x512.png /app/web/public/icon-512x512.png

# Override manifest.json with custom name
COPY manifest.json /app/web/public/manifest.json
