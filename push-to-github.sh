#!/bin/bash
# Push the authentic-photos folder to a GitHub repo you already created (empty, public).
# Usage: bash push-to-github.sh https://github.com/<you>/authentic-photos.git
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="${1:-}"
[ -n "$URL" ] || { echo "Usage: bash push-to-github.sh <repo-url.git>"; exit 1; }
cd "$DIR"

# Clean build artifacts so they don't get committed (they're also in .gitignore).
rm -rf api/node_modules api/dist 2>/dev/null || true

if [ ! -d .git ]; then git init -q; fi
git add -A
git commit -q -m "Authentic Photos on OpenChoreo (phases 0-3)" || echo "(nothing new to commit)"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "$URL"
git push -u origin main
echo
echo "Pushed to $URL"
echo "Next: bash deploy-phase3.sh ${URL%.git}"
