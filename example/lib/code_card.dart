import 'package:material_ui/material_ui.dart';

import 'jobs.dart';

/// Shared barcode/QR data field + type chips.
class CodeCard extends StatelessWidget {
  const CodeCard({
    super.key,
    required this.controller,
    required this.type,
    required this.onType,
    this.extra,
  });

  final TextEditingController controller;
  final CodeType type;
  final ValueChanged<CodeType> onType;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Barcode / QR data',
            helperText: type == CodeType.ean13 ? '12 or 13 digits' : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final t in CodeType.values)
            ChoiceChip(
              label: Text(t.label),
              selected: t == type,
              onSelected: (_) => onType(t),
            ),
        ]),
        if (extra != null) extra!,
      ],
    );
  }
}

/// Runs a print job and reports back; supplied by the page.
typedef RunJob = Future<void> Function(
    String label, Future<String?> Function() job);
