#!/bin/sh
set -eu

# Generate Secrets.local.xcconfig from Xcode Cloud environment variables.
# Required env vars (set in App Store Connect → Xcode Cloud → Workflow → Environment):
#   SUPABASE_URL       e.g. https://<project-ref>.supabase.co
#   SUPABASE_ANON_KEY  Supabase anon (public) key

if [ -z "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  echo "❌ CI_PRIMARY_REPOSITORY_PATH is not set. This script must run in Xcode Cloud."
  exit 1
fi

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "❌ Missing required env vars."
  echo "   SUPABASE_URL is $([ -n "${SUPABASE_URL:-}" ] && echo 'set' || echo 'EMPTY')"
  echo "   SUPABASE_ANON_KEY is $([ -n "${SUPABASE_ANON_KEY:-}" ] && echo 'set' || echo 'EMPTY')"
  echo "   Add them in App Store Connect → Xcode Cloud → Workflow → Environment."
  exit 1
fi

# xcconfig treats '//' as a line comment, so escape it using the SLASH variable
# defined in Common.xcconfig (SLASH = /). This keeps URLs intact at build time.
ESCAPED_URL=$(printf '%s' "$SUPABASE_URL" | sed 's|//|$(SLASH)$(SLASH)|g')

CONFIG_DIR="$CI_PRIMARY_REPOSITORY_PATH/SplitMate/Config"
CONFIG_FILE="$CONFIG_DIR/Secrets.local.xcconfig"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<EOF
SUPABASE_URL = $ESCAPED_URL
SUPABASE_ANON_KEY = $SUPABASE_ANON_KEY
EOF

KEY_LEN=${#SUPABASE_ANON_KEY}
echo "✅ Wrote $CONFIG_FILE"
echo "   SUPABASE_URL       = $SUPABASE_URL"
echo "   SUPABASE_ANON_KEY  = (set, $KEY_LEN chars)"
