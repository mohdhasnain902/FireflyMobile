/// Root dependency wiring for the offline UI (P2 §1).
///
/// Everything the screens need hangs off these providers:
///
/// * **Database layer** — one encrypted connection opened once per app run,
///   plus the `device_meta` and `op_log` DAOs riding on it.
/// * **Repositories** — one provider per entity, each bound to that single
///   connection so a queue write and the row it describes always share a
///   transaction (DESIGN §5.2).
/// * **List providers** — one `FutureProvider<List<T>>` per entity. They are
///   concrete typed providers so the generic list screen can watch and
///   invalidate them through `EntityConfig` with no dynamic typing anywhere.
/// * **Connection settings** — base URL + PAT store for the settings screen.
///
/// Tests override the seam providers ([keyStoreProvider],
/// [databasePathProvider], [connectionSettingsStoreProvider]) rather than
/// poking platform channels.
library;

import 'dart:io' show Platform;

import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/core/sync_status.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/dao/op_log_dao.dart';
import 'package:firefly_mobile/data/db/database_key_store.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:firefly_mobile/data/demo/demo_seeder.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:sqflite/sqflite.dart'
    show Database, DatabaseFactory, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

/// Secure storage for the SQLCipher key.
///
/// Overridden with an in-memory store in widget tests. On Linux desktop
/// hosts — which have no flutter_secure_storage implementation — it falls
/// back to an owner-only key file beside the database instead.
final keyStoreProvider = Provider<DatabaseKeyStore>((ref) {
  if (Platform.isLinux) {
    return FileDatabaseKeyStore(defaultDatabasePath);
  }
  return SecureStorageDatabaseKeyStore();
});

/// Where the on-disk database lives.
///
/// Overridden in widget tests to point at a temp path so no platform database
/// directory is touched.
final databasePathProvider = FutureProvider<String>(
  (ref) => defaultDatabasePath(),
);

/// [DatabaseFactory] for the host this build runs on.
///
/// Android and iOS keep sqflite's platform-channel factory, which routes
/// opens through the SQLCipher-backed plugin. Linux desktops have no
/// platform channel (this is a mobile app being demoed on a desktop), so
/// they bind `databaseFactoryFfi` instead — initialised in `main()` and the
/// same FFI backend the test suite already exercises.
DatabaseFactory get _appDatabaseFactory =>
    Platform.isLinux ? databaseFactoryFfi : databaseFactory;

/// The app's single encrypted SQLite connection.
///
/// Key order matches [openAppDatabase]: resolve the path, fetch (or create)
/// the SQLCipher key, open with `PRAGMA KEY` first.
final databaseProvider = FutureProvider<Database>((ref) async {
  final path = await ref.watch(databasePathProvider.future);
  final key = await ref.watch(keyStoreProvider).getOrCreateKey();
  return await openAppDatabase(
    factory: _appDatabaseFactory,
    path: path,
    password: key,
  );
});

/// Typed access to the `device_meta` key/value table.
final metaProvider = FutureProvider<DeviceMetaDao>(
  (ref) async => DeviceMetaDao(await ref.watch(databaseProvider.future)),
);

/// Number of ops still queued for the server — the sync badge's input.
///
/// Screens invalidate it after every mutation; P3's push loop will watch it.
final pendingOpsCountProvider = FutureProvider<int>(
  (ref) async =>
      await OpLogDao(await ref.watch(databaseProvider.future)).pendingCount(),
);

/// Snapshot powering the app-bar sync indicator (P2.3, DESIGN §3.2):
/// pending op count + last-sync timestamp + last-sync outcome.
///
/// Watches [pendingOpsCountProvider], so a mutation screen that invalidates
/// that provider cascades a refresh here — no separate invalidation needed.
final syncStatusProvider = FutureProvider<AppSyncStatus>((ref) async {
  final pending = await ref.watch(pendingOpsCountProvider.future);
  final meta = await ref.watch(metaProvider.future);
  final tsRaw = await meta.get(DeviceMetaDao.lastSyncTsKey);
  final statusRaw = await meta.get(DeviceMetaDao.lastSyncStatusKey);
  return AppSyncStatus(
    pendingOps: pending,
    // Unset or unparseable → null → state resolves to `never`.
    lastSyncTsMs: tsRaw == null ? null : int.tryParse(tsRaw),
    lastSyncStatus: statusRaw,
  );
});

// ---------------------------------------------------------------------------
// Repositories — one provider per entity, all sharing the single connection.
//
// The 13 write-capable repositories all take `{db, meta}` (their queue write
// allocates `seq` from `device_meta` inside the same transaction). Currencies
// are pull-only (DESIGN §3.1) so `CurrencyRepository` takes only the database
// and is wired accordingly.
// ---------------------------------------------------------------------------

/// Accounts (assets, expenses, revenue, cash, liabilities).
final accountRepositoryProvider = FutureProvider<AccountRepository>(
  (ref) async => AccountRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Receipt/file attachments (notes edit + delete in P2; upload is P3+).
final attachmentRepositoryProvider = FutureProvider<AttachmentRepository>(
  (ref) async => AttachmentRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Recurring bills.
final billRepositoryProvider = FutureProvider<BillRepository>(
  (ref) async => BillRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Budgets.
final budgetRepositoryProvider = FutureProvider<BudgetRepository>(
  (ref) async => BudgetRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Budget limits (per-period amounts inside a budget).
final budgetLimitRepositoryProvider = FutureProvider<BudgetLimitRepository>(
  (ref) async => BudgetLimitRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Transaction categories.
final categoryRepositoryProvider = FutureProvider<CategoryRepository>(
  (ref) async => CategoryRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Currencies — read-only, because the phone never writes them.
final currencyRepositoryProvider = FutureProvider<CurrencyRepository>(
  (ref) async => CurrencyRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Piggy banks.
final piggyBankRepositoryProvider = FutureProvider<PiggyBankRepository>(
  (ref) async => PiggyBankRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Recurring transactions.
final recurrenceRepositoryProvider = FutureProvider<RecurrenceRepository>(
  (ref) async => RecurrenceRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Rules.
final ruleRepositoryProvider = FutureProvider<RuleRepository>(
  (ref) async => RuleRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Rule groups.
final ruleGroupRepositoryProvider = FutureProvider<RuleGroupRepository>(
  (ref) async => RuleGroupRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Subscriptions.
final subscriptionRepositoryProvider = FutureProvider<SubscriptionRepository>(
  (ref) async => SubscriptionRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Tags.
final tagRepositoryProvider = FutureProvider<TagRepository>(
  (ref) async => TagRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

/// Withdrawals, deposits and transfers.
final transactionRepositoryProvider = FutureProvider<TransactionRepository>(
  (ref) async => TransactionRepository(
    db: await ref.watch(databaseProvider.future),
    meta: await ref.watch(metaProvider.future),
  ),
);

// ---------------------------------------------------------------------------
// List providers — the page the list screens render.
//
// Each loads the newest 50 rows (`getAll` defaults to `updated_at DESC`), the
// page size the P2 plan fixes; search filters that page client-side until a
// server-side search pass lands with P3's pull. Returning a concrete
// `FutureProvider<List<T>>` is what lets [EntityConfig] store a typed
// reference the generic screen can watch without ever seeing `dynamic`.
// ---------------------------------------------------------------------------

/// Newest 50 accounts.
final accountListProvider = FutureProvider<List<Account>>(
  (ref) async {
    final repo = await ref.watch(accountRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 attachments.
final attachmentListProvider = FutureProvider<List<Attachment>>(
  (ref) async {
    final repo = await ref.watch(attachmentRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 bills.
final billListProvider = FutureProvider<List<Bill>>(
  (ref) async {
    final repo = await ref.watch(billRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 budgets.
final budgetListProvider = FutureProvider<List<Budget>>(
  (ref) async {
    final repo = await ref.watch(budgetRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 budget limits.
final budgetLimitListProvider = FutureProvider<List<BudgetLimit>>(
  (ref) async {
    final repo = await ref.watch(budgetLimitRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 categories.
final categoryListProvider = FutureProvider<List<Category>>(
  (ref) async {
    final repo = await ref.watch(categoryRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 currencies.
final currencyListProvider = FutureProvider<List<Currency>>(
  (ref) async {
    final repo = await ref.watch(currencyRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 piggy banks.
final piggyBankListProvider = FutureProvider<List<PiggyBank>>(
  (ref) async {
    final repo = await ref.watch(piggyBankRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 recurrences.
final recurrenceListProvider = FutureProvider<List<Recurrence>>(
  (ref) async {
    final repo = await ref.watch(recurrenceRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 rules.
final ruleListProvider = FutureProvider<List<Rule>>(
  (ref) async {
    final repo = await ref.watch(ruleRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 rule groups.
final ruleGroupListProvider = FutureProvider<List<RuleGroup>>(
  (ref) async {
    final repo = await ref.watch(ruleGroupRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 subscriptions.
final subscriptionListProvider = FutureProvider<List<Subscription>>(
  (ref) async {
    final repo = await ref.watch(subscriptionRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Newest 50 tags.
final tagListProvider = FutureProvider<List<Tag>>(
  (ref) async {
    final repo = await ref.watch(tagRepositoryProvider.future);
    final rows = await repo.getAll(limit: 50);
    return rows;
  },
);

/// Every tag name already used in the book, alphabetically.
///
/// The transaction form's tag chips offer these for one-tap re-use (Firefly's
/// tag field autocompletes from the same pool). Two sources are merged because
/// each alone can miss: the pulled `tags` table (what the website knows as a
/// tag resource) and the `tags_json` of every transaction (a tag typed on the
/// phone before its first sync, or one the server lists only on a journal).
final tagSuggestionsProvider = FutureProvider<List<String>>((ref) async {
  final tags = await ref.watch(tagListProvider.future);
  final transactions = await ref.watch(ledgerTransactionsProvider.future);
  final seen = <String, String>{};
  void add(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    seen.putIfAbsent(tag.toLowerCase(), () => tag);
  }

  for (final tag in tags) {
    if (tag.deletedAt == null) add(tag.tag);
  }
  for (final row in transactions) {
    for (final tag in jsonListFromColumn(row.tagsJson).whereType<String>()) {
      add(tag);
    }
  }
  final names = seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return names;
});

/// The whole book, in the website's own order.
///
/// Firefly III lists transactions by `date DESC` and breaks same-instant ties
/// by journal id descending (verified across all 510 date buckets of the
/// reference book, where the API is monotone in exactly that sort). The list
/// must therefore load every row, not a 50-row page: a page ordered by
/// `updated_at` both reordered the book and hid 496 of 546 legs.
final transactionListProvider = FutureProvider<List<Transaction>>(
  (ref) async {
    final repo = await ref.watch(transactionRepositoryProvider.future);
    final rows = await repo.getAll(
      orderBy: kTransactionListOrder,
      limit: kLedgerQueryLimit,
    );
    return rows;
  },
);

/// The website's transaction order: newest first, ties by journal id.
///
/// `journal_id` is a numeric string server-side, so the cast keeps 999 before
/// 1000. Locally-created rows have no journal id yet (NULL sorts last within
/// its date), which is where a not-yet-pushed transaction belongs.
const String kTransactionListOrder =
    'date DESC, CAST(journal_id AS INTEGER) DESC';

// ---------------------------------------------------------------------------
// Ledger providers — every row, no page limit.
//
// Dashboard balances and net worth are sums over the whole history, so a
// 50-row page silently computed wrong numbers on a real book (546 transactions
// on the reference device put SadaPay at 7,102.53 instead of 4,041.00).
// List screens keep the paged providers above; only summaries read these.
// ---------------------------------------------------------------------------

/// Every transaction the phone holds, across all dates.
final ledgerTransactionsProvider = FutureProvider<List<Transaction>>(
  (ref) async {
    final repo = await ref.watch(transactionRepositoryProvider.future);
    return await repo.getAll(
      orderBy: kTransactionListOrder,
      limit: kLedgerQueryLimit,
    );
  },
);

/// Every account the phone holds (114 on the reference device, not 50).
final ledgerAccountsProvider = FutureProvider<List<Account>>(
  (ref) async {
    final repo = await ref.watch(accountRepositoryProvider.future);
    return await repo.getAll(limit: kLedgerQueryLimit);
  },
);

/// Row cap for summary queries — effectively "all", matching Reports.
const int kLedgerQueryLimit = 100000;

// ---------------------------------------------------------------------------
// Connection settings (P2 §4).
// ---------------------------------------------------------------------------

/// Store holding the base URL and PAT.
///
/// Overridden with [InMemoryConnectionSettingsStore] in widget tests.
final connectionSettingsStoreProvider = FutureProvider<ConnectionSettingsStore>(
  (ref) async {
    final meta = await ref.watch(metaProvider.future);
    return DeviceConnectionSettingsStore(meta: meta);
  },
);

/// Current settings as read from `device_meta` + secure storage.
///
/// Screens watch this and invalidate it after every save so the form always
/// shows what is actually persisted.
final connectionSettingsProvider = FutureProvider<ConnectionSettings>(
  (ref) async {
    final store = await ref.watch(connectionSettingsStoreProvider.future);
    return await store.read();
  },
);

/// HTTP client the sync engine uses to reach Firefly (P3.1).
///
/// Built from [connectionSettingsStoreProvider] so a URL/token save on the
/// settings screen takes effect without rebuilding the client. Tests that
/// exercise the sync engine override [connectionSettingsStoreProvider] with
/// [InMemoryConnectionSettingsStore] — this provider then builds a real
/// client bound to the in-memory store (no Keystore).
final fireflyApiClientProvider = FutureProvider<FireflyApiClient>(
  (ref) async {
    final store = await ref.watch(connectionSettingsStoreProvider.future);
    return FireflyApiClient(settings: store);
  },
);

// ---------------------------------------------------------------------------
// Sync engine + trigger controller (P3.2/P3.6).
// ---------------------------------------------------------------------------

/// HTTP client for the PC backup sidecar (P4, best-effort).
///
/// Built from the same [connectionSettingsStoreProvider] as the Firefly
/// client, so a backup URL/token saved on the settings screen takes effect
/// on the next sync. The client reads settings fresh per trigger anyway —
/// this provider only owns the client's lifetime.
final backupClientProvider = FutureProvider<BackupClient>((ref) async {
  final store = await ref.watch(connectionSettingsStoreProvider.future);
  return BackupClient(settings: store);
});

/// The sync engine — one per app run, bound to the shared database and the
/// settings-bound API client.
///
/// Tests that need a sync cycle override this directly with a
/// [SyncEngine] built over an in-memory database (the pattern used by
/// `test/data/sync/sync_engine_test.dart`).
final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final client = await ref.watch(fireflyApiClientProvider.future);
  final backup = await ref.watch(backupClientProvider.future);
  return SyncEngine(db: db, client: client, backup: backup);
});

/// In-app sync log, newest first, up to [kMaxSyncLogEntries] (500) rows.
///
/// `autoDispose` so the log screen re-reads (and re-shows) fresh rows on
/// every open instead of a session-cached snapshot.
final FutureProvider<List<SyncLogEntry>> syncLogProvider =
    FutureProvider.autoDispose<List<SyncLogEntry>>((ref) async {
      final engine = await ref.watch(syncEngineProvider.future);
      return await engine.recentLog(limit: kMaxSyncLogEntries);
    });

/// Probe-gated sync triggers shared by Settings, the list pull-to-refresh,
/// the app-bar "Sync now" button and the lifecycle auto-sync.
///
/// Single instance per container: the in-flight coalescing inside
/// [SyncController] only works when every trigger talks to the same object.
/// Seams read (not watch) their sources — settings changes are picked up on
/// the next trigger, never mid-cycle.
final syncControllerProvider = Provider<SyncController>((ref) {
  return SyncController(
    engine: () => ref.read(syncEngineProvider.future),
    isConfigured: () async {
      final settings = await ref.read(connectionSettingsProvider.future);
      return settings.isConfigured;
    },
    probe: () async {
      final settings = await ref.read(connectionSettingsProvider.future);
      return await probeFirefly(baseUrl: settings.baseUrl, pat: settings.pat);
    },
  );
});

// ---------------------------------------------------------------------------
// Demo data (P2 demo polish) — seeder + first-frame auto-seed seam.
// ---------------------------------------------------------------------------

/// Toggle: should the HomeShell first frame auto-seed an empty database?
///
/// Defaults to true for the demo build. Widget tests override this to false
/// so the smoke/home-shell suites keep their empty-DB expectations (R19).
final demoSeedEnabledProvider = Provider<bool>((ref) => true);

/// Every list provider the demo seeder/eraser must invalidate after a write.
///
/// Kept as one list so Settings' Load/Erase handlers and the auto-seed path
/// stay in sync when a new entity list is added.
final List<ProviderBase<Object?>> allEntityListProviders =
    <ProviderBase<Object?>>[
  accountListProvider,
  attachmentListProvider,
  billListProvider,
  budgetListProvider,
  budgetLimitListProvider,
  categoryListProvider,
  currencyListProvider,
  piggyBankListProvider,
  recurrenceListProvider,
  ruleListProvider,
  ruleGroupListProvider,
  subscriptionListProvider,
  tagListProvider,
  transactionListProvider,
];

/// Every provider whose contents come from the synced database.
///
/// [allEntityListProviders] covers the entity screens; the ledger providers
/// back the Dashboard and Reports, which read whole-history aggregates rather
/// than a page. A pull changes local rows, so after one **every** screen must
/// re-query: invalidating only the list providers left the Dashboard showing
/// an account (and a net worth including it) that the website had just
/// deleted, until the app was restarted.
final List<ProviderBase<Object?>> allSyncedDataProviders =
    <ProviderBase<Object?>>[
  ...allEntityListProviders,
  ledgerTransactionsProvider,
  ledgerAccountsProvider,
  tagSuggestionsProvider,
];

/// Post-frame one-shot: seed the demo dataset if the DB is empty.
///
/// Called once from HomeShell initState. Skips immediately when
/// [demoSeedEnabledProvider] is false (tests) or the DB already has data.
/// After a successful seed it invalidates every list provider so the
/// dashboard and entity screens re-query without a restart.
final FutureProvider<bool> autoDemoSeedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  if (!ref.watch(demoSeedEnabledProvider)) return false;
  final db = await ref.watch(databaseProvider.future);
  final seeded = await ensureDemoSeeded(db);
  if (seeded) {
    allEntityListProviders.forEach(ref.invalidate);
    // pendingOpsCount / syncStatus never change: demo rows are born synced
    // with no op_log entries.
  }
  return seeded;
});
