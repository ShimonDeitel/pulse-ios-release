#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# set-deepseek-key.sh — one-shot: put the DeepSeek key on the proxy + deploy.
#
# The key is NEVER stored in this file or printed. wrangler prompts you for it
# and sends it straight to Cloudflare encrypted. Run this in YOUR terminal:
#
#     bash ai-proxy/set-deepseek-key.sh
#
# (You'll need to have run `npx wrangler login` once before.)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Step 1/2 — paste your DeepSeek key at the prompt below (input is hidden):"
npx wrangler secret put DEEPSEEK_API_KEY

echo
echo "▶ Step 2/2 — deploying the worker (ships the key + \$2.50 cap + firewall)…"
npx wrangler deploy

echo
echo "✅ Done. Now:"
echo "   • Fund DeepSeek  → platform.deepseek.com → Top up (even \$2; \$0 = every call fails)"
echo "   • Test on phone  → open Coach, send \"hi\", approve Face ID"
echo "   • Rotate the key → it was pasted in chat earlier; regenerate it once this works"
