#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "         Buzz Compose Production Bootstrapper             "
echo "=========================================================="

if [ ! -f ".env.example" ]; then
  echo "Error: .env.example not found in the current directory."
  echo "Please run this script from buzz/deploy/compose."
  exit 1
fi

# 1. Reset from template
cp .env.example .env

# 2. Prompt for your Buzz Desktop Client Nostr Public Key
if [ -z "${MY_PUBKEY:-}" ]; then
  echo ""
  read -r -p "Enter your Desktop Nostr Public Key (64-char hex): " MY_PUBKEY
  echo ""
fi

# Strip any whitespace
MY_PUBKEY="$(echo "$MY_PUBKEY" | tr -d '[:space:]')"

if [[ ! "$MY_PUBKEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "Error: Public key must be exactly 64 hexadecimal characters (0-9, a-f)."
  echo "If it starts with 'npub1', decode it first or copy the raw hex from Settings."
  exit 1
fi

echo "==> Generating 64-hex Nostr Secret Key for the relay..."
RELAY_SECKEY=""
if docker image inspect ghcr.io/block/buzz:main >/dev/null 2>&1; then
  RELAY_SECKEY=$(docker run --rm --entrypoint /usr/local/bin/buzz-admin ghcr.io/block/buzz:main generate-key 2>/dev/null | grep -i "secret key:" | awk '{print $NF}' || true)
fi

if [ -z "$RELAY_SECKEY" ]; then
  RELAY_SECKEY=$(openssl rand -hex 32)
fi

echo "==> Populating identity keys..."
# Replace RELAY_OWNER_PUBKEY
sed -i '' "s|^RELAY_OWNER_PUBKEY=.*|RELAY_OWNER_PUBKEY=${MY_PUBKEY}|" .env

# Replace BUZZ_RELAY_PRIVATE_KEY
sed -i '' "s|^BUZZ_RELAY_PRIVATE_KEY=.*|BUZZ_RELAY_PRIVATE_KEY=${RELAY_SECKEY}|" .env

echo "==> Populating random secrets for passwords, tokens, and storage..."
# Replace all explicit CHANGE_ME_RANDOM_* placeholders individually
GIT_HMAC=$(openssl rand -hex 32)
PG_PASS=$(openssl rand -hex 16)
REDIS_PASS=$(openssl rand -hex 16)
S3_ACCESS=$(openssl rand -hex 12)
S3_SECRET=$(openssl rand -hex 24)

sed -i '' "s|^BUZZ_GIT_HOOK_HMAC_SECRET=.*|BUZZ_GIT_HOOK_HMAC_SECRET=${GIT_HMAC}|" .env
sed -i '' "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASS}|" .env
sed -i '' "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASS}|" .env
sed -i '' "s|^BUZZ_S3_ACCESS_KEY=.*|BUZZ_S3_ACCESS_KEY=${S3_ACCESS}|" .env
sed -i '' "s|^BUZZ_S3_SECRET_KEY=.*|BUZZ_S3_SECRET_KEY=${S3_SECRET}|" .env

echo "==> Configuring Tailscale domain and Direct WebSocket ingress..."
sed -i '' "s|^BUZZ_DOMAIN=.*|BUZZ_DOMAIN=joels-mac-studio.tail0dcd7.ts.net|" .env
sed -i '' "s|^RELAY_URL=.*|RELAY_URL=ws://joels-mac-studio:3000|" .env
sed -i '' "s|^BUZZ_MEDIA_SERVER_DOMAIN=.*|BUZZ_MEDIA_SERVER_DOMAIN=joels-mac-studio.tail0dcd7.ts.net|" .env
sed -i '' "s|^BUZZ_MEDIA_BASE_URL=.*|BUZZ_MEDIA_BASE_URL=http://joels-mac-studio:3000/media|" .env
sed -i '' "s|^BUZZ_CORS_ORIGINS=.*|BUZZ_CORS_ORIGINS=http://localhost:3000,http://tauri.localhost,tauri://localhost,https://tauri.localhost|" .env

# Ensure DB migrations run automatically on boot
sed -i '' "s|^BUZZ_AUTO_MIGRATE=.*|BUZZ_AUTO_MIGRATE=true|" .env

echo "==> Auditing .env for unresolved active CHANGE_ME keys..."
ACTIVE_LEFTOVERS=$(grep -v '^[[:space:]]*#' .env | grep 'CHANGE_ME' || true)

if [ -n "$ACTIVE_LEFTOVERS" ]; then
  echo "Error: Unresolved active variables found in .env:"
  echo "$ACTIVE_LEFTOVERS"
  exit 1
fi

echo "All active settings resolved successfully."

echo "==> Running internal Buzz configuration check..."
if [ -f "./run.sh" ]; then
  chmod +x ./run.sh
  ./run.sh config
fi

echo ""
echo "=========================================================="
echo " Setup complete!"
echo " Starting Buzz containers via ./run.sh start..."
echo "=========================================================="
./run.sh start

echo ""
echo "Relay is running on port 3000."
echo "In your Buzz Desktop client, join community:"
echo "   ws://joels-mac-studio:3000"
echo "=========================================================="