/// Local SQLite schema (DESIGN §5.1–5.3).
///
/// One source of truth for DDL. Statements are applied in order by
/// [migrations]; each integer key is a `PRAGMA user_version`, so the schema
/// only ever moves forward and a downgrade attempt fails loudly instead of
/// silently corrupting data.
library;

/// Bookkeeping columns shared by every business table.
///
/// Kept as a fragment so the seven columns cannot drift between tables. The
/// column names match DESIGN §5.1 exactly.
const String syncBookkeepingColumns = '''
    firefly_id          TEXT,
    updated_at          INTEGER NOT NULL,
    remote_updated_at   INTEGER,
    sync_status         TEXT NOT NULL DEFAULT 'pending',
    deleted_at          INTEGER,
    seq                 INTEGER NOT NULL
''';

/// Builds the trailing sync-status bookkeeping for a business table plus the
/// two indexes DESIGN §5.1 shows on `transactions`.
///
/// [tableName] is the table the indexes should be created on.
String syncIndexes(String tableName) => '''
CREATE INDEX IF NOT EXISTS idx_${tableName}_remote_updated
    ON $tableName(remote_updated_at);
CREATE INDEX IF NOT EXISTS idx_${tableName}_sync_status
    ON $tableName(sync_status);
CREATE INDEX IF NOT EXISTS idx_${tableName}_deleted
    ON $tableName(deleted_at);
''';

/// Schema migrations keyed by target `PRAGMA user_version`.
///
/// Version 1 is the complete initial schema: every business table from
/// DESIGN §5.1, the op log from §5.2, and device meta from §5.3. Future
/// schema changes must be added as new keys (2, 3, …) rather than edited in
/// place, so an installed app migrates forward correctly.
final Map<int, List<String>> migrations = {
  1: _initialSchema,
};

// `syncIndexes(...)` is a function call, so this list cannot be const even
// though its contents are compile-time strings.
final List<String> _initialSchema = [
  // ---------------------------------------------------------------------
  // Sync infrastructure (DESIGN §5.2, §5.3)
  // ---------------------------------------------------------------------
  '''
CREATE TABLE device_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
)
''',
  '''
CREATE TABLE op_log (
    op_id       TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    entity_id   TEXT NOT NULL,
    action      TEXT NOT NULL,
    payload     TEXT,
    wall_ts     INTEGER NOT NULL,
    device_id   TEXT NOT NULL,
    seq         INTEGER NOT NULL,
    created_at  INTEGER NOT NULL,
    attempts    INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT
)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_oplog_order
    ON op_log(wall_ts, device_id, seq)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_oplog_pending
    ON op_log(entity_type, entity_id)
''',

  // ---------------------------------------------------------------------
  // Business entities. Each carries [syncBookkeepingColumns].
  // ---------------------------------------------------------------------

  // Currency is pull-only: the phone never creates one, so `sync_status` is
  // always 'synced' (DESIGN §3.1).
  '''
CREATE TABLE currencies (
    id             TEXT PRIMARY KEY,
    code           TEXT NOT NULL,
    name           TEXT NOT NULL,
    symbol         TEXT,
    symbol_first   INTEGER NOT NULL DEFAULT 0,
    decimal_places INTEGER NOT NULL DEFAULT 2,
    enabled        INTEGER NOT NULL DEFAULT 1,
    is_default     INTEGER NOT NULL DEFAULT 0,
    rate           TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('currencies'),

  '''
CREATE TABLE accounts (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    type                TEXT NOT NULL,
    currency_code       TEXT,
    currency_id         TEXT,
    account_role        TEXT,
    opening_balance     TEXT,
    opening_balance_date TEXT,
    iban                TEXT,
    bic                 TEXT,
    account_number      TEXT,
    order_index         INTEGER,
    active              INTEGER NOT NULL DEFAULT 1,
    virtual_balance     TEXT,
    notes               TEXT,
    include_net_worth   INTEGER NOT NULL DEFAULT 1,
    $syncBookkeepingColumns
)
''',
  syncIndexes('accounts'),

  '''
CREATE TABLE budgets (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    notes          TEXT,
    currency_code  TEXT,
    currency_id    TEXT,
    active         INTEGER NOT NULL DEFAULT 1,
    order_index    INTEGER,
    auto_budget_type TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('budgets'),

  '''
CREATE TABLE budget_limits (
    id            TEXT PRIMARY KEY,
    budget_id     TEXT NOT NULL,
    start         TEXT NOT NULL,
    end           TEXT NOT NULL,
    amount        TEXT NOT NULL,
    currency_code TEXT,
    currency_id   TEXT,
    notes         TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('budget_limits'),

  '''
CREATE TABLE categories (
    id    TEXT PRIMARY KEY,
    name  TEXT NOT NULL,
    notes TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('categories'),

  '''
CREATE TABLE tags (
    id   TEXT PRIMARY KEY,
    tag  TEXT NOT NULL,
    date TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('tags'),

  '''
CREATE TABLE bills (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    amount              TEXT NOT NULL,
    currency_code       TEXT,
    currency_id         TEXT,
    bill_direction      TEXT,
    repeat_freq         TEXT NOT NULL DEFAULT 'monthly',
    skip                INTEGER NOT NULL DEFAULT 0,
    active              INTEGER NOT NULL DEFAULT 1,
    pay_dates           TEXT,
    remaining_amount    TEXT,
    next_expected_match TEXT,
    notes               TEXT,
    auto_budget_type    TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('bills'),

  '''
CREATE TABLE subscriptions (
    id                  TEXT PRIMARY KEY,
    title               TEXT NOT NULL,
    amount              TEXT NOT NULL,
    currency_code       TEXT,
    currency_id         TEXT,
    transaction_journal_id TEXT,
    repeat_freq         TEXT NOT NULL DEFAULT 'monthly',
    active              INTEGER NOT NULL DEFAULT 1,
    next_date           TEXT,
    end_date            TEXT,
    periods             TEXT,
    method              TEXT,
    notes               TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('subscriptions'),

  '''
CREATE TABLE piggy_banks (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    account_id     TEXT,
    target_amount  TEXT,
    current_amount TEXT,
    start_date     TEXT,
    target_date    TEXT,
    currency_code  TEXT,
    currency_id    TEXT,
    order_index    INTEGER,
    notes          TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('piggy_banks'),

  '''
CREATE TABLE rule_groups (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    description TEXT,
    active      INTEGER NOT NULL DEFAULT 1,
    order_index INTEGER,
    $syncBookkeepingColumns
)
''',
  syncIndexes('rule_groups'),

  // Rule definitions are stored and synced, but never executed on the phone
  // (DESIGN §3.1). Trigger/action bodies stay verbatim as JSON so a rule
  // round-trips to the server without lossy re-mapping.
  '''
CREATE TABLE rules (
    id            TEXT PRIMARY KEY,
    title         TEXT NOT NULL,
    description   TEXT,
    rule_group_id TEXT,
    trigger       TEXT,
    active        INTEGER NOT NULL DEFAULT 1,
    strict        INTEGER NOT NULL DEFAULT 0,
    stop          INTEGER NOT NULL DEFAULT 0,
    order_index   INTEGER,
    scope         TEXT,
    triggers_json TEXT,
    actions_json  TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('rules'),

  // Recurrence definitions are likewise server-executed only (DESIGN §3.1).
  '''
CREATE TABLE recurrences (
    id                   TEXT PRIMARY KEY,
    title                TEXT NOT NULL,
    description          TEXT,
    repeat_freq          TEXT NOT NULL DEFAULT 'monthly',
    recur_until          TEXT,
    nr_of_repetitions    INTEGER,
    active               INTEGER NOT NULL DEFAULT 1,
    transactions_json    TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('recurrences'),

  // Attachment bytes live on disk; the row holds metadata plus a local path
  // to the file staged for multipart upload.
  '''
CREATE TABLE attachments (
    id           TEXT PRIMARY KEY,
    filename     TEXT NOT NULL,
    notes        TEXT,
    md5          TEXT,
    size         INTEGER,
    mime_type    TEXT,
    download_url TEXT,
    local_path   TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('attachments'),

  // The canonical entity from DESIGN §5.1. `tags_json` mirrors Firefly's
  // `tags` array on the wire (array of tag names) so the create payload needs
  // no join-table reconstruction.
  '''
CREATE TABLE transactions (
    id                  TEXT PRIMARY KEY,
    journal_id          TEXT,
    type                TEXT NOT NULL,
    description         TEXT NOT NULL,
    date                TEXT NOT NULL,
    amount              TEXT NOT NULL,
    currency_code       TEXT,
    currency_id         TEXT,
    source_account_id   TEXT,
    dest_account_id     TEXT,
    source_name         TEXT,
    dest_name           TEXT,
    category_id         TEXT,
    category_name       TEXT,
    budget_id          TEXT,
    budget_name         TEXT,
    bill_id             TEXT,
    bill_name           TEXT,
    tags_json           TEXT,
    notes               TEXT,
    reconciled          INTEGER NOT NULL DEFAULT 0,
    foreign_amount      TEXT,
    foreign_currency_code TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('transactions'),
];
