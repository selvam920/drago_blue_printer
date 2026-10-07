import 'dart:typed_data';

import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:material_ui/material_ui.dart';

import 'code_card.dart';
import 'jobs.dart';

class LabelTab extends StatefulWidget {
  const LabelTab({super.key, required this.run, required this.enabled});
  final RunJob run;
  final bool enabled;

  @override
  State<LabelTab> createState() => _LabelTabState();
}

class _LabelTabState extends State<LabelTab> {
  final _bt = DragoBluePrinter.instance;
  final _w = TextEditingController(text: '50');
  final _h = TextEditingController(text: '30');
  final _gap = TextEditingController(text: '2');
  final _data = TextEditingController(text: '123456789012');
  LabelLanguage _lang = LabelLanguage.tspl;
  CodeType _type = CodeType.code128;

  @override
  void dispose() {
    for (final c in [_w, _h, _gap, _data]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  LabelSize? _size() {
    final w = double.tryParse(_w.text.trim());
    final h = double.tryParse(_h.text.trim());
    final g = double.tryParse(_gap.text.trim()) ?? 0;
    if (w == null || h == null || w <= 0 || h <= 0 || g < 0) return null;
    return LabelSize(w, h, g);
  }

  void _send(String label, List<int> Function(LabelSize s) build) {
    widget.run(label, () async {
      final s = _size();
      if (s == null) throw 'Invalid label size';
      await _bt.writeBytes(Uint8List.fromList(build(s)));
      return null;
    });
  }

  Widget _num(TextEditingController c, String label) => Expanded(
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: label,
              suffixText: 'mm',
              border: const OutlineInputBorder()),
          onChanged: (_) => _set(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final tspl = _lang == LabelLanguage.tspl;
    final cur = _size();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Language', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<LabelLanguage>(
          segments: const [
            ButtonSegment(value: LabelLanguage.tspl, label: Text('TSPL')),
            ButtonSegment(value: LabelLanguage.escpos, label: Text('ESC/POS')),
          ],
          selected: {_lang},
          onSelectionChanged: (s) => _set(() => _lang = s.first),
        ),
        const SizedBox(height: 16),
        Text('Size (203 dpi, 8 dots/mm)',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final (w, h) in labelPresets)
            ChoiceChip(
              label: Text('${w.toInt()}x${h.toInt()}'),
              selected: cur?.width == w && cur?.height == h,
              onSelected: (_) => _set(() {
                _w.text = '${w.toInt()}';
                _h.text = '${h.toInt()}';
              }),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _num(_w, 'Width'),
          const SizedBox(width: 8),
          _num(_h, 'Height'),
          const SizedBox(width: 8),
          _num(_gap, 'Gap'),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: on
                ? () => _send('Sample label',
                    (s) => sampleLabel(_lang, s, _data.text.trim()))
                : null,
            icon: const Icon(Icons.label_rounded),
            label: const Text('Sample label'),
          ),
          if (tspl) ...[
            FilledButton.tonalIcon(
              onPressed:
                  on ? () => _send('Calibrate', (_) => tsplCalibrate()) : null,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Calibrate'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  on ? () => _send('Self test', (_) => tsplSelfTest()) : null,
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Self test'),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CodeCard(
              controller: _data,
              type: _type,
              onType: (t) => _set(() => _type = t),
              extra: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: on
                        ? () => _send(
                            '${_type.label} label',
                            (s) =>
                                codeLabel(_lang, s, _type, _data.text.trim()))
                        : null,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Barcode / QR label'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
