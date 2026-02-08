{{- define "hubble-timescape-clickhouse.tablemetrics-queries" -}}
SELECT
  'clickhouse_system_parts_rows' as name,
  sum(rows) as value,
  map('database', database, 'table', table) as labels,
  'gauge' as type,
  'Total number of rows' as help
FROM system.parts
WHERE active
GROUP BY
  database,
  table
ORDER BY
  database,
  table

UNION ALL

SELECT
  'clickhouse_system_parts_total_size' as name,
  sum(bytes) as value,
  map('database', database, 'table', table) as labels,
  'gauge' as type,
  'Total table size in bytes' as help
FROM system.parts
WHERE active
GROUP BY
  database,
  table
ORDER BY
  database,
  table

UNION ALL

SELECT
  'clickhouse_system_parts_largest_size' as name,
  max(bytes) as value,
  map('database', database, 'table', table) as labels,
  'gauge' as type,
  'Size of the largest part in bytes' as help
FROM system.parts
WHERE active
GROUP BY
  database,
  table
ORDER BY
  database,
  table

UNION ALL

SELECT
  'clickhouse_system_parts_primary_keys_size' as name,
  sum(primary_key_bytes_in_memory) as value,
  map('database', database, 'table', table) as labels,
  'gauge' as type,
  'Total size of the primary keys in bytes' as help
FROM system.parts
WHERE active
GROUP BY
  database,
  table
ORDER BY
  database,
  table

UNION ALL

SELECT
  'clickhouse_system_parts_count' as name,
  count(*) as value,
  map('database', database, 'table', table, 'state', multiIf(active, 'active', 'inactive')) as labels,
  'gauge' as type,
  'Total number of parts' as help
FROM system.parts
GROUP BY
  database,
  table,
  active
ORDER BY
  database,
  table,
  active

FORMAT Prometheus
{{- end -}}
