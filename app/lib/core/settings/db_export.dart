import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Copies the on-disk local database to a shareable file and returns its
/// path (P2 §4, debug aid).
///
/// A SQLite database in WAL mode keeps recent commits in `-wal` until a
/// checkpoint, so copying only the main file can silently produce a stale or
/// torn export. The function therefore forces a TRUNCATE checkpoint first —
/// which drains every committed frame into the main file — and only then
/// copies. This is a manual, user-initiated debug aid (the plan wires
/// scheduled/encrypted export to a later phase), so it copies bytes as-is and
/// leaves sanitisation to whoever shares the file.
///
/// [sourcePath] is passed in rather than discovered here so the caller is
/// always exporting exactly the file its own database provider opened — the
/// two can never drift apart.
Future<String> exportLocalDatabase(
  Database db, {
  required String sourcePath,
}) async {
  // Drain the WAL so the single copied file is self-contained.
  await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  final source = File(sourcePath);
  if (!source.existsSync()) {
    throw StateError('local database not found at $sourcePath');
  }
  final dir = await getApplicationDocumentsDirectory();
  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-');
  final target = File('${dir.path}/firefly_export_$stamp.db');
  await source.copy(target.path);
  return target.path;
}
