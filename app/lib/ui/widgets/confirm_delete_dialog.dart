import 'package:flutter/material.dart';

/// Confirmation dialog shown before a soft-delete (P2.2.4).
///
/// Pure UI: returns `true` only when the user taps the destructive button.
/// The actual `softDelete` call lives in the list screen, so this widget can
/// be unit-tested without any repository or database.
///
/// Returns `true` to confirm, `false`/null to cancel (dismiss, back, etc).
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required String singular,
  required String rowTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $singular?'),
      content: Text(
        '"$rowTitle" will be marked for deletion. The server copy is '
        'removed once the next sync runs.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
