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

/// `recurrences` — stored and synced schedules; never executed on device.
class RecurrenceDao extends EntityDao<Recurrence> {
  /// Binds the DAO to an open connection or transaction.
  new(DatabaseExecutor executor)
    : super(
        db: executor,
        table: 'recurrences',
        decode: Recurrence.fromRow,
        encode: (e) => e.toRow(),
      );
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
