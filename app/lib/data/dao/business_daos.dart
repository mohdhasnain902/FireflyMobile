/// One DAO per business entity (DESIGN §5.1).
///
/// Each subclass does nothing but bind its entity's `fromRow`/`toRow` pair to
/// its physical table; every behaviour lives in [EntityDao]. That is the
/// deliberate shape of this layer: the fourteen tables differ in columns, not
/// in semantics, so the only per-entity decision left is the mapping itself.
///
/// The table name doubles as the JSON:API `type` and as the `entity_type`
/// recorded in the op log — all three are identical for every entity (see each
/// entity's `toJsonApi`). Keeping them aligned is what lets the replay engine
/// build `POST /api/v1/{table}` from one string later.
///
/// [CurrencyDao] is intentionally read-only in practice: currencies are
/// pull-only (DESIGN §3.1), so nothing on the phone ever creates one and no
/// mutation path is wired to it.
library;

import 'package:firefly_mobile/data/dao/entity_dao.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

/// `accounts` — asset and liability accounts.
class AccountDao extends EntityDao<Account> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'accounts',
        decode: Account.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `attachments` — receipt files and their metadata.
class AttachmentDao extends EntityDao<Attachment> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'attachments',
        decode: Attachment.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `bills` — recurring expected payments.
class BillDao extends EntityDao<Bill> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'bills',
        decode: Bill.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `budgets` — envelope categories.
class BudgetDao extends EntityDao<Budget> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'budgets',
        decode: Budget.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `budget_limits` — a budget's per-period spending cap.
class BudgetLimitDao extends EntityDao<BudgetLimit> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'budget_limits',
        decode: BudgetLimit.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `categories` — transaction category tree.
class CategoryDao extends EntityDao<Category> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'categories',
        decode: Category.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `currencies` — exchange-rate lookup, pull-only.
class CurrencyDao extends EntityDao<Currency> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'currencies',
        decode: Currency.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `piggy_banks` — savings goals.
class PiggyBankDao extends EntityDao<PiggyBank> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'piggy_banks',
        decode: PiggyBank.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `recurrences` — recurring transaction definitions plus their 1:N
/// `recurrence_repetitions` frequency rows.
///
/// Firefly's frequency model is nested: the parent's `recurrences` row carries
/// no repetition columns, so every content write (insert/upsert/update)
/// rewrites the children wholesale from the entity's in-memory list, and every
/// read re-joins them before handing the entity back — otherwise
/// `Recurrence.repetitions` would stay empty after any load and `toJsonApi`
/// would silently push a recurrence without its schedule.
///
/// Child rewrites follow the server's own update semantics
/// (RecurrenceUpdateService): an empty in-memory list is treated as "leave
/// children untouched" (the server ignores `repetitions: []` on update), so a
/// half-loaded entity can never wipe a schedule. `patch`/`softDelete` stay
/// inherited — sync-bookkeeping writes must not touch schedule data. Because
/// the repository builds this DAO on the caller's executor, child rewrites
/// inside the sync engine's transaction are atomic with the parent row.
class RecurrenceDao extends EntityDao<Recurrence> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'recurrences',
        decode: Recurrence.fromRow,
        encode: (e) => e.toRow(),
      );

  /// Child table of schedule rows; always accessed through the same executor
  /// as the parent write/read so both stay atomic inside a transaction.
  static const String _childTable = 'recurrence_repetitions';

  @override
  Future<void> insert(Recurrence entity, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    await super.insert(entity, exec);
    await _rewriteRepetitions(entity, exec);
  }

  @override
  Future<void> upsert(Recurrence entity, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    await super.upsert(entity, exec);
    await _rewriteRepetitions(entity, exec);
  }

  @override
  Future<int> update(Recurrence entity, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final changed = await super.update(entity, exec);
    // Zero rows means the parent vanished; rewriting its schedule would be
    // writing an edit for a row the device no longer has.
    if (changed > 0) await _rewriteRepetitions(entity, exec);
    return changed;
  }

  @override
  Future<void> hardDelete(String id, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    await super.hardDelete(id, exec);
    await exec.delete(
      _childTable,
      where: 'recurrence_id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<Recurrence?> getById(String id, [DatabaseExecutor? executor]) async {
    final exec = executor ?? db;
    final entity = await super.getById(id, exec);
    if (entity == null) return null;
    return (await _attachRepetitions(<Recurrence>[entity], exec)).single;
  }

  @override
  Future<Recurrence?> getByFireflyId(
    String fireflyId, [
    DatabaseExecutor? executor,
  ]) async {
    final exec = executor ?? db;
    final entity = await super.getByFireflyId(fireflyId, exec);
    if (entity == null) return null;
    return (await _attachRepetitions(<Recurrence>[entity], exec)).single;
  }

  @override
  Future<List<Recurrence>> getAll({
    bool includeDeleted = false,
    String orderBy = 'updated_at DESC',
    int? limit,
    int? offset,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final entities = await super.getAll(
      includeDeleted: includeDeleted,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      executor: exec,
    );
    return await _attachRepetitions(entities, exec);
  }

  @override
  Future<List<Recurrence>> getPending({
    String orderBy = 'updated_at ASC',
    int? limit,
    int? offset,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? db;
    final entities = await super.getPending(
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      executor: exec,
    );
    return await _attachRepetitions(entities, exec);
  }

  /// Replaces [entity]'s children in [exec] with its in-memory repetitions.
  ///
  /// Deliberately a no-op for an empty list: the server ignores an empty
  /// `repetitions` array on update rather than dropping the schedule, and a
  /// half-loaded local entity must never be able to wipe real children.
  Future<void> _rewriteRepetitions(
    Recurrence entity,
    DatabaseExecutor exec,
  ) async {
    if (entity.repetitions.isEmpty) return;
    await exec.delete(
      _childTable,
      where: 'recurrence_id = ?',
      whereArgs: <Object?>[entity.id],
    );
    for (final row in entity.repetitionRows()) {
      await exec.insert(_childTable, row);
    }
  }

  /// Joins the child rows for [entities] in one query (no N+1) and attaches
  /// them via [Recurrence.loadRepetitions]. A recurrence with no children
  /// returns with an empty list — its schedule is simply empty.
  Future<List<Recurrence>> _attachRepetitions(
    List<Recurrence> entities,
    DatabaseExecutor exec,
  ) async {
    if (entities.isEmpty) return entities;
    final ids = entities.map((entity) => entity.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await exec.query(
      _childTable,
      where: 'recurrence_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'recurrence_id, ord',
    );
    if (rows.isEmpty) return entities;
    return entities
        .map((entity) => entity.loadRepetitions(rows))
        .toList();
  }
}

/// `rules` — trigger/action definitions, stored and never executed on device.
class RuleDao extends EntityDao<Rule> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'rules',
        decode: Rule.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `rule_groups` — ordered containers for rules.
class RuleGroupDao extends EntityDao<RuleGroup> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'rule_groups',
        decode: RuleGroup.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `subscriptions` — scheduled repeating transactions.
class SubscriptionDao extends EntityDao<Subscription> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'subscriptions',
        decode: Subscription.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `tags` — free-form labels.
class TagDao extends EntityDao<Tag> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'tags',
        decode: Tag.fromRow,
        encode: (e) => e.toRow(),
      );
}

/// `transactions` — journals, the app's primary record.
class TransactionDao extends EntityDao<Transaction> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'transactions',
        decode: Transaction.fromRow,
        encode: (e) => e.toRow(),
      );
}
