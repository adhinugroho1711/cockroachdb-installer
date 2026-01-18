#!/bin/bash

# SOP CockroachDB - Certificate Generation Script
# Description: Generate CA and node certificates for secure CockroachDB cluster
# Run this script on ONE node (preferably Node 1) to generate all certificates

set -e

echo "=========================================="
echo "  CockroachDB Certificate Generator"
echo "=========================================="
echo ""

# 1. Check if cockroach binary exists
if ! command -v cockroach &> /dev/null; then
    echo "❌ Error: cockroach binary not found"
    echo "Please install CockroachDB first by running: bash scripts/setup_cockroach.sh"
    exit 1
fi

# 2. Interactive: Get node IPs
echo "Enter the IP addresses for ALL your CockroachDB nodes (separated by comma):"
echo "Example: 192.168.1.1, 192.168.1.2, ..."
read -p "Node IPs: " NODES_INPUT

# Parse input into array
IFS=',' read -ra NODE_IPS <<< "$NODES_INPUT"

# Trim whitespace
for i in "${!NODE_IPS[@]}"; do
    NODE_IPS[$i]=$(echo "${NODE_IPS[$i]}" | xargs)
done

NODE_COUNT=${#NODE_IPS[@]}
echo ""
echo "Detected $NODE_COUNT nodes:"
for i in "${!NODE_IPS[@]}"; do
    echo "  - Node $((i+1)): ${NODE_IPS[$i]}"
done
echo ""

read -p "Is this correct? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# 3. Create directories
CERTS_DIR="$HOME/cockroach-certs"
CA_KEY_DIR="$HOME/cockroach-ca-key"
mkdir -p "$CA_KEY_DIR"
mkdir -p "$CERTS_DIR/client"

for i in "${!NODE_IPS[@]}"; do
    NODE_NUM=$((i+1))
    mkdir -p "$CERTS_DIR/node$NODE_NUM"
done

echo ""
echo "Creating certificates in:"
echo "  - Certificates: $CERTS_DIR"
echo "  - CA Key (KEEP SECURE!): $CA_KEY_DIR"
echo ""

# 4. Generate CA Certificate (once)
echo "Step 1/2: Generating CA Certificate..."
if [ -f "$CA_KEY_DIR/ca.key" ]; then
    echo "  Existing CA key found. Using it."
else
    cockroach cert create-ca \
      --certs-dir="$CERTS_DIR" \
      --ca-key="$CA_KEY_DIR/ca.key"
    echo "  New CA key created."
fi
cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/client/"
echo "✅ CA Certificate ready"
echo ""

# 5. Generate Node Certificates (Loop)
echo "Step 2/2: Generating Certificates for $NODE_COUNT nodes..."

for i in "${!NODE_IPS[@]}"; do
    NODE_NUM=$((i+1))
    NODE_IP="${NODE_IPS[$i]}"
    NODE_DIR="$CERTS_DIR/node$NODE_NUM"
    
    echo "  Processing Node $NODE_NUM ($NODE_IP)..."
    
    cockroach cert create-node \
      "$NODE_IP" \
      localhost \
      127.0.0.1 \
      --certs-dir="$NODE_DIR" \
      --ca-key="$CA_KEY_DIR/ca.key"
      
    # Copy CA to node dir
    cp "$CERTS_DIR/ca.crt" "$NODE_DIR/"
    echo "  ✅ Node $NODE_NUM done."
done
echo ""

# 8. Generate Client Certificate (for root user)
echo "Step 3/3: Generating Client Certificate (root user)..."
cockroach cert create-client \
  root \
  --certs-dir="$CERTS_DIR/client" \
  --ca-key="$CA_KEY_DIR/ca.key"

# Copy CA to client dir
cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/client/"
echo "✅ Client certificates ready: $CERTS_DIR/client/"
echo ""

# 9. Summary
echo "=========================================="
echo "  ✅ Certificate Generation Complete!"
echo "=========================================="
echo ""
echo "Generated Certificates:"
echo ""

for i in "${!NODE_IPS[@]}"; do
    NODE_NUM=$((i+1))
    echo "📁 $CERTS_DIR/node$NODE_NUM/"
    echo "   ├── ca.crt"
    echo "   ├── node.crt"
    echo "   └── node.key"
    echo ""
done

echo "📁 $CERTS_DIR/client/"
echo "   ├── ca.crt"
echo "   ├── client.root.crt"
echo "   └── client.root.key"
echo ""
echo "🔐 CA Private Key (KEEP SECURE!):"
echo "   $CA_KEY_DIR/ca.key"
echo ""
echo "=========================================="
echo "  Next Steps:"
echo "=========================================="
echo ""
echo "1. TRANSFER certificates to each node:"
echo ""
echo "   # Node 1 (current node):"
echo "   sudo mkdir -p /var/lib/cockroach/certs"
echo "   sudo cp $CERTS_DIR/node1/* /var/lib/cockroach/certs/"
echo "   sudo chown -R cockroach:cockroach /var/lib/cockroach/certs"
echo "   sudo chmod 600 /var/lib/cockroach/certs/node.key"
echo ""

echo "   # External Nodes (Loop this for Node 2 - Node $NODE_COUNT):"
echo "   scp $CERTS_DIR/nodeX/* user@<NODE_X_IP>:~/"
echo "   # Then on Node X:"
echo "   sudo mkdir -p /var/lib/cockroach/certs"
echo "   sudo mv ~/ca.crt ~/node.crt ~/node.key /var/lib/cockroach/certs/"
echo "   sudo chown -R cockroach:cockroach /var/lib/cockroach/certs"
echo "   sudo chmod 600 /var/lib/cockroach/certs/node.key"
echo ""

echo "2. UPDATE systemd service to remove --insecure flag on ALL nodes:"
echo "   sudo systemctl stop cockroach"
echo "   sudo sed -i 's/--insecure/--certs-dir=\\/var\\/lib\\/cockroach\\/certs/g' /etc/systemd/system/cockroach.service"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl start cockroach"
echo ""
echo "3. VERIFY secure connection:"
echo "   cockroach sql --certs-dir=/var/lib/cockroach/certs --host=localhost"
echo ""
echo "⚠️  BACKUP CA Key:"
echo "   Store $CA_KEY_DIR/ca.key in a SECURE location!"
echo "   You'll need it to generate new node/client certificates later."
echo ""
