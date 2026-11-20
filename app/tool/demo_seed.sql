-- Demo data for eyeballing the transactions 2nd-UI list on desktop.
-- Apply through the app's own SQLCipher build; the key lives beside the DB:
--   KEY=$(cat ~/.local/share/firefly_mobile/firefly.db.key)
--   { echo "PRAGMA key = '$KEY';"; cat tool/demo_seed.sql; } | sqlcipher ~/.local/share/firefly_mobile/firefly.db
-- Idempotent: every row is keyed with a stable demo-* id (INSERT OR IGNORE).

PRAGMA foreign_keys = OFF;

INSERT OR IGNORE INTO currencies
  (id, code, name, symbol, symbol_first, decimal_places, enabled, is_default,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-usd', 'USD', 'US Dollar', '$', 0, 2, 1, 1,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 1);

-- 1) Today — deposit, income category, tags, $ symbol
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-01', NULL, 'deposit', 'Salary',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','start of day','+9 hours'),
   '1200.50', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Income',
   NULL, NULL, NULL, NULL, '["income"]', NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 2);

-- 2) Today — small cash withdrawal
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-02', NULL, 'withdrawal', 'Coffee',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','start of day','+14 hours','+10 minutes'),
   '4.50', 'USD', 'demo-usd', NULL, NULL,
   'Cash', NULL, NULL, 'Food',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 3);

-- 3) Today — grocery run, two tags, still PENDING (clock badge demo)
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-03', NULL, 'withdrawal', 'Whole Foods',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','start of day','+19 hours','+40 minutes'),
   '72.18', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Groceries',
   NULL, NULL, NULL, NULL, '["food","home"]', NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'pending', NULL, 4);

-- 4) Yesterday — subscription
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-04', NULL, 'withdrawal', 'Netflix',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-1 day','start of day','+12 hours','+30 minutes'),
   '9.99', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Entertainment',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 5);

-- 5) Yesterday — transfer (source -> dest, no sign on amount)
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-05', NULL, 'transfer', 'To savings',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-1 day','start of day','+18 hours'),
   '100.00', 'USD', 'demo-usd', NULL, NULL,
   'Checking', 'Savings', NULL, NULL,
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 6);

-- 6) 3 days ago — rent
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-06', NULL, 'withdrawal', 'Rent',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-3 days','start of day','+10 hours'),
   '1250.00', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Housing',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 7);

-- 7) 10 days ago — freelance income
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-07', NULL, 'deposit', 'Freelance invoice',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-10 days','start of day','+16 hours','+45 minutes'),
   '430.20', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Income',
   NULL, NULL, NULL, NULL, '["work"]', NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 8);

-- 8) 40 days ago — older `MMM d` section, bill name
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-08', NULL, 'withdrawal', 'Electric bill',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-40 days','start of day','+11 hours'),
   '88.00', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Bills',
   NULL, NULL, NULL, 'PowerCo', NULL, 'Due monthly',
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 9);

-- 9) ~2 months ago — groceries
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-09', NULL, 'withdrawal', 'Groceries',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-60 days','start of day','+12 hours'),
   '145.30', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Groceries',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 10);

-- 10) ~3 months ago — utilities
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-10', NULL, 'withdrawal', 'Utilities',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-90 days','start of day','+10 hours'),
   '110.00', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Bills',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 11);

-- 11) ~5 months ago — shopping
INSERT OR IGNORE INTO transactions
  (id, journal_id, type, description, date, amount,
   currency_code, currency_id, source_account_id, dest_account_id,
   source_name, dest_name, category_id, category_name,
   budget_id, budget_name, bill_id, bill_name, tags_json, notes,
   reconciled, foreign_amount, foreign_currency_code,
   firefly_id, updated_at, remote_updated_at, sync_status, deleted_at, seq)
VALUES
  ('demo-11', NULL, 'withdrawal', 'Shopping',
   strftime('%Y-%m-%dT%H:%M:%S.000','now','localtime','-150 days','start of day','+15 hours'),
   '230.75', 'USD', 'demo-usd', NULL, NULL,
   'Checking', NULL, NULL, 'Shopping',
   NULL, NULL, NULL, NULL, NULL, NULL,
   0, NULL, NULL,
   NULL, CAST(strftime('%s','now') AS INTEGER)*1000, NULL, 'synced', NULL, 12);
