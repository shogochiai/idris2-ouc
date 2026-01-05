#!/bin/bash
# Remote Build Script for Idris2 OUC
# Spins up CCX33, builds, retrieves artifacts, terminates server

set -e

# Configuration
SERVER_NAME="idris2-build-$(date +%s)"
SERVER_TYPE="ccx33"  # 8 vCPU, 32GB RAM
IMAGE="ubuntu-22.04"
LOCATION="fsn1"
SSH_KEY_NAME="vastai_idr_1"  # Your SSH key name in Hetzner
SSH_KEY_PATH="$HOME/.ssh/vastai_idr_1"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ARTIFACTS="build"

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
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@"$SERVER_IP" echo "SSH ready" 2>/dev/null; then
        break
    fi
    echo "  Attempt $i/30..."
    sleep 10
done

# Setup script to run on server
SETUP_SCRIPT='
set -e
export PATH="$HOME/.local/bin:$PATH"
export IDRIS2_PREFIX="$HOME/.local"

echo "=== Installing dependencies ==="
apt-get update
apt-get install -y build-essential libgmp-dev git curl chezscheme

echo "=== Installing Idris2 ==="
if [ ! -f "$HOME/.local/bin/idris2" ]; then
    cd /tmp
    git clone https://github.com/idris-lang/Idris2.git
    cd Idris2
    make bootstrap SCHEME=chezscheme
    make install PREFIX="$HOME/.local"
fi

echo "=== Installing idris2-cdk ==="
cd /root
if [ -d idris2-cdk ]; then rm -rf idris2-cdk; fi
git clone https://github.com/shogochiai/idris2-cdk.git
cd idris2-cdk
idris2 --install idris2-cdk.ipkg

echo "=== Building OUC ==="
cd /root/ouc
rm -rf build
idris2 --build ouc.ipkg

echo "=== Build complete ==="
'

# Upload project
echo ""
echo ">>> Uploading project..."
rsync -avz --delete \
    -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    --exclude 'build' \
    --exclude '.git' \
    --exclude 'scripts' \
    "$PROJECT_DIR/" root@"$SERVER_IP":/root/ouc/

# Run build
echo ""
echo ">>> Running build on server..."
ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no root@"$SERVER_IP" "$SETUP_SCRIPT"

# Download artifacts
echo ""
echo ">>> Downloading build artifacts..."
mkdir -p "$PROJECT_DIR/$BUILD_ARTIFACTS"
rsync -avz \
    -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
    root@"$SERVER_IP":/root/ouc/build/ "$PROJECT_DIR/$BUILD_ARTIFACTS/"

# Cleanup
echo ""
echo ">>> Terminating server..."
hcloud server delete "$SERVER_NAME" --yes

echo ""
echo "=== Build complete ==="
echo "Artifacts: $PROJECT_DIR/$BUILD_ARTIFACTS"
