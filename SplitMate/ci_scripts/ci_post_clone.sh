#!/bin/sh

# Create Secrets.local.xcconfig from Xcode Cloud environment variables
cat > "$CI_PRIMARY_REPOSITORY_PATH/SplitMate/Config/Secrets.local.xcconfig" << EOF
SUPABASE_URL = $SUPABASE_URL
SUPABASE_ANON_KEY = $SUPABASE_ANON_KEY
EOF

echo "✅ Secrets.local.xcconfig created successfully"
