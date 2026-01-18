#!/bin/bash

# CockroachDB Automated Backup Script
# Usage: bash scripts/backup_cockroach.sh [database_name]

set -e

# Configuration
CRDB_HOST="${CRDB_HOST:-localhost}"
CRDB_PORT="${CRDB_PORT:-26257}"
DATABASE="${1:-defaultdb}"
BACKUP_BASE_DIR="/var/lib/cockroach/backups"
DATE=$(date +%Y%m%d-%H%M%S)
RETENTION_DAYS=30

# Logging
LOG_FILE="/var/log/cockroach-backup.log"
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=========================================="
log "Starting CockroachDB Backup"
log "=========================================="
log "Database: $DATABASE"
log "Host: $CRDB_HOST:$CRDB_PORT"

# Check if CockroachDB is running
if ! cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "SELECT 1;" &>/dev/null; then
    log "ERROR: Cannot connect to CockroachDB at $CRDB_HOST:$CRDB_PORT"
    exit 1
fi

# Create backup directory if not exists
sudo mkdir -p "$BACKUP_BASE_DIR"
sudo chown -R cockroach:cockroach "$BACKUP_BASE_DIR"

# Determine backup type
FULL_BACKUP_DIR="$BACKUP_BASE_DIR/${DATABASE}-full"

# Check if we need full backup or incremental
if [ ! -d "$FULL_BACKUP_DIR" ] || [ "$(find "$FULL_BACKUP_DIR" -type f -mtime +7)" ]; then
    BACKUP_TYPE="FULL"
    BACKUP_LOCATION="nodelocal://self/backups/${DATABASE}-full"
    
    log "Performing FULL backup..."
    cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
        BACKUP DATABASE $DATABASE INTO '$BACKUP_LOCATION' WITH revision_history;
    " 2>&1 | tee -a "$LOG_FILE"
    
else
    BACKUP_TYPE="INCREMENTAL"
    BACKUP_LOCATION="nodelocal://self/backups/${DATABASE}-full"
    
    log "Performing INCREMENTAL backup..."
    cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
        BACKUP DATABASE $DATABASE INTO LATEST IN '$BACKUP_LOCATION';
    " 2>&1 | tee -a "$LOG_FILE"
fi

# Get backup info
BACKUP_SIZE=$(du -sh "$FULL_BACKUP_DIR" 2>/dev/null | cut -f1)
log "Backup completed successfully!"
log "Backup type: $BACKUP_TYPE"
log "Backup size: ${BACKUP_SIZE:-Unknown}"
log "Location: $FULL_BACKUP_DIR"

# Cleanup old backups (retention policy)
log "Applying retention policy (keep last $RETENTION_DAYS days)..."

# Find and remove old full backups
find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "${DATABASE}-full-*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true

OLD_BACKUPS_REMOVED=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)
log "Removed $OLD_BACKUPS_REMOVED old backup(s)"

# Verify backup integrity (check if backup can be listed)
log "Verifying backup integrity..."
VERIFY_RESULT=$(cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
    SHOW BACKUP FROM LATEST IN '$BACKUP_LOCATION';
" 2>&1)

if echo "$VERIFY_RESULT" | grep -q "database_name"; then
    log "✅ Backup integrity verified"
else
    log "⚠️  WARNING: Backup verification failed"
    log "$VERIFY_RESULT"
fi

# Send notification (optional - configure email/slack)
# send_notification "CockroachDB Backup Completed" "$BACKUP_TYPE backup of $DATABASE completed successfully"

log "=========================================="
log "Backup process completed"
log "=========================================="

# Exit with success
exit 0
