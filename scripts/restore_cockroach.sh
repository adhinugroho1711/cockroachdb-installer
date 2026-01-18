#!/bin/bash

# CockroachDB Restore Script
# Usage: bash scripts/restore_cockroach.sh [database_name] [backup_location] [options]

set -e

# Configuration
CRDB_HOST="${CRDB_HOST:-localhost}"
CRDB_PORT="${CRDB_PORT:-26257}"
DATABASE="${1}"
BACKUP_LOCATION="${2}"
RESTORE_MODE="${3:-new}"  # new, replace, specific-time

# Logging
LOG_FILE="/var/log/cockroach-restore.log"
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Validate arguments
if [ -z "$DATABASE" ] || [ -z "$BACKUP_LOCATION" ]; then
    echo "Usage: $0 <database_name> <backup_location> [mode]"
    echo ""
    echo "Modes:"
    echo "  new              - Restore to new database (safe, default)"
    echo "  replace          - Replace existing database (DESTRUCTIVE)"
    echo "  point-in-time    - Restore to specific timestamp"
    echo ""
    echo "Examples:"
    echo "  $0 test 'nodelocal://self/backups/test-full' new"
    echo "  $0 test 'nodelocal://self/backups/test-full' replace"
    echo "  $0 test 'nodelocal://self/backups/test-full' point-in-time"
    exit 1
fi

log "=========================================="
log "Starting CockroachDB Restore"
log "=========================================="
log "Database: $DATABASE"
log "Backup Location: $BACKUP_LOCATION"
log "Restore Mode: $RESTORE_MODE"

# Check if CockroachDB is running
if ! cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "SELECT 1;" &>/dev/null; then
    log "ERROR: Cannot connect to CockroachDB at $CRDB_HOST:$CRDB_PORT"
    exit 1
fi

# Verify backup exists
log "Verifying backup exists..."
BACKUP_INFO=$(cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" --format=csv -e "
    SHOW BACKUP FROM LATEST IN '$BACKUP_LOCATION';
" 2>&1)

if echo "$BACKUP_INFO" | grep -q "ERROR"; then
    log "ERROR: Backup not found or invalid at $BACKUP_LOCATION"
    log "$BACKUP_INFO"
    exit 1
fi

log "✅ Backup verified"
echo "$BACKUP_INFO" | head -5 | tee -a "$LOG_FILE"

# Perform restore based on mode
case "$RESTORE_MODE" in
    new)
        NEW_DB_NAME="${DATABASE}_restored_$(date +%Y%m%d_%H%M%S)"
        log "Restoring to NEW database: $NEW_DB_NAME"
        
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            CREATE DATABASE $NEW_DB_NAME;
        " 2>&1 | tee -a "$LOG_FILE"
        
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            RESTORE DATABASE $DATABASE FROM LATEST IN '$BACKUP_LOCATION' 
            WITH into_db = '$NEW_DB_NAME';
        " 2>&1 | tee -a "$LOG_FILE"
        
        log "✅ Database restored to: $NEW_DB_NAME"
        log "⚠️  Remember to update application connection string!"
        ;;
        
    replace)
        log "⚠️  WARNING: This will REPLACE the existing database!"
        read -p "Are you sure? Type 'YES' to confirm: " CONFIRM
        
        if [ "$CONFIRM" != "YES" ]; then
            log "Restore cancelled by user"
            exit 0
        fi
        
        log "Dropping existing database..."
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            DROP DATABASE IF EXISTS $DATABASE CASCADE;
        " 2>&1 | tee -a "$LOG_FILE"
        
        log "Restoring database..."
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            RESTORE DATABASE $DATABASE FROM LATEST IN '$BACKUP_LOCATION';
        " 2>&1 | tee -a "$LOG_FILE"
        
        log "✅ Database replaced successfully"
        ;;
        
    point-in-time)
        read -p "Enter timestamp (YYYY-MM-DD HH:MM:SS): " TIMESTAMP
        
        if [ -z "$TIMESTAMP" ]; then
            log "ERROR: Timestamp required for point-in-time restore"
            exit 1
        fi
        
        NEW_DB_NAME="${DATABASE}_pitr_$(date +%Y%m%d_%H%M%S)"
        log "Restoring to point-in-time: $TIMESTAMP"
        
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            CREATE DATABASE $NEW_DB_NAME;
        " 2>&1 | tee -a "$LOG_FILE"
        
        cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
            RESTORE DATABASE $DATABASE FROM LATEST IN '$BACKUP_LOCATION' 
            AS OF SYSTEM TIME '$TIMESTAMP'
            WITH into_db = '$NEW_DB_NAME';
        " 2>&1 | tee -a "$LOG_FILE"
        
        log "✅ Point-in-time restore completed to: $NEW_DB_NAME"
        ;;
        
    *)
        log "ERROR: Invalid restore mode: $RESTORE_MODE"
        exit 1
        ;;
esac

# Verify restored data
log "Verifying restored database..."

if [ "$RESTORE_MODE" = "replace" ]; then
    VERIFY_DB="$DATABASE"
else
    VERIFY_DB="$NEW_DB_NAME"
fi

TABLE_COUNT=$(cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" --format=csv -e "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_catalog = '$VERIFY_DB';
" | tail -1)

log "Restored database contains $TABLE_COUNT table(s)"

# Sample data verification
cockroach sql --insecure --host="$CRDB_HOST" --port="$CRDB_PORT" -e "
    USE $VERIFY_DB;
    SHOW TABLES;
" 2>&1 | tee -a "$LOG_FILE"

log "=========================================="
log "Restore process completed successfully"
log "=========================================="

exit 0
