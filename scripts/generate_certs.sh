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
echo "Enter the IP addresses for your CockroachDB nodes:"
read -p "Node 1 IP: " NODE1_IP
read -p "Node 2 IP: " NODE2_IP
read -p "Node 3 IP: " NODE3_IP

echo ""
echo "Node Configuration:"
echo "  - Node 1: $NODE1_IP"
echo "  - Node 2: $NODE2_IP"
echo "  - Node 3: $NODE3_IP"
echo ""

read -p "Is this correct? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# 3. Create directories
CERTS_DIR="$HOME/cockroach-certs"
CA_KEY_DIR="$HOME/cockroach-ca-key"

mkdir -p "$CERTS_DIR/node1"
mkdir -p "$CERTS_DIR/node2"
mkdir -p "$CERTS_DIR/node3"
mkdir -p "$CERTS_DIR/client"
mkdir -p "$CA_KEY_DIR"

echo ""
echo "Creating certificates in:"
echo "  - Certificates: $CERTS_DIR"
echo "  - CA Key (KEEP SECURE!): $CA_KEY_DIR"
echo ""

# 4. Generate CA Certificate (once)
echo "Step 1/5: Generating CA Certificate..."
cockroach cert create-ca \
  --certs-dir="$CERTS_DIR" \
  --ca-key="$CA_KEY_DIR/ca.key"

echo "✅ CA Certificate created: $CERTS_DIR/ca.crt"
echo ""

# 5. Generate Node 1 Certificate
echo "Step 2/5: Generating Node 1 Certificate ($NODE1_IP)..."
cockroach cert create-node \
  "$NODE1_IP" \
  localhost \
  127.0.0.1 \
  --certs-dir="$CERTS_DIR/node1" \
  --ca-key="$CA_KEY_DIR/ca.key"

# Copy CA to node1 dir
cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/node1/"
echo "✅ Node 1 certificates ready: $CERTS_DIR/node1/"
echo ""

# 6. Generate Node 2 Certificate
echo "Step 3/5: Generating Node 2 Certificate ($NODE2_IP)..."
cockroach cert create-node \
  "$NODE2_IP" \
  localhost \
  127.0.0.1 \
  --certs-dir="$CERTS_DIR/node2" \
  --ca-key="$CA_KEY_DIR/ca.key"

# Copy CA to node2 dir
cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/node2/"
echo "✅ Node 2 certificates ready: $CERTS_DIR/node2/"
echo ""

# 7. Generate Node 3 Certificate
echo "Step 4/5: Generating Node 3 Certificate ($NODE3_IP)..."
cockroach cert create-node \
  "$NODE3_IP" \
  localhost \
  127.0.0.1 \
  --certs-dir="$CERTS_DIR/node3" \
  --ca-key="$CA_KEY_DIR/ca.key"

# Copy CA to node3 dir
cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/node3/"
echo "✅ Node 3 certificates ready: $CERTS_DIR/node3/"
echo ""

# 8. Generate Client Certificate (for root user)
echo "Step 5/5: Generating Client Certificate (root user)..."
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
echo "📁 $CERTS_DIR/node1/"
echo "   ├── ca.crt"
echo "   ├── node.crt"
echo "   └── node.key"
echo ""
echo "📁 $CERTS_DIR/node2/"
echo "   ├── ca.crt"
echo "   ├── node.crt"
echo "   └── node.key"
echo ""
echo "📁 $CERTS_DIR/node3/"
echo "   ├── ca.crt"
echo "   ├── node.crt"
echo "   └── node.key"
echo ""
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
echo "   # Node 2 ($NODE2_IP):"
echo "   scp $CERTS_DIR/node2/* user@$NODE2_IP:~/"
echo "   # Then on Node 2:"
echo "   sudo mkdir -p /var/lib/cockroach/certs"
echo "   sudo mv ~/ca.crt ~/node.crt ~/node.key /var/lib/cockroach/certs/"
echo "   sudo chown -R cockroach:cockroach /var/lib/cockroach/certs"
echo "   sudo chmod 600 /var/lib/cockroach/certs/node.key"
echo ""
echo "   # Node 3 ($NODE3_IP):"
echo "   scp $CERTS_DIR/node3/* user@$NODE3_IP:~/"
echo "   # Then on Node 3:"
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
