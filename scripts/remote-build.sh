#!/bin/bash
# Remote Build Script for Idris2 OUC
# Spins up CCX33, builds, retrieves artifacts, terminates server

set -e

# Load environment
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
fi

# Configuration
SERVER_NAME="idris2-build-$(date +%s)"
SERVER_TYPE="ccx33"  # 8 vCPU, 32GB RAM
IMAGE="ubuntu-22.04"
LOCATION="nbg1"  # Nuremberg (fallback: hel1, ash)
SSH_KEY_NAME="${SSH_KEY_NAME:-vastai_idr_1}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/vastai_idr_1}"
BUILD_ARTIFACTS="build"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "=== Idris2 OUC Remote Build ==="
echo "Server type: $SERVER_TYPE (32GB RAM)"
echo "Project: $PROJECT_DIR"

# Check hcloud CLI
if ! command -v hcloud &> /dev/null; then
    echo "Error: hcloud CLI not installed"
    echo "Install: brew install hcloud"
    exit 1
fi

# Create server
echo ""
echo ">>> Creating server $SERVER_NAME..."
hcloud server create \
    --name "$SERVER_NAME" \
    --type "$SERVER_TYPE" \
    --image "$IMAGE" \
    --location "$LOCATION" \
    --ssh-key "$SSH_KEY_NAME" \
    --start-after-create

# Get server IP
SERVER_IP=$(hcloud server ip "$SERVER_NAME")
echo "Server IP: $SERVER_IP"

# Wait for SSH
echo ""
echo ">>> Waiting for SSH..."
for i in {1..30}; do
    if ssh -i "$SSH_KEY_PATH" $SSH_OPTS -o ConnectTimeout=5 root@"$SERVER_IP" echo "SSH ready" 2>/dev/null; then
        break
    fi
    echo "  Attempt $i/30..."
    sleep 10
done

# Setup script to run on server
SETUP_SCRIPT='
set -e
export PATH="$HOME/.local/bin:$HOME/emsdk:$HOME/emsdk/upstream/emscripten:$PATH"
export IDRIS2_PREFIX="$HOME/.local"

echo "=== Installing dependencies ==="
apt-get update
apt-get install -y build-essential libgmp-dev git curl chezscheme python3 cmake wabt

echo "=== Installing Emscripten (emsdk) ==="
if [ ! -d "$HOME/emsdk" ]; then
    cd $HOME
    git clone https://github.com/emscripten-core/emsdk.git
    cd emsdk
    ./emsdk install latest
    ./emsdk activate latest
fi
source $HOME/emsdk/emsdk_env.sh

echo "=== Installing Idris2 via pack ==="
if ! command -v pack &> /dev/null; then
    cd /tmp
    curl -L https://raw.githubusercontent.com/stefan-hoeck/idris2-pack/main/install.bash | bash
fi
export PATH="$HOME/.pack/bin:$PATH"
echo "pack version: $(pack --version)"
echo "idris2 version: $(idris2 --version)"

echo "=== Installing idris2-cdk and contrib ==="
pack install contrib
pack install idris2-cdk

echo "=== Building OUC (WASM Canister) ==="
cd /root/ouc
rm -rf build
chmod +x scripts/build-canister.sh
./scripts/build-canister.sh

echo "=== Build complete ==="
ls -la build/
'

# Upload project (including scripts and support directories)
echo ""
echo ">>> Uploading project..."
rsync -avz --delete \
    -e "ssh -i $SSH_KEY_PATH $SSH_OPTS" \
    --exclude 'build' \
    --exclude '.git' \
    --exclude '.dfx' \
    --exclude '.lazy' \
    "$PROJECT_DIR/" root@"$SERVER_IP":/root/ouc/

# Run build
echo ""
echo ">>> Running build on server..."
ssh -i "$SSH_KEY_PATH" $SSH_OPTS root@"$SERVER_IP" "$SETUP_SCRIPT"

# Download artifacts
echo ""
echo ">>> Downloading build artifacts..."
mkdir -p "$PROJECT_DIR/$BUILD_ARTIFACTS"
rsync -avz \
    -e "ssh -i $SSH_KEY_PATH $SSH_OPTS" \
    root@"$SERVER_IP":/root/ouc/build/ "$PROJECT_DIR/$BUILD_ARTIFACTS/"

# Cleanup
echo ""
echo ">>> Terminating server..."
echo "y" | hcloud server delete "$SERVER_NAME"

echo ""
echo "=== Build complete ==="
echo "Artifacts: $PROJECT_DIR/$BUILD_ARTIFACTS"
