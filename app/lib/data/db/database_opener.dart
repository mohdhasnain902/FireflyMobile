import 'package:firefly_mobile/data/db/schema.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Highest schema version this build understands.
///
/// Derived from [migrations] so a new migration cannot be added without the
/// open path picking it up.
final int latestSchemaVersion =
    migrations.keys.reduce((a, b) => a > b ? a : b);

/// Opens the local database, applying any pending schema migrations.
///
/// Responsibilities, in the order they matter:
///
/// 1. **Encryption.** When [password] is supplied, `PRAGMA KEY` is the very
///    first statement issued. SQLCipher rejects every subsequent statement
///    until the key is correct, so a wrong or missing key fails the open
///    rather than returning a silently empty database.
/// 2. **WAL.** Write-ahead logging is enabled on every open, not just on
///    create, so a database created by an older build (or by a test fixture)
///    still ends up in WAL mode.
/// 3. **Foreign keys.** Off by default in SQLite; enabling it makes the
///    `REFERENCES` clauses in [migrations] actually enforce.
///
/// [factory] is injected rather than imported so unit tests can drive the
/// same code path through `sqflite_common_ffi` without a device.
Future<Database> openAppDatabase({
  required DatabaseFactory factory,
  required String path,
  String? password,
}) {
  return factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: latestSchemaVersion,
      onConfigure: (db) => _onConfigure(db, password),
      onCreate: (db, version) => _applyMigrations(db, 0, version),
      onUpgrade: _applyMigrations,
      onOpen: _onOpen,
    ),
  );
}

Future<void> _onConfigure(Database db, String? password) async {
  if (password != null) {
    // Single-quoted literal; the key alphabet is URL-safe base64, which
    // contains no quote character (see database_key_store.dart).
    await db.execute("PRAGMA KEY = '$password'");
  }
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<void> _onOpen(Database db) async {
  // `journal_mode` returns the resulting mode as a row, so it must be read
  // back with a query rather than executed as a bare statement.
  await db.rawQuery('PRAGMA journal_mode = WAL');
}

/// Runs every migration between (but not including) [from] up to and
/// including [to].
///
/// An unknown target version is a programming error — the migration map and
/// the version bump must land in the same change — so it throws instead of
/// leaving a half-migrated database.
Future<void> _applyMigrations(Database db, int from, int to) async {
  for (var version = from + 1; version <= to; version++) {
    final statements = migrations[version];
    if (statements == null) {
      throw StateError(
        'No migration defined for schema version $version. '
        'Add it to migrations in lib/data/db/schema.dart.',
      );
    }
    // Each version is applied as a unit so a mid-list failure rolls the whole
    // version back rather than leaving some tables created and some not.
    await db.transaction((txn) async {
      for (final sql in statements) {
        await txn.execute(sql);
      }
    });
  }
}
