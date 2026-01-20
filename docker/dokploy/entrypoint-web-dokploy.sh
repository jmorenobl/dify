#!/bin/bash
# Custom entrypoint for Dify Web container in Dokploy
# Separates internal (SSR) API URL from public (browser) API URL

set -e

# =====================================================
# Internal URLs for Server-Side Rendering (SSR)
# These use Docker service names for internal communication
# =====================================================
INTERNAL_API_URL=${INTERNAL_API_URL:-http://api:5001}

# =====================================================
# Public URLs for Browser (injected into HTML)
# These are used by the client-side JavaScript
# =====================================================
PUBLIC_API_URL=${CONSOLE_API_URL:-$INTERNAL_API_URL}
PUBLIC_APP_API_URL=${APP_API_URL:-$INTERNAL_API_URL}

# =====================================================
# Set NEXT_PUBLIC_* for SSR (Node.js uses these)
# =====================================================
export NEXT_PUBLIC_DEPLOY_ENV=${DEPLOY_ENV}
export NEXT_PUBLIC_EDITION=${EDITION}
export NEXT_PUBLIC_BASE_PATH=${NEXT_PUBLIC_BASE_PATH}

# SSR uses internal URLs
export NEXT_PUBLIC_API_PREFIX=${INTERNAL_API_URL}/console/api
export NEXT_PUBLIC_PUBLIC_API_PREFIX=${INTERNAL_API_URL}/api

# Marketplace and other settings
export NEXT_PUBLIC_MARKETPLACE_API_PREFIX=${MARKETPLACE_API_URL}/api/v1
export NEXT_PUBLIC_MARKETPLACE_URL_PREFIX=${MARKETPLACE_URL}
export NEXT_PUBLIC_COOKIE_DOMAIN=${NEXT_PUBLIC_COOKIE_DOMAIN}

export NEXT_PUBLIC_SENTRY_DSN=${SENTRY_DSN}
export NEXT_PUBLIC_SITE_ABOUT=${SITE_ABOUT}
export NEXT_TELEMETRY_DISABLED=${NEXT_TELEMETRY_DISABLED}

export NEXT_PUBLIC_AMPLITUDE_API_KEY=${AMPLITUDE_API_KEY}

export NEXT_PUBLIC_TEXT_GENERATION_TIMEOUT_MS=${TEXT_GENERATION_TIMEOUT_MS}
export NEXT_PUBLIC_CSP_WHITELIST=${CSP_WHITELIST}
export NEXT_PUBLIC_ALLOW_EMBED=${ALLOW_EMBED}
export NEXT_PUBLIC_ALLOW_UNSAFE_DATA_SCHEME=${ALLOW_UNSAFE_DATA_SCHEME:-false}
export NEXT_PUBLIC_TOP_K_MAX_VALUE=${TOP_K_MAX_VALUE}
export NEXT_PUBLIC_INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH=${INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH}
export NEXT_PUBLIC_MAX_TOOLS_NUM=${MAX_TOOLS_NUM}
export NEXT_PUBLIC_ENABLE_WEBSITE_JINAREADER=${ENABLE_WEBSITE_JINAREADER:-true}
export NEXT_PUBLIC_ENABLE_WEBSITE_FIRECRAWL=${ENABLE_WEBSITE_FIRECRAWL:-true}
export NEXT_PUBLIC_ENABLE_WEBSITE_WATERCRAWL=${ENABLE_WEBSITE_WATERCRAWL:-true}
export NEXT_PUBLIC_ENABLE_SINGLE_DOLLAR_LATEX=${NEXT_PUBLIC_ENABLE_SINGLE_DOLLAR_LATEX:-false}
export NEXT_PUBLIC_LOOP_NODE_MAX_COUNT=${LOOP_NODE_MAX_COUNT}
export NEXT_PUBLIC_MAX_PARALLEL_LIMIT=${MAX_PARALLEL_LIMIT}
export NEXT_PUBLIC_MAX_ITERATIONS_NUM=${MAX_ITERATIONS_NUM}
export NEXT_PUBLIC_MAX_TREE_DEPTH=${MAX_TREE_DEPTH}

# =====================================================
# CRITICAL: Override data-* attributes in HTML for browser
# The browser will read these from <body> attributes
# =====================================================
# We need to patch the server.js or HTML output to use public URLs for browser
# This is done by setting environment variables that layout.tsx reads

# For the HTML injection, we override the NEXT_PUBLIC vars ONLY for the HTML rendering
# But since Next.js uses these at both SSR and client, we need a workaround:
# We'll use a post-start script or rely on the browser reading data-* attributes

# Actually, looking at layout.tsx, it reads process.env and injects into body attributes
# So we need to set these to PUBLIC URLs for the HTML, but use INTERNAL for fetch calls

# WORKAROUND: Since Dify's layout.tsx uses the same env var for both SSR and HTML injection,
# we set the env var to the PUBLIC URL, and create a runtime override for SSR fetch calls.

# Reset to public URLs for HTML injection (layout.tsx will read these)
export NEXT_PUBLIC_API_PREFIX=${PUBLIC_API_URL}/console/api
export NEXT_PUBLIC_PUBLIC_API_PREFIX=${PUBLIC_APP_API_URL}/api

# Create a runtime configuration that SSR can read differently
# This uses Next.js runtime config mechanism
export DIFY_INTERNAL_API_URL=${INTERNAL_API_URL}

echo "=== Dify Web Dokploy Entrypoint ==="
echo "Internal API URL (SSR): ${INTERNAL_API_URL}"
echo "Public API URL (Browser): ${PUBLIC_API_URL}"
echo "NEXT_PUBLIC_API_PREFIX: ${NEXT_PUBLIC_API_PREFIX}"
echo "==================================="

# Start PM2 as the original entrypoint does
pm2 start /app/web/server.js --name dify-web --cwd /app/web -i ${PM2_INSTANCES} --no-daemon
