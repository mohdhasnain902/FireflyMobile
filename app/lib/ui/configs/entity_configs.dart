// ---------------------------------------------------------------------------
// The 14 entity configs — every field and choice grounded in Firefly 6.7.9.
//
// Grounding sources (read from the running container, 2026-10-16):
//   • App/Api/V1/Requests/Models/<Entity>/StoreRequest.php — validation rules
//   • config/firefly.php — subTitlesByIdentifier, accountRoles
// No enum or required-flag below is invented; fields the server API does not
// know (e.g. bill_direction — zero matches in API V1) are deliberately left
// out of the forms.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/recurrence_repetition.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/models/field_spec.dart';
import 'package:firefly_mobile/ui/theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Server-grounded vocabularies (see header for sources).
// ---------------------------------------------------------------------------

/// Account types — config/firefly.php subTitlesByIdentifier keys (liabilities
/// is a duplicate of liability and is left out).
const List<String> kAccountTypes = [
  'asset',
  'expense',
  'revenue',
  'cash',
  'liability',
];

/// Account roles — config/firefly.php `accountRoles`.
/// Server rule: `required_if:type,asset` (Account StoreRequest:115).
const List<String> kAccountRoles = [
  'defaultAsset',
  'sharedAsset',
  'savingAsset',
  'ccAsset',
  'cashWalletAsset',
];

/// Repeat frequencies — Bill StoreRequest:88
/// `in:weekly,monthly,quarterly,half-year,yearly`.
const List<String> kRepeatFreqs = [
  'weekly',
  'monthly',
  'quarterly',
  'half-year',
  'yearly',
];

/// Recurrence transaction directions — Recurrence StoreRequest `type`
/// (`required|in:withdrawal,transfer,deposit`).
const List<String> kRecurrenceTypes = [
  'withdrawal',
  'transfer',
  'deposit',
];

/// Repetition step types — Recurrence StoreRequest `repetitions.*.type`
/// (`required|in:daily,weekly,ndom,monthly,yearly`).
const List<String> kRepetitionTypes = [
  'daily',
  'weekly',
  'ndom',
  'monthly',
  'yearly',
];

/// Transaction types — Transaction StoreRequest:100.
const List<String> kTransactionTypes = [
  'withdrawal',
  'deposit',
  'transfer',
  'opening-balance',
  'reconciliation',
];

/// Rule triggers — Rule StoreRequest:87.
const List<String> kRuleTriggers = [
  'store-journal',
  'update-journal',
  'manual-activation',
];

/// Auto-budget types — Budget StoreRequest:84.
const List<String> kAutoBudgetTypes = ['none', 'reset', 'rollover', 'adjusted'];

// ---------------------------------------------------------------------------
// Reference dropdown providers (local rows only — never invents options).
// ---------------------------------------------------------------------------

/// Accounts as dropdown options, deleted rows excluded.
final accountRefOptionsProvider = FutureProvider<List<RefOption>>((ref) async {
  final rows = await ref.watch(accountListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.id, label: row.name))
      .toList();
});

/// Categories as dropdown options.
final categoryRefOptionsProvider = FutureProvider<List<RefOption>>((ref) async {
  final rows = await ref.watch(categoryListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.id, label: row.name))
      .toList();
});

/// Budgets as dropdown options.
final budgetRefOptionsProvider = FutureProvider<List<RefOption>>((ref) async {
  final rows = await ref.watch(budgetListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.id, label: row.name))
      .toList();
});

/// Bills as dropdown options.
final billRefOptionsProvider = FutureProvider<List<RefOption>>((ref) async {
  final rows = await ref.watch(billListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.id, label: row.name))
      .toList();
});

/// Rule groups as dropdown options.
final ruleGroupRefOptionsProvider = FutureProvider<List<RefOption>>((
  ref,
) async {
  final rows = await ref.watch(ruleGroupListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.id, label: row.title))
      .toList();
});

/// Currencies as dropdown options keyed by ISO code (Firefly wires
/// `currency_code`, not a row id — Currency StoreRequest
/// exists:transaction_currencies,code).
final currencyRefOptionsProvider = FutureProvider<List<RefOption>>((ref) async {
  final rows = await ref.watch(currencyListProvider.future);
  return rows
      .where((row) => row.deletedAt == null)
      .map((row) => RefOption(id: row.code, label: row.code))
      .toList();
});

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

/// Accounts — list, create, edit, delete.
final accountsConfig = EntityConfig<Account>(
  title: 'Accounts',
  singular: 'account',
  icon: Icons.account_balance_outlined,
  listProvider: accountListProvider,
  repoOf: (ref) => ref.watch(accountRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'type',
      label: 'Type',
      kind: FieldKind.choice,
      required: true,
      choices: kAccountTypes,
    ),
    FieldSpec(
      key: 'accountRole',
      label: 'Role',
      kind: FieldKind.choice,
      choices: kAccountRoles,
      hint: 'Required by the server for asset accounts',
      // Server: required_if:type,asset (Account StoreRequest:115).
      requiredWhen: (values) => values['type'] == 'asset',
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(key: 'iban', label: 'IBAN', kind: FieldKind.text),
    const FieldSpec(key: 'bic', label: 'BIC', kind: FieldKind.text),
    const FieldSpec(
      key: 'accountNumber',
      label: 'Account number',
      kind: FieldKind.text,
    ),
    const FieldSpec(
      key: 'openingBalance',
      label: 'Opening balance',
      kind: FieldKind.decimal,
    ),
    const FieldSpec(
      key: 'openingBalanceDate',
      label: 'Opening balance date',
      kind: FieldKind.date,
    ),
    const FieldSpec(
      key: 'virtualBalance',
      label: 'Virtual balance',
      kind: FieldKind.decimal,
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(
      key: 'includeNetWorth',
      label: 'Include in net worth',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(
      key: 'orderIndex',
      label: 'Order',
      kind: FieldKind.integer,
      hint: 'Lower sorts first',
    ),
  ],
  rowTitle: (row) => row.name,
  rowSubtitle: (row) {
    final parts = <String>[row.type];
    if (row.currencyCode != null) parts.add(row.currencyCode!);
    if (row.iban != null) parts.add(row.iban!);
    return parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'name': row.name,
    'type': row.type,
    'accountRole': row.accountRole,
    'currencyCode': row.currencyCode,
    'iban': row.iban,
    'bic': row.bic,
    'accountNumber': row.accountNumber,
    'openingBalance': row.openingBalance,
    'openingBalanceDate': row.openingBalanceDate,
    'virtualBalance': row.virtualBalance,
    'notes': row.notes,
    'active': row.active,
    'includeNetWorth': row.includeNetWorth,
    'orderIndex': row.orderIndex,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Account(
        id: id,
        name: reqString(values, 'name'),
        type: reqString(values, 'type'),
        accountRole: optString(values, 'accountRole'),
        currencyCode: optString(values, 'currencyCode'),
        iban: optString(values, 'iban'),
        bic: optString(values, 'bic'),
        accountNumber: optString(values, 'accountNumber'),
        openingBalance: optString(values, 'openingBalance'),
        openingBalanceDate: _openingBalanceDate(values, updatedAt),
        virtualBalance: optString(values, 'virtualBalance'),
        notes: optString(values, 'notes'),
        active: boolValue(values, 'active', fallback: true),
        includeNetWorth: boolValue(values, 'includeNetWorth', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        name: reqString(values, 'name'),
        type: reqString(values, 'type'),
        accountRole: optString(values, 'accountRole'),
        currencyCode: optString(values, 'currencyCode'),
        iban: optString(values, 'iban'),
        bic: optString(values, 'bic'),
        accountNumber: optString(values, 'accountNumber'),
        openingBalance: optString(values, 'openingBalance'),
        openingBalanceDate: _openingBalanceDate(values, updatedAt),
        virtualBalance: optString(values, 'virtualBalance'),
        notes: optString(values, 'notes'),
        active: boolValue(values, 'active', fallback: true),
        includeNetWorth: boolValue(values, 'includeNetWorth', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

/// Opening balance date for a create/edit, defaulting to the write's own day.
///
/// Firefly rejects `opening_balance` without `opening_balance_date` ("The
/// opening balance date field is required when opening balance is present"),
/// and the form's date picker starts empty — so an account created with an
/// opening balance but no date could never be pushed: the create op failed on
/// every attempt and, because a failed op stops the batch, nothing behind it
/// synced either. Firefly's own account form pre-fills the creation day; this
/// does the same instead of letting the user reach an unsendable state.
DateTime? _openingBalanceDate(
  Map<String, Object?> values,
  DateTime updatedAt,
) {
  final chosen = optDate(values, 'openingBalanceDate');
  if (chosen != null) return chosen;
  final balance = optString(values, 'openingBalance');
  if (balance == null) return null;
  final parsed = double.tryParse(balance.replaceAll(',', ''));
  if (parsed == null || parsed == 0) return null;
  final local = updatedAt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

// ---------------------------------------------------------------------------
// Attachments
// ---------------------------------------------------------------------------

/// Attachments — local rows; file upload lands with P4.
final attachmentsConfig = EntityConfig<Attachment>(
  title: 'Attachments',
  singular: 'attachment',
  icon: Icons.attach_file_outlined,
  listProvider: attachmentListProvider,
  repoOf: (ref) => ref.watch(attachmentRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'filename',
      label: 'Filename',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(
      key: 'mimeType',
      label: 'MIME type',
      kind: FieldKind.text,
      hint: 'e.g. image/jpeg',
    ),
    const FieldSpec(
      key: 'downloadUrl',
      label: 'Download URL',
      kind: FieldKind.text,
    ),
    const FieldSpec(
      key: 'localPath',
      label: 'Local path',
      kind: FieldKind.text,
      hint: 'Set after an upload (P4)',
    ),
    const FieldSpec(
      key: 'size',
      label: 'Size (bytes)',
      kind: FieldKind.integer,
    ),
    const FieldSpec(key: 'md5', label: 'MD5', kind: FieldKind.text),
  ],
  rowTitle: (row) => row.filename,
  rowSubtitle: (row) {
    final parts = <String>[
      if (row.mimeType != null) row.mimeType!,
      if (row.size != null) '${row.size} B',
      if (row.localPath != null) 'local',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'filename': row.filename,
    'notes': row.notes,
    'mimeType': row.mimeType,
    'downloadUrl': row.downloadUrl,
    'localPath': row.localPath,
    'size': row.size,
    'md5': row.md5,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Attachment(
        id: id,
        filename: reqString(values, 'filename'),
        notes: optString(values, 'notes'),
        mimeType: optString(values, 'mimeType'),
        downloadUrl: optString(values, 'downloadUrl'),
        localPath: optString(values, 'localPath'),
        size: optInt(values, 'size'),
        md5: optString(values, 'md5'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        filename: reqString(values, 'filename'),
        notes: optString(values, 'notes'),
        mimeType: optString(values, 'mimeType'),
        downloadUrl: optString(values, 'downloadUrl'),
        localPath: optString(values, 'localPath'),
        size: optInt(values, 'size'),
        md5: optString(values, 'md5'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Bills
// ---------------------------------------------------------------------------

/// Bills — recurring commitments.
///
/// `billDirection` is intentionally absent: zero matches for `bill_direction`
/// anywhere under App/Api/V1 (verified 2026-10-16), so the field stays null
/// and is never sent on the wire.
final billsConfig = EntityConfig<Bill>(
  title: 'Bills',
  singular: 'bill',
  icon: Icons.receipt_long_outlined,
  listProvider: billListProvider,
  repoOf: (ref) => ref.watch(billRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'amount',
      label: 'Amount',
      kind: FieldKind.decimal,
      required: true,
      positive: true,
      hint: 'Sent as both amount_min and amount_max',
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(
      key: 'date',
      label: 'Next due date',
      kind: FieldKind.date,
      required: true,
      hint: 'The website counts down from this date and requires it',
    ),
    const FieldSpec(
      key: 'repeatFreq',
      label: 'Frequency',
      kind: FieldKind.choice,
      required: true,
      choices: kRepeatFreqs,
      defaultValue: 'monthly',
    ),
    const FieldSpec(
      key: 'skip',
      label: 'Skip every n periods',
      kind: FieldKind.integer,
    ),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
  ],
  rowTitle: (row) => row.name,
  rowSubtitle: (row) {
    final parts = <String>[
      row.amount,
      if (row.currencyCode != null) row.currencyCode!,
      row.repeatFreq,
      if (!row.active) 'inactive',
    ];
    return parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'name': row.name,
    'amount': row.amount,
    'currencyCode': row.currencyCode,
    'date': row.date,
    'repeatFreq': row.repeatFreq,
    'skip': row.skip,
    'active': row.active,
    'notes': row.notes,
  },
  createWith: (values, {required id, required updatedAt, required seq}) => Bill(
    id: id,
    name: reqString(values, 'name'),
    amount: reqString(values, 'amount'),
    currencyCode: optString(values, 'currencyCode'),
    date: optDate(values, 'date'),
    repeatFreq: optString(values, 'repeatFreq') ?? 'monthly',
    skip: optInt(values, 'skip') ?? 0,
    active: boolValue(values, 'active', fallback: true),
    notes: optString(values, 'notes'),
    updatedAt: updatedAt,
    seq: seq,
  ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        name: reqString(values, 'name'),
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        date: optDate(values, 'date'),
        repeatFreq: optString(values, 'repeatFreq') ?? 'monthly',
        skip: optInt(values, 'skip') ?? 0,
        active: boolValue(values, 'active', fallback: true),
        notes: optString(values, 'notes'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

/// Budgets — spending envelopes.
final budgetsConfig = EntityConfig<Budget>(
  title: 'Budgets',
  singular: 'budget',
  icon: Icons.savings_outlined,
  listProvider: budgetListProvider,
  repoOf: (ref) => ref.watch(budgetRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(
      key: 'autoBudgetType',
      label: 'Auto budget',
      kind: FieldKind.choice,
      choices: kAutoBudgetTypes,
      hint: 'Server gates amount/period on a non-none type',
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(key: 'orderIndex', label: 'Order', kind: FieldKind.integer),
  ],
  rowTitle: (row) => row.name,
  rowSubtitle: (row) {
    final parts = <String>[
      if (row.autoBudgetType != null) row.autoBudgetType!,
      if (row.currencyCode != null) row.currencyCode!,
      if (!row.active) 'inactive',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'name': row.name,
    'notes': row.notes,
    'autoBudgetType': row.autoBudgetType,
    'currencyCode': row.currencyCode,
    'active': row.active,
    'orderIndex': row.orderIndex,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Budget(
        id: id,
        name: reqString(values, 'name'),
        notes: optString(values, 'notes'),
        autoBudgetType: optString(values, 'autoBudgetType'),
        currencyCode: optString(values, 'currencyCode'),
        active: boolValue(values, 'active', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        name: reqString(values, 'name'),
        notes: optString(values, 'notes'),
        autoBudgetType: optString(values, 'autoBudgetType'),
        currencyCode: optString(values, 'currencyCode'),
        active: boolValue(values, 'active', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Budget limits
// ---------------------------------------------------------------------------

/// Budget limits — per-period amount caps for one budget.
final budgetLimitsConfig = EntityConfig<BudgetLimit>(
  title: 'Budget limits',
  singular: 'budget limit',
  icon: Icons.timeline_outlined,
  listProvider: budgetLimitListProvider,
  repoOf: (ref) => ref.watch(budgetLimitRepositoryProvider.future),
  fields: [
    FieldSpec(
      key: 'budgetId',
      label: 'Budget',
      kind: FieldKind.reference,
      required: true,
      refOptions: budgetRefOptionsProvider,
    ),
    const FieldSpec(
      key: 'start',
      label: 'Start',
      kind: FieldKind.date,
      required: true,
    ),
    FieldSpec(
      key: 'end',
      label: 'End',
      kind: FieldKind.date,
      required: true,
      // Server: start `before:end`, end `after:start`
      // (BudgetLimit StoreRequest:74-75).
      isValid: (value, all) {
        final start = all['start'];
        if (value is DateTime && start is DateTime && !value.isAfter(start)) {
          return 'End must be after start';
        }
        return null;
      },
    ),
    const FieldSpec(
      key: 'amount',
      label: 'Amount',
      kind: FieldKind.decimal,
      required: true,
      positive: true,
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
  ],
  rowTitle: (row) => row.amount,
  rowSubtitle: (row) {
    final start = row.start.toUtc().toIso8601String().substring(0, 10);
    final end = row.end.toUtc().toIso8601String().substring(0, 10);
    final parts = <String>[
      '$start → $end',
      if (row.currencyCode != null) row.currencyCode!,
    ];
    return parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'budgetId': row.budgetId,
    'start': row.start,
    'end': row.end,
    'amount': row.amount,
    'currencyCode': row.currencyCode,
    'notes': row.notes,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      BudgetLimit(
        id: id,
        budgetId: reqString(values, 'budgetId'),
        start: optDate(values, 'start')!,
        end: optDate(values, 'end')!,
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        notes: optString(values, 'notes'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        budgetId: reqString(values, 'budgetId'),
        start: optDate(values, 'start')!,
        end: optDate(values, 'end')!,
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        notes: optString(values, 'notes'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// Categories — free-form spending labels.
final categoriesConfig = EntityConfig<Category>(
  title: 'Categories',
  singular: 'category',
  icon: Icons.category_outlined,
  listProvider: categoryListProvider,
  repoOf: (ref) => ref.watch(categoryRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
      hint: 'Server max length 100',
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
  ],
  rowTitle: (row) => row.name,
  rowSubtitle: (row) => row.notes ?? '—',
  toValues: (row) => <String, Object?>{'name': row.name, 'notes': row.notes},
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Category(
        id: id,
        name: reqString(values, 'name'),
        notes: optString(values, 'notes'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        name: reqString(values, 'name'),
        notes: optString(values, 'notes'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Currencies — pulled from the server, and writable so a custom currency
// (BTC or any token the user invents) can be added the way Firefly's own
// Currencies page adds one.
// ---------------------------------------------------------------------------

/// Currencies — pull + create/edit/delete (`/currencies` CRUD).
final currenciesConfig = EntityConfig<Currency>(
  title: 'Currencies',
  singular: 'currency',
  icon: Icons.currency_exchange_outlined,
  listProvider: currencyListProvider,
  repoOf: (ref) => ref.watch(currencyRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'code',
      label: 'Code',
      kind: FieldKind.text,
      required: true,
      hint: 'Short ISO-style code, e.g. BTC',
    ),
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
      hint: 'e.g. Bitcoin',
    ),
    const FieldSpec(key: 'symbol', label: 'Symbol', kind: FieldKind.text),
    const FieldSpec(
      key: 'decimalPlaces',
      label: 'Decimal places',
      kind: FieldKind.integer,
    ),
    const FieldSpec(
      key: 'enabled',
      label: 'Enabled',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(
      key: 'isDefault',
      label: 'Default currency',
      kind: FieldKind.boolean,
      hint: 'The book primary currency; only one may be default',
    ),
    const FieldSpec(
      key: 'rate',
      label: 'Rate',
      kind: FieldKind.text,
      hint: '1 unit of this currency in the default currency',
    ),
  ],
  rowTitle: (row) => '${row.code} — ${row.name}',
  rowSubtitle: (row) {
    final parts = <String>[
      if (row.symbol != null) row.symbol!,
      if (row.rate != null) 'rate ${row.rate}',
      if (row.isDefault) 'default',
      if (!row.enabled) 'disabled',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'code': row.code,
    'name': row.name,
    'symbol': row.symbol,
    'decimalPlaces': row.decimalPlaces.toString(),
    'enabled': row.enabled,
    'isDefault': row.isDefault,
    'rate': row.rate,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Currency(
        id: id,
        code: reqString(values, 'code'),
        name: reqString(values, 'name'),
        symbol: optString(values, 'symbol'),
        decimalPlaces: optInt(values, 'decimalPlaces') ?? 2,
        enabled: boolValue(values, 'enabled', fallback: true),
        isDefault: boolValue(values, 'isDefault'),
        rate: optString(values, 'rate'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        code: reqString(values, 'code'),
        name: reqString(values, 'name'),
        symbol: optString(values, 'symbol'),
        decimalPlaces: optInt(values, 'decimalPlaces') ?? current.decimalPlaces,
        enabled: boolValue(values, 'enabled', fallback: current.enabled),
        isDefault: boolValue(values, 'isDefault', fallback: current.isDefault),
        rate: optString(values, 'rate'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Piggy banks
// ---------------------------------------------------------------------------

/// Piggy banks — savings goals on one account.
final piggyBanksConfig = EntityConfig<PiggyBank>(
  title: 'Piggy banks',
  singular: 'piggy bank',
  icon: Icons.account_balance_wallet_outlined,
  listProvider: piggyBankListProvider,
  repoOf: (ref) => ref.watch(piggyBankRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'name',
      label: 'Name',
      kind: FieldKind.text,
      required: true,
    ),
    FieldSpec(
      key: 'accountId',
      label: 'Account',
      kind: FieldKind.reference,
      refOptions: accountRefOptionsProvider,
      hint: 'Server requires one account row',
    ),
    const FieldSpec(
      key: 'targetAmount',
      label: 'Target amount',
      kind: FieldKind.decimal,
      positive: true,
    ),
    const FieldSpec(
      key: 'currentAmount',
      label: 'Current amount',
      kind: FieldKind.decimal,
    ),
    const FieldSpec(
      key: 'startDate',
      label: 'Start date',
      kind: FieldKind.date,
    ),
    const FieldSpec(
      key: 'targetDate',
      label: 'Target date',
      kind: FieldKind.date,
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(key: 'orderIndex', label: 'Order', kind: FieldKind.integer),
  ],
  rowTitle: (row) => row.name,
  rowSubtitle: (row) {
    final parts = <String>[
      if (row.currentAmount != null) row.currentAmount!,
      if (row.targetAmount != null) '/ ${row.targetAmount}',
      if (row.currencyCode != null) row.currencyCode!,
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  },
  toValues: (row) => <String, Object?>{
    'name': row.name,
    'accountId': row.accountId,
    'targetAmount': row.targetAmount,
    'currentAmount': row.currentAmount,
    'startDate': row.startDate,
    'targetDate': row.targetDate,
    'currencyCode': row.currencyCode,
    'notes': row.notes,
    'orderIndex': row.orderIndex,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      PiggyBank(
        id: id,
        name: reqString(values, 'name'),
        accountId: optString(values, 'accountId'),
        targetAmount: optString(values, 'targetAmount'),
        currentAmount: optString(values, 'currentAmount'),
        startDate: optDate(values, 'startDate'),
        targetDate: optDate(values, 'targetDate'),
        currencyCode: optString(values, 'currencyCode'),
        notes: optString(values, 'notes'),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        name: reqString(values, 'name'),
        accountId: optString(values, 'accountId'),
        targetAmount: optString(values, 'targetAmount'),
        currentAmount: optString(values, 'currentAmount'),
        startDate: optDate(values, 'startDate'),
        targetDate: optDate(values, 'targetDate'),
        currencyCode: optString(values, 'currencyCode'),
        notes: optString(values, 'notes'),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Recurrences
// ---------------------------------------------------------------------------

/// Recurrences — recurring transaction definitions.
///
/// Every field below is grounded in the Recurrence StoreRequest validation
/// rules: `type` (`in:withdrawal,transfer,deposit`) and `first_date` are
/// required on create, `nr_of_repetitions` is `min:1|max:31`, and the schedule
/// is the 1:N `repetitions[]` child array rather than a flat frequency. The
/// form validates the JSON editor's shape client-side so an unpushable
/// definition is rejected before it is queued for sync.
final recurrencesConfig = EntityConfig<Recurrence>(
  title: 'Recurrences',
  singular: 'recurrence',
  icon: Icons.event_repeat_outlined,
  listProvider: recurrenceListProvider,
  repoOf: (ref) => ref.watch(recurrenceRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'title',
      label: 'Title',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'type',
      label: 'Type',
      kind: FieldKind.choice,
      required: true,
      choices: kRecurrenceTypes,
      hint: 'Transaction direction this recurrence generates',
      defaultValue: 'withdrawal',
    ),
    const FieldSpec(
      key: 'description',
      label: 'Description',
      kind: FieldKind.multiline,
    ),
    const FieldSpec(
      key: 'firstDate',
      label: 'First date',
      kind: FieldKind.date,
      required: true,
    ),
    // Not const: `requiredWhen`/`isValid` are closures, which are never
    // constant-evaluable.
    FieldSpec(
      key: 'repeatUntil',
      label: 'Repeat until',
      kind: FieldKind.date,
      // Server update XOR: the schedule is capped by exactly one of this date
      // or a repetition count. This date is only required when no count is set.
      requiredWhen: (all) => optInt(all, 'nrOfRepetitions') == null,
      isValid: (value, all) {
        if (value is DateTime && optInt(all, 'nrOfRepetitions') != null) {
          return 'Leave empty when a repetition count is set';
        }
        return null;
      },
    ),
    // Not const: `isValid` below is a closure.
    FieldSpec(
      key: 'nrOfRepetitions',
      label: 'Number of repetitions',
      kind: FieldKind.integer,
      hint: '1–31; leave empty for endless (then set repeat until)',
      // Server: `nullable|numeric|min:1|max:31`.
      isValid: (value, all) {
        final text = value is String ? value.trim() : '';
        if (text.isEmpty) return null;
        final n = int.tryParse(text);
        if (n == null || n < 1 || n > 31) {
          return 'Must be a whole number from 1 to 31';
        }
        if (all['repeatUntil'] is DateTime) {
          return 'Leave empty when a repeat-until date is set';
        }
        return null;
      },
    ),
    // Not const: `isValid` below is a closure.
    FieldSpec(
      key: 'repetitions',
      label: 'Schedule (repetitions JSON)',
      kind: FieldKind.json,
      required: true,
      hint:
          'Non-empty JSON array of frequency rules, e.g. '
          '[{"type":"monthly","moment":"17","skip":0,"weekend":1}]',
      isValid: (value, all) {
        final text = value is String ? value.trim() : '';
        if (text.isEmpty) return null;
        final Object? decoded;
        // FieldKind.json already proved the text decodes; this try only keeps
        // the type honest for the checks below.
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          return null;
        }
        if (decoded is! List || decoded.isEmpty) {
          return 'Repetitions must be a non-empty JSON array';
        }
        for (var i = 0; i < decoded.length; i++) {
          final element = decoded[i];
          if (element is! Map<String, dynamic>) {
            return 'Repetitions[$i] must be a JSON object';
          }
          final type = element['type'];
          if (type is! String || !kRepetitionTypes.contains(type)) {
            return 'Repetitions[$i].type must be one of '
                '${kRepetitionTypes.join(', ')}';
          }
          if (!element.containsKey('moment')) {
            return 'Repetitions[$i] is missing "moment"';
          }
        }
        return null;
      },
    ),
    const FieldSpec(
      key: 'transactionsJson',
      label: 'Template (JSON)',
      kind: FieldKind.json,
      hint: 'Server-side transactions[] template; edited as JSON for now',
    ),
    const FieldSpec(
      key: 'applyRules',
      label: 'Apply rules on creation',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
  ],
  rowTitle: (row) => row.title,
  rowSubtitle: (row) {
    final schedule = row.repetitions.isEmpty
        ? 'no schedule'
        : row.repetitions.map((r) => r.repetitionType).join(' + ');
    final parts = <String>[
      if (row.type != null && row.type!.isNotEmpty) row.type!,
      schedule,
      if (!row.active) 'inactive',
    ];
    return parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'title': row.title,
    'type': row.type,
    'description': row.description,
    'firstDate': row.firstDate,
    'repeatUntil': row.repeatUntil,
    'nrOfRepetitions': row.nrOfRepetitions?.toString(),
    'repetitions': jsonEncode(
      row.repetitions.map((r) => r.toJsonWire()).toList(),
    ),
    'transactionsJson': row.transactionsJson,
    'applyRules': row.applyRules,
    'active': row.active,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Recurrence(
        id: id,
        title: reqString(values, 'title'),
        type: reqString(values, 'type'),
        description: optString(values, 'description'),
        firstDate: optDate(values, 'firstDate'),
        repeatUntil: optDate(values, 'repeatUntil'),
        nrOfRepetitions: optInt(values, 'nrOfRepetitions'),
        repetitions: _repetitionsFromEditor(
          optString(values, 'repetitions'),
          id,
        ),
        transactionsJson: optString(values, 'transactionsJson'),
        applyRules: boolValue(values, 'applyRules', fallback: true),
        active: boolValue(values, 'active', fallback: true),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        title: reqString(values, 'title'),
        type: reqString(values, 'type'),
        description: optString(values, 'description'),
        firstDate: optDate(values, 'firstDate'),
        repeatUntil: optDate(values, 'repeatUntil'),
        nrOfRepetitions: optInt(values, 'nrOfRepetitions'),
        repetitions: _repetitionsFromEditor(
          optString(values, 'repetitions'),
          current.id,
        ),
        transactionsJson: optString(values, 'transactionsJson'),
        applyRules: boolValue(values, 'applyRules', fallback: true),
        active: boolValue(values, 'active', fallback: true),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

/// Parses the repetitions JSON editor's text into child entities owned by
/// [recurrenceId].
///
/// The field's `isValid` has already proven the text decodes to a non-empty
/// array of well-formed objects, so this only converts — reusing the entity's
/// own wire parser (`RecurrenceRepetition.fromJson`) so the defaults for `skip`
/// and `weekend` stay in one place. Anything unparseable degrades to an empty
/// list rather than throwing, so a config bug cannot crash the form.
List<RecurrenceRepetition> _repetitionsFromEditor(
  String? text,
  String recurrenceId,
) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return const <RecurrenceRepetition>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return const <RecurrenceRepetition>[];
  }
  if (decoded is! List) return const <RecurrenceRepetition>[];
  final parsed = <RecurrenceRepetition>[];
  for (var ord = 0; ord < decoded.length; ord++) {
    final element = decoded[ord];
    if (element is! Map<String, dynamic>) continue;
    parsed.add(
      RecurrenceRepetition.fromJson(
        element,
        recurrenceId: recurrenceId,
        ord: ord,
      ),
    );
  }
  return parsed;
}

// ---------------------------------------------------------------------------
// Rule groups
// ---------------------------------------------------------------------------

/// Rule groups — ordered containers for rules.
final ruleGroupsConfig = EntityConfig<RuleGroup>(
  title: 'Rule groups',
  singular: 'rule group',
  icon: Icons.folder_copy_outlined,
  listProvider: ruleGroupListProvider,
  repoOf: (ref) => ref.watch(ruleGroupRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'title',
      label: 'Title',
      kind: FieldKind.text,
      required: true,
      hint: 'Server max length 100',
    ),
    const FieldSpec(
      key: 'description',
      label: 'Description',
      kind: FieldKind.multiline,
    ),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(key: 'orderIndex', label: 'Order', kind: FieldKind.integer),
  ],
  rowTitle: (row) => row.title,
  rowSubtitle: (row) => row.active ? 'active' : 'inactive',
  toValues: (row) => <String, Object?>{
    'title': row.title,
    'description': row.description,
    'active': row.active,
    'orderIndex': row.orderIndex,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      RuleGroup(
        id: id,
        title: reqString(values, 'title'),
        description: optString(values, 'description'),
        active: boolValue(values, 'active', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        title: reqString(values, 'title'),
        description: optString(values, 'description'),
        active: boolValue(values, 'active', fallback: true),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/// Rules — auto-categorisation engine entries.
///
/// `scope` has no `in:` rule anywhere in the API (grep verified), so it stays
/// a free-text optional field. Triggers/actions are JSON because the server
/// wire shape is a nested array; the P3 replay unwraps them.
final rulesConfig = EntityConfig<Rule>(
  title: 'Rules',
  singular: 'rule',
  icon: Icons.rule_outlined,
  listProvider: ruleListProvider,
  repoOf: (ref) => ref.watch(ruleRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'title',
      label: 'Title',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'description',
      label: 'Description',
      kind: FieldKind.multiline,
    ),
    FieldSpec(
      key: 'ruleGroupId',
      label: 'Rule group',
      kind: FieldKind.reference,
      refOptions: ruleGroupRefOptionsProvider,
    ),
    const FieldSpec(
      key: 'trigger',
      label: 'When',
      kind: FieldKind.choice,
      required: true,
      choices: kRuleTriggers,
    ),
    const FieldSpec(
      key: 'triggersJson',
      label: 'Conditions (JSON)',
      kind: FieldKind.json,
      hint: 'Server triggers[] array; edited as JSON for now',
    ),
    const FieldSpec(
      key: 'actionsJson',
      label: 'Actions (JSON)',
      kind: FieldKind.json,
      hint: 'Server actions[] array; edited as JSON for now',
    ),
    const FieldSpec(key: 'scope', label: 'Scope', kind: FieldKind.text),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
    const FieldSpec(
      key: 'strict',
      label: 'Strict (all triggers must match)',
      kind: FieldKind.boolean,
    ),
    const FieldSpec(
      key: 'stop',
      label: 'Stop processing after match',
      kind: FieldKind.boolean,
    ),
    const FieldSpec(key: 'orderIndex', label: 'Order', kind: FieldKind.integer),
  ],
  rowTitle: (row) => row.title,
  rowSubtitle: (row) {
    final parts = <String>[
      if (row.trigger != null) row.trigger!,
      if (!row.active) 'inactive',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'title': row.title,
    'description': row.description,
    'ruleGroupId': row.ruleGroupId,
    'trigger': row.trigger,
    'triggersJson': row.triggersJson,
    'actionsJson': row.actionsJson,
    'scope': row.scope,
    'active': row.active,
    'strict': row.strict,
    'stop': row.stop,
    'orderIndex': row.orderIndex,
  },
  createWith: (values, {required id, required updatedAt, required seq}) => Rule(
    id: id,
    title: reqString(values, 'title'),
    description: optString(values, 'description'),
    ruleGroupId: optString(values, 'ruleGroupId'),
    trigger: optString(values, 'trigger'),
    triggersJson: optString(values, 'triggersJson'),
    actionsJson: optString(values, 'actionsJson'),
    scope: optString(values, 'scope'),
    active: boolValue(values, 'active', fallback: true),
    strict: boolValue(values, 'strict'),
    stop: boolValue(values, 'stop'),
    orderIndex: optInt(values, 'orderIndex'),
    updatedAt: updatedAt,
    seq: seq,
  ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        title: reqString(values, 'title'),
        description: optString(values, 'description'),
        ruleGroupId: optString(values, 'ruleGroupId'),
        trigger: optString(values, 'trigger'),
        triggersJson: optString(values, 'triggersJson'),
        actionsJson: optString(values, 'actionsJson'),
        scope: optString(values, 'scope'),
        active: boolValue(values, 'active', fallback: true),
        strict: boolValue(values, 'strict'),
        stop: boolValue(values, 'stop'),
        orderIndex: optInt(values, 'orderIndex'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------

/// Subscriptions — commitments paid on a schedule.
///
/// `method` has no `in:` grounding anywhere under the API requests (grep
/// verified), so it stays free text. `periods` is kept as the entity's string
/// field via integer-form entry.
final subscriptionsConfig = EntityConfig<Subscription>(
  title: 'Subscriptions',
  singular: 'subscription',
  icon: Icons.autorenew_outlined,
  listProvider: subscriptionListProvider,
  repoOf: (ref) => ref.watch(subscriptionRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'title',
      label: 'Title',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'amount',
      label: 'Amount',
      kind: FieldKind.decimal,
      required: true,
      positive: true,
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    const FieldSpec(
      key: 'repeatFreq',
      label: 'Frequency',
      kind: FieldKind.choice,
      required: true,
      choices: kRepeatFreqs,
      defaultValue: 'monthly',
    ),
    const FieldSpec(key: 'nextDate', label: 'Next date', kind: FieldKind.date),
    const FieldSpec(key: 'endDate', label: 'End date', kind: FieldKind.date),
    const FieldSpec(
      key: 'periods',
      label: 'Periods',
      kind: FieldKind.text,
      hint: 'Server accepts a period count',
    ),
    const FieldSpec(
      key: 'method',
      label: 'Method',
      kind: FieldKind.text,
      hint: 'No server enum; free text',
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(
      key: 'active',
      label: 'Active',
      kind: FieldKind.boolean,
      defaultValue: true,
    ),
  ],
  rowTitle: (row) => row.title,
  rowSubtitle: (row) {
    final parts = <String>[
      row.amount,
      if (row.currencyCode != null) row.currencyCode!,
      row.repeatFreq,
      if (!row.active) 'inactive',
    ];
    return parts.join(' · ');
  },
  toValues: (row) => <String, Object?>{
    'title': row.title,
    'amount': row.amount,
    'currencyCode': row.currencyCode,
    'repeatFreq': row.repeatFreq,
    'nextDate': row.nextDate,
    'endDate': row.endDate,
    'periods': row.periods,
    'method': row.method,
    'notes': row.notes,
    'active': row.active,
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Subscription(
        id: id,
        title: reqString(values, 'title'),
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        repeatFreq: optString(values, 'repeatFreq') ?? 'monthly',
        nextDate: optDate(values, 'nextDate'),
        endDate: optDate(values, 'endDate'),
        periods: optString(values, 'periods'),
        method: optString(values, 'method'),
        notes: optString(values, 'notes'),
        active: boolValue(values, 'active', fallback: true),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        title: reqString(values, 'title'),
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        repeatFreq: optString(values, 'repeatFreq') ?? 'monthly',
        nextDate: optDate(values, 'nextDate'),
        endDate: optDate(values, 'endDate'),
        periods: optString(values, 'periods'),
        method: optString(values, 'method'),
        notes: optString(values, 'notes'),
        active: boolValue(values, 'active', fallback: true),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

/// Tags — free labels attachable to journals.
final tagsConfig = EntityConfig<Tag>(
  title: 'Tags',
  singular: 'tag',
  icon: Icons.label_outline,
  listProvider: tagListProvider,
  repoOf: (ref) => ref.watch(tagRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'tag',
      label: 'Tag',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(key: 'date', label: 'Date', kind: FieldKind.date),
  ],
  rowTitle: (row) => row.tag,
  rowSubtitle: (row) => row.date == null
      ? '—'
      : row.date!.toUtc().toIso8601String().substring(0, 10),
  toValues: (row) => <String, Object?>{'tag': row.tag, 'date': row.date},
  createWith: (values, {required id, required updatedAt, required seq}) => Tag(
    id: id,
    tag: reqString(values, 'tag'),
    date: optDate(values, 'date'),
    updatedAt: updatedAt,
    seq: seq,
  ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        tag: reqString(values, 'tag'),
        date: optDate(values, 'date'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

/// Transactions — the core journal entries.
///
/// Name fields (`sourceName`/`destName`/`categoryName`/…) mirror the server's
/// "create account by name" affordance (Transaction StoreRequest:119-137);
/// the id references point at existing local rows. Either style is valid —
/// the P3 replay sends whichever the user filled.
// ---------------------------------------------------------------------------
// Transactions list visuals — docs/2nd UI 2.png (cards, pills, day headers).
// Reached only through the optional EntityConfig hooks; every other entity
// renders the untouched generic ListTile list.
// ---------------------------------------------------------------------------

/// Type label used when a row has no resolvable category.
String _txTypeLabel(String type) => switch (type) {
  'withdrawal' => 'Withdrawal',
  'deposit' => 'Deposit',
  'transfer' => 'Transfer',
  'opening-balance' => 'Opening balance',
  'reconciliation' => 'Reconciliation',
  _ => type,
};

/// `1234567.890000000000` → `1,234,567.89` (leading sign preserved, then
/// stripped by the caller so the colored sign can be added separately).
///
/// Firefly returns amounts with up to 12 fraction digits
/// (`2023.440000000000`); rendering those raw made the trailing column wider
/// than the whole `ListTile`, which tripped Flutter's "trailing widget
/// consumes the entire tile width" assertion on every row and pushed the
/// row's ⋮ menu off-screen (REGRESSION: delete/edit unreachable). Amounts are
/// therefore rounded to the two digits money is actually shown in, and
/// trailing zeros are dropped so whole amounts stay scannable.
String _txGroupAmount(String raw) {
  var s = raw.trim();
  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final dot = s.indexOf('.');
  var intPart = dot < 0 ? s : s.substring(0, dot);
  var frac = dot < 0 ? '' : s.substring(dot + 1);
  if (intPart.isEmpty) intPart = '0';
  if (frac.length > 2) {
    final keep = frac.substring(0, 2).padRight(2, '0');
    final roundUp = frac.codeUnitAt(2).compareTo('5'.codeUnitAt(0)) >= 0;
    var digits = int.parse(keep) + (roundUp ? 1 : 0);
    if (digits >= 100) {
      digits -= 100;
      // Carry into the integer part without losing precision on huge values.
      intPart = (BigInt.parse(intPart) + BigInt.one).toString();
    }
    frac = digits.toString().padLeft(2, '0');
  }
  frac = frac.replaceAll(RegExp(r'0+$'), '');
  // Bare fractions (`.5`) never reach here as money, but keep it valid.
  frac = frac.length == 1 ? '${frac}0' : frac;
  final grouped = intPart.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '-' : ''}$grouped${frac.isEmpty ? '' : '.$frac'}';
}

/// Currency symbol from the synced currencies; `''` when unresolved so the
/// amount stays clean before the currencies table is filled.
String _txSymbol(WidgetRef ref, String? code) {
  if (code == null || code.isEmpty) return '';
  final currencies = ref.watch(currencyListProvider).value ?? const [];
  for (final c in currencies) {
    if (c.code == code) return c.symbol ?? '';
  }
  return '';
}

/// Account display name: explicit name wins, else id → synced account name.
String? _txAccountName(WidgetRef ref, String? id, String? name) {
  if (name != null && name.isNotEmpty) return name;
  if (id == null || id.isEmpty) return null;
  final accounts = ref.watch(accountListProvider).value ?? const [];
  for (final a in accounts) {
    if (a.id == id) return a.name;
  }
  return null;
}

/// First tag from the `tags_json` column; `null` when absent/not JSON.
String? _txFirstTag(Transaction row) {
  final raw = row.tagsJson;
  if (raw == null || raw.isEmpty) return null;
  try {
    final list = jsonDecode(raw);
    if (list is List && list.isNotEmpty) return list.first.toString();
  } on FormatException catch (_) {
    // Non-JSON column content: not a tag, show nothing.
  }
  return null;
}

/// Leading 40px circle: −/+ glyph in type color at 14% fill (mockup).
Widget _txLeading(BuildContext context, WidgetRef ref, Transaction row) {
  final (icon, fg) = switch (row.type) {
    'withdrawal' => (Icons.remove, FireflyPalette.negative),
    'deposit' => (Icons.add, FireflyPalette.primary),
    _ => (Icons.swap_horiz, FireflyPalette.chartAmber),
  };
  return Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fg.withValues(alpha: 0.14),
    ),
    child: Icon(icon, size: 20, color: fg),
  );
}

/// `Category-or-type · account(s)` plus the first tag as a mini olive chip.
Widget _txSubtitle(BuildContext context, WidgetRef ref, Transaction row) {
  // Category name wins over the raw type word (mockup shows 'Groceries').
  var category = row.categoryName;
  if ((category == null || category.isEmpty) && row.categoryId != null) {
    final cats = ref.watch(categoryListProvider).value ?? const [];
    for (final c in cats) {
      if (c.id == row.categoryId) {
        category = c.name;
        break;
      }
    }
  }
  final head = (category != null && category.isNotEmpty)
      ? category
      : _txTypeLabel(row.type);

  final src = _txAccountName(ref, row.sourceAccountId, row.sourceName);
  final dst = _txAccountName(ref, row.destAccountId, row.destName);
  final accounts = switch (row.type) {
    'withdrawal' => src,
    'deposit' => dst,
    'transfer' => (src != null && dst != null) ? '$src → $dst' : (src ?? dst),
    _ => src ?? dst,
  };

  final children = <Widget>[
    Text(
      [head, ?accounts].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  ];
  final tag = _txFirstTag(row);
  if (tag != null) {
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: FireflyPalette.oliveFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              fontSize: 11,
              color: FireflyPalette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

/// Trailing column: colored signed amount over local `HH:mm` time.
Widget _txTrailing(BuildContext context, WidgetRef ref, Transaction row) {
  var body = _txGroupAmount(row.amount);
  // A raw negative already carries the sign; otherwise type decides it.
  final (sign, color) = body.startsWith('-')
      ? ('-', FireflyPalette.negative)
      : switch (row.type) {
          'withdrawal' => ('-', FireflyPalette.negative),
          'deposit' => ('+', FireflyPalette.primary),
          _ => ('', FireflyPalette.textPrimary),
        };
  if (body.startsWith('-')) body = body.substring(1);
  final symbol = _txSymbol(ref, row.currencyCode);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      // Hard cap: a long amount must never take the room the title needs
      // (ListTile asserts when the trailing widget fills the whole tile).
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 96),
        child: Text(
          '$sign$symbol$body',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        DateFormat('HH:mm', 'en_US').format(row.date.toLocal()),
        style: const TextStyle(
          color: FireflyPalette.textMuted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

/// Section header: `Today` / `Yesterday` / `Oct 19` (local calendar day).
String _txGroupLabel(Transaction row) {
  final d = row.date.toLocal();
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('MMM d', 'en_US').format(d);
}

/// Newest first within the day-grouped list.
int _txGroupCompare(Transaction a, Transaction b) => b.date.compareTo(a.date);

/// Day-grouped transactions list with quick-filter pills and card rows
/// (docs/2nd UI 2.png): All/Withdrawal/Deposits/Transfers filters,
/// Today/Yesterday sections, signed colored amounts, tag chip.
final transactionsConfig = EntityConfig<Transaction>(
  title: 'Transactions',
  singular: 'transaction',
  icon: Icons.swap_vert_outlined,
  listProvider: transactionListProvider,
  repoOf: (ref) => ref.watch(transactionRepositoryProvider.future),
  fields: [
    const FieldSpec(
      key: 'type',
      label: 'Type',
      kind: FieldKind.choice,
      required: true,
      choices: kTransactionTypes,
    ),
    const FieldSpec(
      key: 'description',
      label: 'Description',
      kind: FieldKind.text,
      required: true,
    ),
    const FieldSpec(
      key: 'date',
      label: 'Date',
      kind: FieldKind.date,
      required: true,
    ),
    const FieldSpec(
      key: 'amount',
      label: 'Amount',
      kind: FieldKind.decimal,
      required: true,
      positive: true,
    ),
    FieldSpec(
      key: 'currencyCode',
      label: 'Currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Pick a currency from your book',
    ),
    FieldSpec(
      key: 'sourceAccountId',
      label: 'Source account',
      kind: FieldKind.reference,
      refOptions: accountRefOptionsProvider,
    ),
    const FieldSpec(
      key: 'sourceName',
      label: 'Source name',
      kind: FieldKind.text,
      hint: 'Alternative to picking a row — creates the account on sync',
    ),
    FieldSpec(
      key: 'destAccountId',
      label: 'Destination account',
      kind: FieldKind.reference,
      refOptions: accountRefOptionsProvider,
    ),
    const FieldSpec(
      key: 'destName',
      label: 'Destination name',
      kind: FieldKind.text,
      hint: 'Alternative to picking a row — creates the account on sync',
    ),
    FieldSpec(
      key: 'categoryId',
      label: 'Category',
      kind: FieldKind.reference,
      refOptions: categoryRefOptionsProvider,
    ),
    FieldSpec(
      key: 'budgetId',
      label: 'Budget',
      kind: FieldKind.reference,
      refOptions: budgetRefOptionsProvider,
    ),
    FieldSpec(
      key: 'billId',
      label: 'Bill',
      kind: FieldKind.reference,
      refOptions: billRefOptionsProvider,
    ),
    const FieldSpec(
      key: 'tagsJson',
      label: 'Tags',
      kind: FieldKind.tags,
      hint: 'Press enter to add a tag',
    ),
    const FieldSpec(key: 'notes', label: 'Notes', kind: FieldKind.multiline),
    const FieldSpec(
      key: 'foreignAmount',
      label: 'Foreign amount',
      kind: FieldKind.decimal,
    ),
    FieldSpec(
      key: 'foreignCurrencyCode',
      label: 'Foreign currency',
      kind: FieldKind.reference,
      refOptions: currencyRefOptionsProvider,
      hint: 'Only for a transfer with a different foreign amount',
    ),
    const FieldSpec(
      key: 'reconciled',
      label: 'Reconciled',
      kind: FieldKind.boolean,
    ),
    // Firefly's "Options" block — the same eight per-journal fields its
    // transaction form carries. They are stored and pushed so a phone edit
    // cannot silently clear them on the website.
    const FieldSpec(
      key: 'interestDate',
      label: 'Interest date',
      kind: FieldKind.date,
    ),
    const FieldSpec(
      key: 'bookDate',
      label: 'Book date',
      kind: FieldKind.date,
    ),
    const FieldSpec(
      key: 'processDate',
      label: 'Process date',
      kind: FieldKind.date,
    ),
    const FieldSpec(key: 'dueDate', label: 'Due date', kind: FieldKind.date),
    const FieldSpec(
      key: 'paymentDate',
      label: 'Payment date',
      kind: FieldKind.date,
    ),
    const FieldSpec(
      key: 'externalUrl',
      label: 'External URL',
      kind: FieldKind.text,
    ),
    const FieldSpec(
      key: 'internalReference',
      label: 'Internal reference',
      kind: FieldKind.text,
    ),
    const FieldSpec(
      key: 'order',
      label: 'Order',
      kind: FieldKind.integer,
      hint: 'Manual ordering in Firefly lists',
    ),
  ],
  rowTitle: (row) => row.description,
  rowSubtitle: (row) {
    final parts = <String>[
      row.type,
      row.amount,
      if (row.currencyCode != null) row.currencyCode!,
      row.date.toUtc().toIso8601String().substring(0, 10),
    ];
    return parts.join(' · ');
  },
  // --- 2nd-UI list hooks (docs/2nd UI 2.png) — transactions only ---
  searchHint: 'Search transactions',
  fabLabel: 'New transaction',
  cardRows: true,
  filters: [
    ListFilter(label: 'Withdrawals', test: (row) => row.type == 'withdrawal'),
    ListFilter(label: 'Deposits', test: (row) => row.type == 'deposit'),
    ListFilter(label: 'Transfers', test: (row) => row.type == 'transfer'),
  ],
  groupLabel: _txGroupLabel,
  groupCompare: _txGroupCompare,
  rowLeading: _txLeading,
  rowSubtitleWidget: _txSubtitle,
  rowTrailingWidget: _txTrailing,
  toValues: (row) => <String, Object?>{
    'type': row.type,
    'description': row.description,
    'date': row.date,
    'amount': row.amount,
    'currencyCode': row.currencyCode,
    'sourceAccountId': row.sourceAccountId,
    'sourceName': row.sourceName,
    'destAccountId': row.destAccountId,
    'destName': row.destName,
    'categoryId': row.categoryId,
    'budgetId': row.budgetId,
    'billId': row.billId,
    'tagsJson': row.tagsJson,
    'notes': row.notes,
    'foreignAmount': row.foreignAmount,
    'foreignCurrencyCode': row.foreignCurrencyCode,
    'reconciled': row.reconciled,
    'interestDate': row.interestDate,
    'bookDate': row.bookDate,
    'processDate': row.processDate,
    'dueDate': row.dueDate,
    'paymentDate': row.paymentDate,
    'externalUrl': row.externalUrl,
    'internalReference': row.internalReference,
    'order': row.order?.toString(),
  },
  createWith: (values, {required id, required updatedAt, required seq}) =>
      Transaction(
        id: id,
        type: reqString(values, 'type'),
        description: reqString(values, 'description'),
        date: optDate(values, 'date')!,
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        sourceAccountId: optString(values, 'sourceAccountId'),
        sourceName: optString(values, 'sourceName'),
        destAccountId: optString(values, 'destAccountId'),
        destName: optString(values, 'destName'),
        categoryId: optString(values, 'categoryId'),
        budgetId: optString(values, 'budgetId'),
        billId: optString(values, 'billId'),
        tagsJson: optString(values, 'tagsJson'),
        notes: optString(values, 'notes'),
        foreignAmount: optString(values, 'foreignAmount'),
        foreignCurrencyCode: optString(values, 'foreignCurrencyCode'),
        reconciled: boolValue(values, 'reconciled'),
        interestDate: optDate(values, 'interestDate'),
        bookDate: optDate(values, 'bookDate'),
        processDate: optDate(values, 'processDate'),
        dueDate: optDate(values, 'dueDate'),
        paymentDate: optDate(values, 'paymentDate'),
        externalUrl: optString(values, 'externalUrl'),
        internalReference: optString(values, 'internalReference'),
        order: optInt(values, 'order'),
        updatedAt: updatedAt,
        seq: seq,
      ),
  editWith: (current, values, {required updatedAt, required seq}) =>
      current.copyWith(
        type: reqString(values, 'type'),
        description: reqString(values, 'description'),
        date: optDate(values, 'date')!,
        amount: reqString(values, 'amount'),
        currencyCode: optString(values, 'currencyCode'),
        sourceAccountId: optString(values, 'sourceAccountId'),
        sourceName: optString(values, 'sourceName'),
        destAccountId: optString(values, 'destAccountId'),
        destName: optString(values, 'destName'),
        categoryId: optString(values, 'categoryId'),
        budgetId: optString(values, 'budgetId'),
        billId: optString(values, 'billId'),
        tagsJson: optString(values, 'tagsJson'),
        notes: optString(values, 'notes'),
        foreignAmount: optString(values, 'foreignAmount'),
        foreignCurrencyCode: optString(values, 'foreignCurrencyCode'),
        reconciled: boolValue(values, 'reconciled'),
        interestDate: optDate(values, 'interestDate'),
        bookDate: optDate(values, 'bookDate'),
        processDate: optDate(values, 'processDate'),
        dueDate: optDate(values, 'dueDate'),
        paymentDate: optDate(values, 'paymentDate'),
        externalUrl: optString(values, 'externalUrl'),
        internalReference: optString(values, 'internalReference'),
        order: optInt(values, 'order'),
        updatedAt: updatedAt,
        seq: seq,
      ),
);

/// All 14 configs in drawer order — the single source the shell iterates.
///
/// Covariance makes this legal without `dynamic`: each concrete
/// `EntityConfig<Account>` etc. is a subtype of `EntityConfig<SyncBookkeeping>`
/// because [Account] implements [SyncBookkeeping]. The generic list screen
/// re-wraps each entry with its own typed provider before rendering, so no
/// call site ever reads a row as the base type.
final List<EntityConfig<SyncBookkeeping>> allEntityConfigs =
    <EntityConfig<SyncBookkeeping>>[
      accountsConfig,
      attachmentsConfig,
      billsConfig,
      budgetsConfig,
      budgetLimitsConfig,
      categoriesConfig,
      currenciesConfig,
      piggyBanksConfig,
      recurrencesConfig,
      ruleGroupsConfig,
      rulesConfig,
      subscriptionsConfig,
      tagsConfig,
      transactionsConfig,
    ];
