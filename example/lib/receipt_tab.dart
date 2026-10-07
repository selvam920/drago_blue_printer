import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:material_ui/material_ui.dart';

import 'code_card.dart';
import 'jobs.dart';
import 'testprint.dart';

class ReceiptTab extends StatefulWidget {
  const ReceiptTab({super.key, required this.run, required this.enabled});
  final RunJob run;
  final bool enabled;

  @override
  State<ReceiptTab> createState() => _ReceiptTabState();
}

class _ReceiptTabState extends State<ReceiptTab> {
  final _bt = DragoBluePrinter.instance;
  final _samples = TestPrint();
  final _data = TextEditingController(text: 'https://example.com');
  PaperWidth _paper = PaperWidth.mm58;
  CodeType _type = CodeType.qr;
  bool _asImage = false;

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Paper width', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        SegmentedButton<PaperWidth>(
          segments: const [
            ButtonSegment(
                value: PaperWidth.mm58, label: Text('58mm (384 / 32)')),
            ButtonSegment(
                value: PaperWidth.mm80, label: Text('80mm (576 / 48)')),
          ],
          selected: {_paper},
          onSelectionChanged: (s) => _set(() => _paper = s.first),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: on
                ? () => widget.run('Test page', () async {
                      await _bt.writeBytes(receiptTestPage(_paper));
                      return null;
                    })
                : null,
            icon: const Icon(Icons.straighten_rounded),
            label: const Text('Test page'),
          ),
          FilledButton.tonalIcon(
            onPressed: on
                ? () => widget.run('Batch sample', () async {
                      await _samples.sampleBatch();
                      return null;
                    })
                : null,
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('Batch sample'),
          ),
          FilledButton.tonalIcon(
            onPressed: on
                ? () => widget.run('Legacy sample', () async {
                      await _samples.sampleLegacy();
                      return null;
                    })
                : null,
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Legacy sample'),
          ),
        ]),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: CodeCard(
              controller: _data,
              type: _type,
              onType: (t) => _set(() => _type = t),
              extra: Column(children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Print as image'),
                  subtitle: const Text('Raster GS v 0 instead of native codes'),
                  value: _asImage,
                  onChanged: (v) => _set(() => _asImage = v),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: on
                        ? () => widget.run('${_type.label} receipt', () async {
                              await _bt.writeBytes(receiptCode(
                                  _paper, _type, _data.text.trim(),
                                  asImage: _asImage));
                              return null;
                            })
                        : null,
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Print barcode / QR'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
