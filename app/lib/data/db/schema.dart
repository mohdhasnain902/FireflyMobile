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
  2: _addTransactionExternalId,
  3: _invalidateTransactionLwwCursor,
  4: _addTransactionOptionColumns,
  5: _addBillDate,
  6: _invalidateSubscriptionAndRuleCursor,
};

/// Version 2 — store a journal's `external_id`.
///
/// Firefly puts `external_id` on 522 of the 547 journals on the reference book
/// (imports and bank feeds key off it). Without a column the pull dropped it
/// and any phone edit of such a journal pushed a payload with no
/// `external_id`, which clears it server-side: a silent loss of a field the
/// website shows on every transaction form.
const List<String> _addTransactionExternalId = [
  'ALTER TABLE transactions ADD COLUMN external_id TEXT',
];

/// Version 3 — backfill `external_id` for rows already mirrored.
///
/// The new column can only be filled from the server, and the pull skips any
/// row whose `remote_updated_at` is not older than the server's. Without this,
/// every already-mirrored leg would keep a NULL `external_id` forever (522 of
/// 547 on the reference book, and it is exactly what happened on the first
/// upgrade: the legs pulled before the install finished stayed NULL). Clearing
/// the LWW cursor makes the next pull rewrite every leg once.
///
/// Kept as its own version rather than folded into 2 so a device that already
/// ran 2 still gets the backfill.
const List<String> _invalidateTransactionLwwCursor = [
  'UPDATE transactions SET remote_updated_at = NULL',
];

/// Version 4 — store Firefly's per-journal "Options" fields.
///
/// The website's transaction form carries five extra dates plus an external
/// URL, an internal reference and a manual order. The pull dropped all eight,
/// and because Firefly replaces the journal on a write, editing such a
/// transaction on the phone silently cleared them server-side. Storing them
/// makes both sides hold the same object.
///
/// The LWW cursor is cleared again (same reason as v3): rows mirrored before
/// this version keep NULL for the new columns unless the next pull rewrites
/// them.
const List<String> _addTransactionOptionColumns = [
  'ALTER TABLE transactions ADD COLUMN interest_date TEXT',
  'ALTER TABLE transactions ADD COLUMN book_date TEXT',
  'ALTER TABLE transactions ADD COLUMN process_date TEXT',
  'ALTER TABLE transactions ADD COLUMN due_date TEXT',
  'ALTER TABLE transactions ADD COLUMN payment_date TEXT',
  'ALTER TABLE transactions ADD COLUMN external_url TEXT',
  'ALTER TABLE transactions ADD COLUMN internal_reference TEXT',
  'ALTER TABLE transactions ADD COLUMN order_index INTEGER',
  'UPDATE transactions SET remote_updated_at = NULL',
];

/// Version 5 — store a bill's next due date.
///
/// Firefly's bill object carries the next due date in `date`, the field its own
/// form shows and its write endpoint *requires*. The schema had no column, so
/// the pull dropped it and a bill edited on the phone pushed a payload without
/// it (422).
///
/// The LWW cursor is cleared again (same reason as v3/v4): bills mirrored
/// before this version keep NULL until the next pull rewrites them.
///
/// The column is deliberately absent from the v1 `CREATE TABLE bills`: a fresh
/// install replays every migration in order, so adding it in both places fails
/// with "duplicate column name: date".
const List<String> _addBillDate = [
  'ALTER TABLE bills ADD COLUMN date TEXT',
  'UPDATE bills SET remote_updated_at = NULL',
];

/// Version 6 — re-read subscriptions and rules with their real wire keys.
///
/// They were mirrored with the wrong keys (`title`/`amount`/`next_date` on a
/// payload that only has `name`/`amount_min`/`date`, and `stop` where Firefly
/// sends `stop_processing`), so the stored rows are blank, zero and dateless.
/// Fixing the parser is not enough on a device that already holds those rows:
/// the pull compares `remote_updated_at` and skips them as unchanged. Clearing
/// the cursor forces one rewrite, exactly like v3 and v5 did.
///
/// v5 only cleared `bills`, which is why a device upgraded through it kept the
/// broken subscription rows — this is its own version so those devices heal too.
const List<String> _invalidateSubscriptionAndRuleCursor = [
  'UPDATE subscriptions SET remote_updated_at = NULL',
  'UPDATE rules SET remote_updated_at = NULL',
];

/// Version 2 (Model B) was folded into v1 before this schema ever shipped, so
/// there is no migration list for it: the Model B recurrence columns
/// (`type`, `first_date`, `repeat_until`, `apply_rules`, `latest_date`) and the
/// `recurrence_repetitions` child table are part of the one initial create.
///
/// Do not reintroduce a `RENAME COLUMN recur_until` / `DROP COLUMN
/// repeat_freq` migration for them. SQLite's `onCreate` (a fresh install)
/// replays every migration in order, so such a statement would run against a
/// table v1 just created with the new column names and fail every fresh
/// install with "no such column".

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
  '''
CREATE TABLE sync_log (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at     INTEGER NOT NULL,
    phase          TEXT NOT NULL,
    status         TEXT NOT NULL,
    pushed_ops     INTEGER,
    pull_inserted  INTEGER,
    pull_updated   INTEGER,
    pull_tombstoned INTEGER,
    error          TEXT
)
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

  // Recurrence definitions are stored and synced; the server expands them into
  // transactions (DESIGN §3.1). Frequency is NOT a flat column: a recurrence
  // owns 1:N rows in `recurrence_repetitions`, which is the only model that can
  // express a multi-frequency recurrence the way Firefly does on the wire
  // (`repetitions[]`).
  //
  // `type` is the recurrence's transaction direction and `first_date` /
  // `repeat_until` / `apply_rules` are all wire-backed (RecurrenceTransformer
  // emits them on every pull), so they are real columns from the start rather
  // than re-derived from `transactions_json`. `latest_date` is the scheduler
  // cursor and is phone-local only — never pushed, so a re-run is idempotent.
  '''
CREATE TABLE recurrences (
    id                   TEXT PRIMARY KEY,
    title                TEXT NOT NULL,
    type                 TEXT,
    description          TEXT,
    first_date           TEXT,
    repeat_until         TEXT,
    nr_of_repetitions    INTEGER,
    active               INTEGER NOT NULL DEFAULT 1,
    apply_rules          INTEGER NOT NULL DEFAULT 1,
    transactions_json    TEXT,
    latest_date          TEXT,
    $syncBookkeepingColumns
)
''',
  syncIndexes('recurrences'),

  // Child table of recurrence frequencies. Deliberately has NO
  // `$syncBookkeepingColumns`: repetitions are not an independent synced
  // entity. They are owned entirely by their parent recurrence and ride along
  // in the parent's pull (the server nests them under `repetitions`), so they
  // are rewritten wholesale whenever the parent is upserted.
  '''
  CREATE TABLE recurrence_repetitions (
      recurrence_id      TEXT NOT NULL,
      ord                INTEGER NOT NULL,
      repetition_type    TEXT NOT NULL,
      repetition_moment  TEXT NOT NULL,
      repetition_skip    INTEGER NOT NULL DEFAULT 0,
      weekend            INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY (recurrence_id, ord)
  )
  ''',
  // Cheap lookup by parent when the scheduler loads a recurrence's schedule.
  '''
  CREATE INDEX IF NOT EXISTS idx_recurrence_repetitions_recurrence
      ON recurrence_repetitions(recurrence_id)
  ''',

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
