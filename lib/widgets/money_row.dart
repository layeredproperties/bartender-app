import 'package:flutter/material.dart';

/// A label on the left, an amount on the right — the row used by every
/// summary card on the results and import screens.
///
/// Both screens previously carried a byte-identical private `_row`
/// helper alongside their own copy of the money formatter.
class MoneyRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const MoneyRow(this.label, this.value, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// A card that calls attention to a problem — a negative line item, a
/// duplicate import, a missing sales figure.
class WarningCard extends StatelessWidget {
  final String message;

  const WarningCard(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
