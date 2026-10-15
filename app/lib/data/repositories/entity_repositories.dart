/// One repository per business entity — the whole of this layer
/// (DESIGN §5.2, §6.3).
///
/// Thirteen extend the write base and inherit `create`, `update`, `softDelete`
/// and `hardDelete`, each of which allocates a `seq`, queues its op and writes
/// the row inside one transaction. A subclass here contributes only four facts:
/// its table name, its payload codec, its DAO and its entity type. All four are
/// deliberately the *same* string — `accounts`, `categories`, `piggy_banks`, …
/// — because that identity is what lets the replay engine turn a queued
/// `entity_type` into a Firefly path without consulting anything else.
///
/// That string must not be bent to match the wire path: three entities differ
/// (`piggy-banks`, `rule-groups`, budget limits nested under their budget), so
/// mapping it to a URL stays the replay engine's job. Keeping it identical to
/// the JSON:API `type` the payload already carries means the queue and the body
/// can never disagree about what is being sent.
///
/// [CurrencyRepository] is the exception and extends the read base only:
/// currencies are pull-only (DESIGN §3.1), so nothing on the phone ever writes
/// one, and a write method that would throw at runtime is worse than an
/// absent one.
///
/// Two payload caveats the replay engine must honour, both already visible in
/// the models: an attachment's bytes are absent from its payload (the upload
/// is a multipart POST re-attached from `local_path`), and an edit queued for
/// a row with no `fireflyId` is a `create`, as written up on the `update`
/// method.
library;

import 'dart:convert';

import 'package:firefly_mobile/data/dao/business_daos.dart';
import 'package:firefly_mobile/data/repositories/entity_reader.dart';
import 'package:firefly_mobile/data/repositories/sync_repository.dart';
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

/// `accounts` — asset and liability accounts.
class AccountRepository extends SyncRepository<Account> {
  /// Binds the accounts write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'accounts',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: AccountDao.new,
      );
}

/// `attachments` — receipt files and their metadata.
class AttachmentRepository extends SyncRepository<Attachment> {
  /// Binds the attachments write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'attachments',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: AttachmentDao.new,
      );
}

/// `bills` — recurring expected payments.
class BillRepository extends SyncRepository<Bill> {
  /// Binds the bills write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'bills',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: BillDao.new,
      );
}

/// `budgets` — the envelope a set of limits hangs off.
class BudgetRepository extends SyncRepository<Budget> {
  /// Binds the budgets write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'budgets',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: BudgetDao.new,
      );
}

/// `budget_limits` — one budget's per-period cap.
class BudgetLimitRepository extends SyncRepository<BudgetLimit> {
  /// Binds the budget-limits write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'budget_limits',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: BudgetLimitDao.new,
      );
}

/// `categories` — the one category tree Firefly exposes on this API.
class CategoryRepository extends SyncRepository<Category> {
  /// Binds the categories write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'categories',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: CategoryDao.new,
      );
}

/// Read path for `currencies` — pull-only, with no queue and no mutations.
///
/// Currencies are the one business table the phone never writes (DESIGN §3.1:
/// pull-only, `sync_status` always `synced`), so this repository deliberately
/// extends the read base rather than the write base. Pulling a currency down
/// from the server is a plain row write with no op attached — asking the server
/// to create data it already owns is not a mutation of ours to replay.
class CurrencyRepository extends EntityReader<Currency> {
  /// Binds the currency read path to [db].
  new({required super.db}) : super(daoOf: CurrencyDao.new);
}

/// `piggy_banks` — saving goals.
class PiggyBankRepository extends SyncRepository<PiggyBank> {
  /// Binds the piggy-banks write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'piggy_banks',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: PiggyBankDao.new,
      );
}

/// `recurrences` — schedules Firefly expands into transactions itself.
class RecurrenceRepository extends SyncRepository<Recurrence> {
  /// Binds the recurrences write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'recurrences',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: RecurrenceDao.new,
      );
}

/// `rules` — automated categorisation Firefly applies on the PC (DESIGN §4.6).
class RuleRepository extends SyncRepository<Rule> {
  /// Binds the rules write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'rules',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: RuleDao.new,
      );
}

/// `rule_groups` — ordered container for [Rule]s.
class RuleGroupRepository extends SyncRepository<RuleGroup> {
  /// Binds the rule-groups write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'rule_groups',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: RuleGroupDao.new,
      );
}

/// `subscriptions` — fixed-amount recurring charges.
class SubscriptionRepository extends SyncRepository<Subscription> {
  /// Binds the subscriptions write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'subscriptions',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: SubscriptionDao.new,
      );
}

/// `tags` — free-form labels applied to transactions.
class TagRepository extends SyncRepository<Tag> {
  /// Binds the tags write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'tags',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: TagDao.new,
      );
}

/// `transactions` — single or split journal entries.
///
/// Queued as `transactions`; whether a replay PUT targets the transaction or an
/// individual journal leg is a replay-engine concern (DESIGN §6.3), not a local
/// one — here the row is one journal set either way.
class TransactionRepository extends SyncRepository<Transaction> {
  /// Binds the transactions write path to [db].
  new({required super.db, required super.meta})
    : super(
        entityType: 'transactions',
        payloadOf: (entity) => jsonEncode(entity.toJsonApi()),
        daoOf: TransactionDao.new,
      );
}
