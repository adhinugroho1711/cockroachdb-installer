-- SOP CockroachDB - Advanced Transaction & Schema Optimization
-- Fokus: High-Volume OLTP & Monitoring
-- 1. Anti-Hotspot PK (Review)
-- Menggunakan UUID v4/v7 atau Hash-sharded Index untuk tabel yang sangat write-heavy.
CREATE TABLE order_items (
    order_id UUID NOT NULL,
    item_id UUID NOT NULL,
    quantity INT,
    price DECIMAL(15, 2),
    PRIMARY KEY (order_id, item_id)
) INTERLEAVE IN PARENT orders (order_id);
-- Jika tabel orders ada (optimasi join)
-- 2. Transaksi Volume Besar (Batching)
-- Daripada 1000 INSERT individual, gunakan batch 100-500 row.
-- CockroachDB sangat efisien dengan batching untuk mengurangi overhead Raft.
-- INSERT INTO orders (...) VALUES (...), (...), ... ;
-- 3. Stale Reads untuk Read-Heavy High Volume
-- Jika data tidak harus real-time (misal dashboard/history), gunakan follower reads.
-- Ini sangat mengurangi beban pada Leaseholder (Primary node untuk data tersebut).
-- SELECT * FROM orders AS OF SYSTEM TIME follower_read_timestamp() WHERE ...;
-- 4. Transaction Retries (Client Side Logic)
-- Karena CockroachDB menggunakan Serializable Isolation, transaksi bisa gagal (40001).
-- Pastikan aplikasi memiliki wrapper:
-- loop {
--    START TRANSACTION;
--    EXECUTE SQL;
--    COMMIT;
--    if (success) break;
--    if (error == 40001) continue; -- Retry
-- }
-- 5. Monitoring via SQL
-- Cek query yang sedang berjalan dan paling lambat (Slow Queries)
SELECT query,
    start,
    now() - start AS duration
FROM crdb_internal.node_queries
WHERE now() - start > '5s';
-- Cek statistik tabel (cek jika ada range yang tidak seimbang)
-- SHOW RANGES FROM TABLE table_name;