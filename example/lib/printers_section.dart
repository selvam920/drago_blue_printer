import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:material_ui/material_ui.dart';

/// Paired + nearby printers. Stateless: the page owns connection state.
class PrintersSection extends StatelessWidget {
  const PrintersSection({
    super.key,
    required this.paired,
    required this.nearby,
    required this.selected,
    required this.connected,
    required this.connecting,
    required this.loading,
    required this.scanning,
    required this.onRefresh,
    required this.onToggleScan,
    required this.onConnect,
    required this.onDisconnect,
    required this.onPair,
  });

  final List<BluetoothDevice> paired;
  final List<BluetoothDevice> nearby;
  final BluetoothDevice? selected;
  final bool connected;
  final bool connecting;
  final bool loading;
  final bool scanning;
  final VoidCallback onRefresh;
  final VoidCallback onToggleScan;
  final ValueChanged<BluetoothDevice> onConnect;
  final VoidCallback onDisconnect;
  final ValueChanged<BluetoothDevice> onPair;

  bool _isSel(BluetoothDevice d) => selected?.address == d.address;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.print_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Printers', style: tt.titleMedium)),
              IconButton(
                tooltip: 'Refresh paired',
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              TextButton.icon(
                onPressed: onToggleScan,
                icon: scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching_rounded),
                label: Text(scanning ? 'Stop' : 'Scan'),
              ),
            ]),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(
                    connected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: connected ? cs.primary : cs.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      connecting
                          ? 'Connecting to ${selected!.name ?? selected!.address}...'
                          : connected
                              ? 'Connected: ${selected!.name ?? selected!.address}'
                              : 'Not connected',
                      style: tt.bodyMedium,
                    ),
                  ),
                  if (connected)
                    OutlinedButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Disconnect'),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                ]),
              ),
            const Divider(),
            Text('Paired', style: tt.labelLarge),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (paired.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No paired printers. Scan and pair one.',
                    style: tt.bodyMedium?.copyWith(color: cs.outline)),
              ),
            if (!loading)
              for (final d in paired)
                _PairedTile(
                  device: d,
                  selected: _isSel(d),
                  connected: _isSel(d) && connected,
                  connecting: _isSel(d) && connecting,
                  onTap: connecting ? null : () => onConnect(d),
                ),
            if (scanning || nearby.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Nearby', style: tt.labelLarge),
              if (nearby.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Searching...',
                      style: tt.bodyMedium?.copyWith(color: cs.outline)),
                ),
              for (final d in nearby)
                ListTile(
                  leading: const Icon(Icons.bluetooth_rounded),
                  title: Text(d.name ?? 'Unknown'),
                  subtitle: Text(d.address ?? ''),
                  trailing: FilledButton.tonal(
                    onPressed: () => onPair(d),
                    child: const Text('Pair'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairedTile extends StatelessWidget {
  const _PairedTile({
    required this.device,
    required this.selected,
    required this.connected,
    required this.connecting,
    required this.onTap,
  });

  final BluetoothDevice device;
  final bool selected;
  final bool connected;
  final bool connecting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final battery = device.battery;
    final low = battery != null && battery <= 20;
    return ListTile(
      selected: selected,
      selectedTileColor: cs.primaryContainer.withAlpha(90),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(Icons.print_rounded,
          color: connected ? cs.primary : cs.onSurfaceVariant),
      title: Text(device.name ?? 'Unknown device'),
      subtitle: Text(device.address ?? ''),
      onTap: connected ? null : onTap,
      trailing: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (battery != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  low ? Icons.battery_alert_rounded : Icons.battery_std_rounded,
                  size: 18,
                  color: low ? cs.error : cs.onSurfaceVariant),
              Text('$battery%', style: TextStyle(color: low ? cs.error : null)),
            ]),
          if (connecting)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (connected)
            Chip(
              label: const Text('Connected'),
              visualDensity: VisualDensity.compact,
              backgroundColor: cs.primary,
              labelStyle: TextStyle(color: cs.onPrimary, fontSize: 11),
              side: BorderSide.none,
            ),
        ],
      ),
    );
  }
}
