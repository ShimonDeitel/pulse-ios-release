#!/usr/bin/env bash
# Paste your free-tier API keys into Cloudflare as Worker secrets, then deploy.
# Each `wrangler secret put` PROMPTS you — paste the key and press Enter.
set -euo pipefail
cd "$(dirname "$0")"
npx wrangler login                       # first time only: authorize in browser
npx wrangler secret put AISTUDIO_FREE_KEY    # from aistudio.google.com/apikey
npx wrangler secret put CEREBRAS_FREE_KEY    # from cloud.cerebras.ai (API Keys)
npx wrangler secret put OPENROUTER_FREE_KEY  # from openrouter.ai/settings/keys
npm run deploy
echo "Done — free users now run ONLY on these free keys; paid users on the $3/mo metered pot."
