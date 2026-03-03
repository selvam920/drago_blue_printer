import 'dart:async';
import 'package:example/testprint.dart';
import 'package:flutter/material.dart';
import 'package:drago_blue_printer/drago_blue_printer.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drago Blue Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
      home: const BluetoothPrinterPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------
class BluetoothPrinterPage extends StatefulWidget {
  const BluetoothPrinterPage({super.key});

  @override
  State<BluetoothPrinterPage> createState() => _BluetoothPrinterPageState();
}

class _BluetoothPrinterPageState extends State<BluetoothPrinterPage>
    with SingleTickerProviderStateMixin {
  final _bluetooth = DragoBluePrinter.instance;
  final _testPrint = TestPrint();

  List<BluetoothDevice> _pairedDevices = [];
  final List<BluetoothDevice> _scannedDevices = [];
  BluetoothDevice? _selectedDevice;
  bool _connected = false;
  bool _isLoading = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  bool _isScanning = false;
  StreamSubscription<BluetoothDevice>? _scanSub;
  StreamSubscription<int?>? _stateSub;

  late final AnimationController _scanAnimCtrl;

  @override
  void initState() {
    super.initState();
    _scanAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _loadDevices();
    _listenState();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateSub?.cancel();
    _scanAnimCtrl.dispose();
    super.dispose();
  }

  // -- Bluetooth state listener ---------------------------------------------
  void _listenState() {
    _stateSub = _bluetooth.onStateChanged().listen((state) {
      if (!mounted) return;
      switch (state) {
        case DragoBluePrinter.CONNECTED:
          setState(() {
            _connected = true;
            _isConnecting = false;
          });
          _showSnack('Connected', icon: Icons.check_circle, isError: false);
          break;
        case DragoBluePrinter.DISCONNECTED:
        case DragoBluePrinter.DISCONNECT_REQUESTED:
          setState(() {
            _connected = false;
            _isConnecting = false;
          });
          break;
        case DragoBluePrinter.STATE_OFF:
        case DragoBluePrinter.STATE_TURNING_OFF:
          setState(() {
            _connected = false;
            _isConnecting = false;
          });
          _showSnack('Bluetooth turned off', icon: Icons.bluetooth_disabled);
          break;
        default:
          break;
      }
    });
  }

  // -- Load bonded devices --------------------------------------------------
  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      _pairedDevices = await _bluetooth.getBondedDevices();
    } catch (e) {
      debugPrint('getBondedDevices error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // -- Scan -----------------------------------------------------------------
  void _toggleScan() {
    _isScanning ? _stopScan() : _startScan();
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _scannedDevices.clear();
    });
    _scanAnimCtrl.repeat();
    _scanSub?.cancel();
    _scanSub = _bluetooth.scan().listen((device) {
      final isDuplicate =
          _pairedDevices.any((d) => d.address == device.address) ||
              _scannedDevices.any((d) => d.address == device.address);
      if (!isDuplicate && mounted) {
        setState(() => _scannedDevices.add(device));
      }
    });
    Future.delayed(const Duration(seconds: 20), _stopScan);
  }

  void _stopScan() {
    _scanSub?.cancel();
    if (mounted) {
      _scanAnimCtrl.stop();
      _scanAnimCtrl.reset();
      setState(() => _isScanning = false);
    }
  }

  // -- Connect / Disconnect -------------------------------------------------
  Future<void> _connect(BluetoothDevice device) async {
    if (_isConnecting) return;
    setState(() {
      _selectedDevice = device;
      _isConnecting = true;
    });
    try {
      final alreadyConnected = await _bluetooth.isConnected ?? false;
      if (!alreadyConnected) {
        await _bluetooth.connect(device);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        _showSnack('Connection failed: $e');
      }
    }
  }

  Future<void> _disconnect() async {
    try {
      await _bluetooth.disconnect();
    } catch (_) {}
    if (mounted) setState(() => _connected = false);
  }

  // -- Pair -----------------------------------------------------------------
  Future<void> _pairDevice(BluetoothDevice device) async {
    try {
      await _bluetooth.pairDevice(device);
      await Future.delayed(const Duration(seconds: 2));
      _loadDevices();
      _showSnack('Pairing requested', icon: Icons.link, isError: false);
    } catch (e) {
      _showSnack('Pairing failed: $e');
    }
  }

  // -- Print ----------------------------------------------------------------
  Future<void> _printReceipt() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await _testPrint.sampleBatch();
      if (mounted) {
        _showSnack('Print sent!', icon: Icons.print, isError: false);
      }
    } catch (e) {
      if (mounted) _showSnack('Print error: $e');
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  Future<void> _printLegacy() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      await _testPrint.sampleLegacy();
      if (mounted) {
        _showSnack('Print sent (legacy)!', icon: Icons.print, isError: false);
      }
    } catch (e) {
      if (mounted) _showSnack('Print error: $e');
    }
    if (mounted) setState(() => _isPrinting = false);
  }

  // -- Snackbar helper ------------------------------------------------------
  void _showSnack(String msg,
      {IconData icon = Icons.error_outline, bool isError = true}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: isError ? cs.errorContainer : cs.primaryContainer,
      content: Row(children: [
        Icon(icon,
            color: isError ? cs.onErrorContainer : cs.onPrimaryContainer,
            size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: TextStyle(
                  color: isError
                      ? cs.onErrorContainer
                      : cs.onPrimaryContainer)),
        ),
      ]),
      duration: const Duration(seconds: 3),
    ));
  }

  // =========================================================================
  // BUILD
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isConnected =
        _selectedDevice != null && _connected && !_isConnecting;

    return Scaffold(
      // ── App Bar ──────────────────────────────────────────────────────────
      appBar: AppBar(
        title: const Text('Drago Blue Printer'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh paired devices',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadDevices,
          ),
          const SizedBox(width: 4),
        ],
      ),

      // ── FAB ──────────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: _isScanning
            ? RotationTransition(
                turns: _scanAnimCtrl,
                child: const Icon(Icons.bluetooth_searching))
            : const Icon(Icons.search_rounded),
        label: Text(_isScanning ? 'Stop Scan' : 'Scan Nearby'),
      ),

      // ── Body ─────────────────────────────────────────────────────────────
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDevices,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  // ── Status banner ────────────────────────────────────────
                  _StatusBanner(
                    connected: isConnected,
                    deviceName: _selectedDevice?.name,
                  ),
                  const SizedBox(height: 16),

                  // ── Action buttons when connected ────────────────────────
                  if (isConnected) ...[
                    _SectionHeader(
                        icon: Icons.receipt_long_rounded, label: 'Actions'),
                    const SizedBox(height: 8),
                    _ActionBar(
                      isPrinting: _isPrinting,
                      onPrintBatch: _printReceipt,
                      onPrintLegacy: _printLegacy,
                      onDisconnect: _disconnect,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Paired devices ───────────────────────────────────────
                  _SectionHeader(
                      icon: Icons.devices_rounded, label: 'Paired Devices'),
                  const SizedBox(height: 8),
                  if (_pairedDevices.isEmpty)
                    _EmptyHint(
                        label: 'No paired printers found.',
                        icon: Icons.print_disabled_rounded),
                  ..._pairedDevices.map((d) => _DeviceTile(
                        device: d,
                        isSelected: _selectedDevice?.address == d.address,
                        isConnected:
                            _selectedDevice?.address == d.address && _connected,
                        isConnecting:
                            _selectedDevice?.address == d.address &&
                                _isConnecting,
                        onTap: () => _connect(d),
                      )),

                  // ── Scanned devices ──────────────────────────────────────
                  if (_isScanning || _scannedDevices.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(
                        icon: Icons.bluetooth_searching_rounded,
                        label: 'Nearby Devices',
                        trailing: _isScanning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : null),
                    const SizedBox(height: 8),
                    if (_scannedDevices.isEmpty && _isScanning)
                      _EmptyHint(
                          label: 'Searching…',
                          icon: Icons.radar_rounded),
                    ..._scannedDevices.map((d) => _ScannedDeviceTile(
                          device: d,
                          onPair: () => _pairDevice(d),
                        )),
                  ],
                ],
              ),
            ),
    );
  }
}

// ===========================================================================
// Extracted widgets
// ===========================================================================

/// Bluetooth connection status banner at the top.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.connected, this.deviceName});
  final bool connected;
  final String? deviceName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: connected
              ? [cs.primaryContainer, cs.primaryContainer.withAlpha(180)]
              : [cs.surfaceContainerHighest, cs.surfaceContainerHigh],
        ),
      ),
      child: Row(children: [
        Icon(
          connected
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_disabled_rounded,
          color: connected ? cs.primary : cs.outline,
          size: 28,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? 'Connected' : 'Not Connected',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: connected ? cs.primary : cs.onSurfaceVariant),
              ),
              if (connected && deviceName != null)
                Text(deviceName!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer)),
              if (!connected)
                Text('Select a device below to connect',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.outline)),
            ],
          ),
        ),
        if (connected)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.green.withAlpha(120),
                    blurRadius: 6,
                    spreadRadius: 2)
              ],
            ),
          ),
      ]),
    );
  }
}

/// Section header with icon.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 18, color: cs.primary),
      const SizedBox(width: 8),
      Text(label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600, color: cs.primary)),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ]);
  }
}

/// Empty-state hint row.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ]),
      ),
    );
  }
}

/// Tile for a paired device.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isSelected,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });
  final BluetoothDevice device;
  final bool isSelected;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        borderRadius: BorderRadius.circular(14),
        color: isConnected
            ? cs.primaryContainer.withAlpha(80)
            : cs.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isConnected ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isConnected
                      ? cs.primary.withAlpha(30)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.print_rounded,
                  color: isConnected ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name ?? 'Unknown Device',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(device.address ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.outline)),
                  ],
                ),
              ),
              if (isConnecting)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (isConnected)
                Chip(
                  label: const Text('Connected'),
                  labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimary),
                  backgroundColor: cs.primary,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              else
                Icon(Icons.chevron_right_rounded, color: cs.outline),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tile for a scanned (not-yet-paired) device.
class _ScannedDeviceTile extends StatelessWidget {
  const _ScannedDeviceTile({required this.device, required this.onPair});
  final BluetoothDevice device;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        borderRadius: BorderRadius.circular(14),
        color: cs.surfaceContainerLow,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPair,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.bluetooth_rounded,
                    color: cs.tertiary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name ?? 'Unknown',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(device.address ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.outline)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onPair,
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: const Text('Pair'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Row of action buttons shown when a printer is connected.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isPrinting,
    required this.onPrintBatch,
    required this.onPrintLegacy,
    required this.onDisconnect,
  });
  final bool isPrinting;
  final VoidCallback onPrintBatch;
  final VoidCallback onPrintLegacy;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Expanded(
        child: FilledButton.icon(
          onPressed: isPrinting ? null : onPrintBatch,
          icon: isPrinting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.bolt_rounded, size: 20),
          label: const Text('Batch Print'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: isPrinting ? null : onPrintLegacy,
          icon: const Icon(Icons.receipt_long_rounded, size: 20),
          label: const Text('Legacy Print'),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        onPressed: onDisconnect,
        icon: const Icon(Icons.link_off_rounded, size: 20),
        tooltip: 'Disconnect',
        style: IconButton.styleFrom(
          backgroundColor: cs.errorContainer,
          foregroundColor: cs.onErrorContainer,
        ),
      ),
    ]);
  }
}
