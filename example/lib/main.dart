import 'dart:async';

import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:material_ui/material_ui.dart';

import 'jobs.dart';
import 'label_tab.dart';
import 'printers_section.dart';
import 'receipt_tab.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1565C0);
    return MaterialApp(
      title: 'Drago Blue Printer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: seed),
      darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: seed,
          brightness: Brightness.dark),
      home: const PrinterHomePage(),
    );
  }
}

enum UseAs { receipt, label, both }

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key});

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  final _bt = DragoBluePrinter.instance;

  List<BluetoothDevice> _paired = [];
  final List<BluetoothDevice> _nearby = [];
  BluetoothDevice? _selected;
  bool _connected = false;
  bool _connecting = false;
  bool _loading = false;
  bool _scanning = false;
  StreamSubscription<BluetoothDevice>? _scanSub;
  StreamSubscription<int?>? _stateSub;
  Timer? _scanTimer;

  UseAs _useAs = UseAs.receipt;
  bool _busy = false;
  String? _result;
  bool _resultError = false;

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _stateSub = _bt.onStateChanged().listen(_onState);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _onState(int? state) {
    switch (state) {
      case DragoBluePrinter.CONNECTED:
        // Any BT link (e.g. a headset) fires this; only trust it while we
        // are actually connecting to the selected printer.
        if (!_connecting) break;
        _set(() {
          _connected = true;
          _connecting = false;
        });
        break;
      case DragoBluePrinter.DISCONNECTED:
      case DragoBluePrinter.DISCONNECT_REQUESTED:
      case DragoBluePrinter.STATE_OFF:
      case DragoBluePrinter.STATE_TURNING_OFF:
        _set(() {
          _connected = false;
          _connecting = false;
        });
        if (state == DragoBluePrinter.STATE_OFF) {
          _report('Bluetooth turned off', error: true);
        }
        break;
      default:
        break;
    }
  }

  void _report(String msg, {bool error = false}) => _set(() {
        _result = msg;
        _resultError = error;
      });

  Future<void> _loadDevices() async {
    _set(() => _loading = true);
    try {
      final list = await _bt.getBondedDevices();
      _set(() => _paired = list);
    } catch (e) {
      _report('Paired list failed: $e', error: true);
    }
    _set(() => _loading = false);
  }

  void _toggleScan() => _scanning ? _stopScan() : _startScan();

  void _startScan() {
    _set(() {
      _scanning = true;
      _nearby.clear();
    });
    _scanSub?.cancel();
    _scanSub = _bt.scan().listen((d) {
      final dup = _paired.any((p) => p.address == d.address) ||
          _nearby.any((p) => p.address == d.address);
      if (!dup) _set(() => _nearby.add(d));
    }, onError: (Object e) {
      _report('Scan failed: $e', error: true);
      _stopScan();
    });
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 20), _stopScan);
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _scanSub = null;
    _set(() => _scanning = false);
  }

  Future<void> _pair(BluetoothDevice d) async {
    try {
      await _bt.pairDevice(d);
      _report('Pairing requested for ${d.name ?? d.address}');
      await Future.delayed(const Duration(seconds: 2));
      await _loadDevices();
      _set(() => _nearby.removeWhere((n) => _paired.contains(n)));
    } catch (e) {
      _report('Pairing failed: $e', error: true);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_connecting) return;
    _set(() {
      _selected = device;
      _connecting = true;
    });
    // Settle from connect()'s own result: the state stream may not fire
    // (or fire before we listen), which left the spinner running forever.
    // connect() is a no-op for the printer already linked and closes any
    // other one, so no isConnected pre-check (it was stale after disconnect).
    var ok = false;
    try {
      ok = await _bt.connect(device).timeout(const Duration(seconds: 20)) ==
          true;
      if (ok) {
        _report('Connected to ${device.name ?? device.address}');
      } else {
        _report('Could not connect to ${device.name ?? device.address}',
            error: true);
      }
    } on TimeoutException {
      _report('Connection timed out', error: true);
    } catch (e) {
      _report('Connection failed: $e', error: true);
    }
    _set(() {
      _connected = ok;
      _connecting = false;
    });
  }

  Future<void> _disconnect() async {
    try {
      await _bt.disconnect();
      _report('Disconnected');
    } catch (e) {
      _report('Disconnect error: $e', error: true);
    }
    _set(() {
      _connected = false;
      _connecting = false;
    });
  }

  /// Runs one job: awaits it, shows progress and the ok / error result.
  Future<void> _run(String label, Future<String?> Function() job) async {
    if (_busy) return;
    _set(() => _busy = true);
    try {
      final msg = await job();
      _report('$label: ${msg ?? 'sent'}');
    } catch (e) {
      _report('$label failed: $e', error: true);
    }
    _set(() => _busy = false);
  }

  Future<void> _checkStatus() => _run('Status', () async {
        final tspl = _useAs == UseAs.label;
        final reply =
            await _bt.queryStatus(tspl ? statusQueryTspl : statusQueryEscPos);
        if (reply == null) return 'no reply';
        final hex = reply
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .toUpperCase();
        return '${tspl ? 'TSPL' : 'ESC/POS'} reply [$hex]';
      });

  Widget _printers() => PrintersSection(
        paired: _paired,
        nearby: _nearby,
        selected: _selected,
        connected: _connected,
        connecting: _connecting,
        loading: _loading,
        scanning: _scanning,
        onRefresh: _loadDevices,
        onToggleScan: _toggleScan,
        onConnect: _connect,
        onDisconnect: _disconnect,
        onPair: _pair,
      );

  Widget _jobsPane() {
    final enabled = _connected && !_connecting && !_busy;
    final receipt = ReceiptTab(run: _run, enabled: enabled);
    final label = LabelTab(run: _run, enabled: enabled);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<UseAs>(
            segments: const [
              ButtonSegment(
                  value: UseAs.receipt,
                  icon: Icon(Icons.receipt_rounded),
                  label: Text('Receipt')),
              ButtonSegment(
                  value: UseAs.label,
                  icon: Icon(Icons.label_rounded),
                  label: Text('Label')),
              ButtonSegment(value: UseAs.both, label: Text('Both')),
            ],
            selected: {_useAs},
            onSelectionChanged: (s) => _set(() => _useAs = s.first),
          ),
          OutlinedButton.icon(
            onPressed: enabled ? _checkStatus : null,
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Check status'),
          ),
        ],
      ),
    );
    final Widget body = switch (_useAs) {
      UseAs.receipt => receipt,
      UseAs.label => label,
      UseAs.both => DefaultTabController(
          length: 2,
          child: Column(children: [
            const TabBar(tabs: [Tab(text: 'Receipt'), Tab(text: 'Label')]),
            Expanded(child: TabBarView(children: [receipt, label])),
          ]),
        ),
    };
    return Column(children: [header, Expanded(child: body)]);
  }

  Widget _resultBar() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: _resultError ? cs.errorContainer : cs.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(
                _busy
                    ? Icons.hourglass_top_rounded
                    : _resultError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                size: 20,
                color: _resultError ? cs.onErrorContainer : cs.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _busy ? 'Printing...' : (_result ?? 'Ready'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _resultError ? cs.onErrorContainer : null),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drago Blue Printer')),
      bottomNavigationBar: _resultBar(),
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 380,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _printers(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _jobsPane()),
          ]);
        }
        // Phone: printers on top (scrollable, capped), jobs below.
        return Column(children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _printers(),
            ),
          ),
          Expanded(child: _jobsPane()),
        ]);
      }),
    );
  }
}
