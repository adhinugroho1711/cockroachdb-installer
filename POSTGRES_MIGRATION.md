# 🐘 PostgreSQL to CockroachDB Migration Guide

Migrating from PostgreSQL to CockroachDB is straightforward because CockroachDB is wire-compatible with PostgreSQL. However, due to its distributed nature, some architectural adjustments are recommended.

---

## 📥 Step 1: Installation

MOLT is a standalone binary. You should install it on a machine that has network access to both the source PostgreSQL and the target CockroachDB.

```bash
# Download and install MOLT (Linux x86_64)
curl https://binaries.cockroachdb.com/molt/molt.latest.linux-amd64.tar.gz | tar -xz

# Move to your path
sudo mv molt /usr/local/bin/

# Verify
molt version
```

---

## 🛠️ Step 2: Assessment (Schema Analysis)

---

## 📐 Step 2: Schema Migration

### 1. Dump Schema from PostgreSQL
Do not dump data yet, only the structure.

```bash
pg_dump -h <pg_host> -U <user> -s <dbname> > schema.sql
```

### 2. Manual Adjustments (If needed)
Review `schema.sql` for:
- **Extensions**: CockroachDB supports many (PostGIS, etc.) but you might need to enable them manually.
- **Triggers**: CockroachDB supports triggers but limited compared to Postgres.
- **Stored Procedures**: Convert PL/pgSQL to supported SQL or application logic.
- **Serial**: Replace `SERIAL` with `BIGINT DEFAULT unique_row_id()` or `UUID DEFAULT gen_random_uuid()` for better distribution.

### 3. Load Schema to CockroachDB
```bash
cockroach sql --host=<crdb_host> --insecure -d <dbname> < schema.sql
```

---

## 💾 Step 3: Data Migration

There are three ways to move your data:

### Option A: MOLT Fetch (Online/One-time)
Best for small to medium databases. It handles the copy automatically.

```bash
./molt fetch \
  --source "postgres://user:pass@pg-host:5432/dbname" \
  --target "postgres://user:pass@crdb-host:26257/dbname?sslmode=disable"
```

### Option B: IMPORT (Offline - Fastest)
Best for large datasets (GBs to TBs). Requires the database to be in a "clean" state.

1. **Export to CSV/SQL** from Postgres.
2. **Import** into CockroachDB:
```sql
IMPORT TABLE users CSV DATA ('http://backup-server/users.csv');
```

### Option C: MOLT Live (Zero Downtime)
Uses Change Data Capture (CDC) to keep CockroachDB in sync with PostgreSQL until you are ready to cut over.

---

## 🏗️ Step 4: Architectural Best Practices

To get the best performance out of a distributed database:

| Topic | PostgreSQL | CockroachDB Recommendation |
|-------|------------|----------------------------|
| **Primary Keys** | Usually `SERIAL` (Monotonic) | Use **`UUID`** or `BIGINT` to avoid "hotspots". |
| **Indexes** | B-Tree | Secondary indexes are supported but use them judiciously. |
| **Joins** | Local Join | Try to avoid extremely wide joins; use `LOOKUP JOIN`. |
| **FK Constraints** | Process-level | Validated across the cluster (adds small latency). |

---

## 🧪 Step 5: Verification

After migration, verify row counts and data integrity.

```bash
# Verify data consistency using MOLT
./molt verify data \
  --source "postgres://user:pass@pg-host:5432/dbname" \
  --target "postgres://user:pass@crdb-host:26257/dbname"
```

---

## 🔌 Step 6: Application Cutover

1. Update your application connection string.
2. Point to the **HAProxy IP** (Port 26257) or **PgBouncer IP** (Port 6432).
3. Change the driver (if using a very old one), though standard `libpq` or `pg` drivers work perfectly.

---

### Need Help?
- [CockroachDB Migration Docs](https://www.cockroachlabs.com/docs/stable/migration-overview.html)
- [MOLT Tool Documentation](https://www.cockroachlabs.com/docs/stable/molt.html)
