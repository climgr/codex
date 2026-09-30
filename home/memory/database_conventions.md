---
name: Database conventions
description: Schema management, parameterized queries, connection pooling, SQLite vs PostgreSQL selection, transaction patterns, and data safety rules
type: user
---

## Database Selection

| Scenario | Database | Rationale |
|----------|----------|-----------|
| Single-node server | **SQLite** — `{db_dir}/server.db` | Zero-config, embedded, no separate process |
| Cluster / multi-node | **PostgreSQL** | Shared state across nodes requires remote DB |
| CLI tool (local state) | SQLite | Same zero-config advantage |
| Library / package | None (caller provides) | Libraries must not own a database |

SQLite is the default. Switch to PostgreSQL only when multi-node cluster support is needed. Document the choice in `{project_dir}/IDEA.md`.

---

## Schema Management — No Migration Files

Use `CREATE TABLE IF NOT EXISTS` and idempotent `ALTER TABLE` statements executed on every startup. No migration table, no version tracking, no migration files.

```go
// EnsureSchema runs on startup — safe to run multiple times
func EnsureSchema(db *sql.DB) error {
    for _, stmt := range createStatements {
        if _, err := db.Exec(stmt); err != nil {
            return fmt.Errorf("create table: %w", err)
        }
    }
    for _, stmt := range schemaUpdates {
        if err := db.Exec(stmt); err != nil {
            if !isAlreadyExistsError(err) {
                return fmt.Errorf("schema update: %w", err)
            }
        }
    }
    return nil
}
```

### Schema update rules

| Rule | Detail |
|------|--------|
| **Always idempotent** | Every statement is safe to run multiple times |
| **Never destructive** | Never `DROP COLUMN`, `DROP TABLE`, or `DELETE` in schema updates |
| **Add only** | Add columns, add tables, add indexes |
| **Defaults required** | New columns must have `DEFAULT` or be `NULL`-able |
| **No renames** | Add new column, migrate data in application code, leave old column — never drop it |
| **Comment the version** | Each schema update entry notes the version that introduced it |

### Cross-database "column already exists" handling

```go
func isAlreadyExistsError(err error) bool {
    msg := strings.ToLower(err.Error())
    // SQLite
    return strings.Contains(msg, "duplicate column") ||
           // PostgreSQL
           strings.Contains(msg, "already exists") ||
           // MySQL
           strings.Contains(msg, "duplicate column name")
}
```

PostgreSQL v9.6+: prefer `ADD COLUMN IF NOT EXISTS` to avoid the error entirely.

---

## Parameterized Queries — Mandatory

**Never build SQL by string concatenation.** Always use parameterized queries.

```go
// WRONG — SQL injection risk
query := "SELECT * FROM users WHERE email = '" + email + "'"

// CORRECT
row := db.QueryRow("SELECT id, name FROM users WHERE email = ?", email)
```

```rust
// CORRECT (sqlx)
let user = sqlx::query_as!(User, "SELECT * FROM users WHERE email = ?", email)
    .fetch_one(&pool)
    .await?;
```

This applies everywhere: `WHERE`, `INSERT`, `UPDATE`, `DELETE`, `LIKE`, `IN` lists. No exceptions.

**`IN` lists**: build a parameterized placeholder list, never concatenate values:
```go
placeholders := strings.Repeat("?,", len(ids))
placeholders = strings.TrimRight(placeholders, ",")
query := fmt.Sprintf("SELECT * FROM users WHERE id IN (%s)", placeholders)
// Pass ids... as args
```

---

## Connection Pooling

Set explicit pool limits. Never use the driver's unlimited defaults in production code.

```go
db, err := sql.Open("sqlite3", dsn)
// or sql.Open("postgres", dsn)
// max simultaneous connections
db.SetMaxOpenConns(25)
// idle connections kept alive
db.SetMaxIdleConns(5)
// max connection age
db.SetConnMaxLifetime(5 * time.Minute)
// max idle time before close
db.SetConnMaxIdleTime(1 * time.Minute)
```

| Setting | SQLite | PostgreSQL |
|---------|--------|-----------|
| `MaxOpenConns` | 1 (SQLite is not concurrent-write safe) | 25 (tune per server) |
| `MaxIdleConns` | 1 | 5 |
| `ConnMaxLifetime` | 30 min | 5 min |

SQLite: open with `?_journal_mode=WAL&_busy_timeout=5000` for better concurrent read performance and write retry behavior.

---

## Transactions

- Wrap multi-step writes in a transaction — never leave the database in a partial-write state
- Always call `tx.Rollback()` in a `defer`; it is a no-op after `tx.Commit()`
- Never hold a transaction open across an HTTP request boundary — finish within the handler

```go
tx, err := db.BeginTx(ctx, nil)
if err != nil {
    return err
}
// no-op after Commit
defer tx.Rollback()

// ... multiple operations ...

return tx.Commit()
```

- Use `context.Context` for deadlines on every query — `db.QueryContext(ctx, ...)`, `db.ExecContext(ctx, ...)`. An undeadlined query is an eventual hang.

---

## Data Safety Rules

- `DELETE FROM` without a `WHERE` is forbidden — always filter by at least one column
- `DROP TABLE` / `DROP COLUMN` in application code is forbidden — schema changes are additive only
- Never `SELECT *` in application code — list columns explicitly; `*` breaks when schema evolves
- Index every foreign key column and every column used in a `WHERE` clause in hot queries
- Never store raw passwords — Argon2id only (see `sensitive_data.md`)
- Never store raw tokens — hash with SHA-256 before persisting; store the hash
- Encrypt at-rest when the database contains PII — document the encryption method in `IDEA.md`

---

## SQLite-Specific

- Default database path: `{db_dir}/server.db` and `{db_dir}/users.db` (see `{project_dir}/IDEA.md` for platform-specific `{db_dir}`)
- Always open with `?_journal_mode=WAL` for concurrent reads
- Always open with `?_foreign_keys=on` to enforce FK constraints
- Use `VACUUM` sparingly — only on user request or scheduled maintenance, never inline
- Backups: `sqlite3 src.db ".backup dst.db"` or the `VACUUM INTO` statement — never `cp` an open database file

---

## Query Patterns

Prefer small, focused queries over large JOINs when the join fan-out is unbounded. Fetch related rows in a second query and join in application code when the result set could be large.

Row-not-found is not an error in most cases — check `sql.ErrNoRows` explicitly and return a domain-level not-found value, not a 500.

```go
var user User
err := db.QueryRowContext(ctx, "SELECT id, name FROM users WHERE id = ?", id).Scan(&user.ID, &user.Name)
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}
if err != nil {
    return nil, fmt.Errorf("get user: %w", err)
}
return &user, nil
```
