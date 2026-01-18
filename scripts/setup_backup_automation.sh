#!/bin/bash

# Setup Automated Backup via Cron
# This script configures cron jobs for CockroachDB backups

set -e

echo "==========================================="
echo "  CockroachDB Backup Automation Setup"
echo "==========================================="
echo ""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="$SCRIPT_DIR/backup_cockroach.sh"
DATABASE="${1:-defaultdb}"
CRDB_HOST="${CRDB_HOST:-localhost}"

# Make backup script executable
chmod +x "$BACKUP_SCRIPT"

echo "Database to backup: $DATABASE"
echo "CockroachDB Host: $CRDB_HOST"
echo ""

# Create log directory
sudo mkdir -p /var/log/cockroach-backups
sudo chown cockroach:cockroach /var/log/cockroach-backups

# Backup schedule options
echo "Select backup schedule:"
echo "1. Daily at 2 AM (Recommended for production)"
echo "2. Daily at 2 AM + Hourly incrementals"
echo "3. Every 6 hours"
echo "4. Custom schedule"
echo ""
read -p "Enter choice (1-4): " SCHEDULE_CHOICE

case "$SCHEDULE_CHOICE" in
    1)
        CRON_SCHEDULE="0 2 * * *"
        DESCRIPTION="Daily at 2 AM"
        ;;
    2)
        CRON_SCHEDULE_FULL="0 2 * * *"
        CRON_SCHEDULE_INCREMENTAL="0 */1 * * *"
        DESCRIPTION="Daily full + Hourly incremental"
        ;;
    3)
        CRON_SCHEDULE="0 */6 * * *"
        DESCRIPTION="Every 6 hours"
        ;;
    4)
        read -p "Enter cron schedule (e.g., '0 2 * * *'): " CRON_SCHEDULE
        DESCRIPTION="Custom: $CRON_SCHEDULE"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Create cron job
CRON_USER="cockroach"
CRON_JOB="$CRON_SCHEDULE CRDB_HOST=$CRDB_HOST $BACKUP_SCRIPT $DATABASE >> /var/log/cockroach-backups/backup.log 2>&1"

echo ""
echo "Setting up cron job:"
echo "  User: $CRON_USER"
echo "  Schedule: $DESCRIPTION"
echo "  Command: $BACKUP_SCRIPT $DATABASE"
echo ""

# Add to crontab
(sudo crontab -u $CRON_USER -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -u $CRON_USER -

if [ "$SCHEDULE_CHOICE" = "2" ]; then
    # Add incremental backup hourly
    CRON_JOB_INC="$CRON_SCHEDULE_INCREMENTAL CRDB_HOST=$CRDB_HOST $BACKUP_SCRIPT $DATABASE >> /var/log/cockroach-backups/backup.log 2>&1"
    (sudo crontab -u $CRON_USER -l 2>/dev/null; echo "$CRON_JOB_INC") | sudo crontab -u $CRON_USER -
    echo "✅ Incremental backup job added (hourly)"
fi

echo "✅ Backup automation configured successfully!"
echo ""
echo "To verify cron jobs:"
echo "  sudo crontab -u $CRON_USER -l"
echo ""
echo "To view backup logs:"
echo "  tail -f /var/log/cockroach-backups/backup.log"
echo ""
echo "To manually run backup:"
echo "  bash $BACKUP_SCRIPT $DATABASE"
echo ""

# Optional: Run first backup now
read -p "Run first backup now? (y/n): " RUN_NOW

if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Running initial backup..."
    bash "$BACKUP_SCRIPT" "$DATABASE"
fi

echo ""
echo "==========================================="
echo "  Setup Complete!"
echo "==========================================="
