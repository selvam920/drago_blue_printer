import 'dart:io';
import 'package:example/testprint.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:drago_blue_printer/drago_blue_printer.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DragoBluePrinter bluetooth = DragoBluePrinter.instance;

  List<BluetoothDevice> _devices = [];
  final List<BluetoothDevice> _scannedDevices = [];
  BluetoothDevice? _device;
  bool _connected = false;
  String? pathImage;
  var testPrint = TestPrint();
  bool _isLoading = false;
  bool _isScanning = false;
  StreamSubscription<BluetoothDevice>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> initPlatformState() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    List<BluetoothDevice> devices = [];

    try {
      devices = await bluetooth.getBondedDevices();
    } catch (e) {
      debugPrint("Error in initPlatformState: $e");
      // Optionally show a snackbar here
      // show("Error loading devices: $e");
    }

    bluetooth.onStateChanged().listen((state) {
      switch (state) {
        case DragoBluePrinter.CONNECTED:
          setState(() {
            _connected = true;
            debugPrint("bluetooth device state: connected");
          });
          break;
        case DragoBluePrinter.DISCONNECTED:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: disconnected");
          });
          break;
        case DragoBluePrinter.DISCONNECT_REQUESTED:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: disconnect requested");
          });
          break;
        case DragoBluePrinter.STATE_TURNING_OFF:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: bluetooth turning off");
          });
          break;
        case DragoBluePrinter.STATE_OFF:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: bluetooth off");
          });
          break;
        case DragoBluePrinter.STATE_ON:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: bluetooth on");
          });
          break;
        case DragoBluePrinter.STATE_TURNING_ON:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: bluetooth turning on");
          });
          break;
        case DragoBluePrinter.ERROR:
          setState(() {
            _connected = false;
            debugPrint("bluetooth device state: error");
          });
          break;
        default:
          debugPrint(state.toString());
          break;
      }
    });

    if (!mounted) return;
    setState(() {
      _devices = devices;
      _isLoading = false;
    });

    // The connection status is now handled by the onStateChanged listener
    // if (isConnected) {
    //   setState(() {
    //     _connected = true;
    //   });
    // }
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _scannedDevices.clear();
    });

    _scanSubscription?.cancel();
    _scanSubscription = bluetooth.scan().listen((device) {
      if (!_devices.any((d) => d.address == device.address) &&
          !_scannedDevices.any((d) => d.address == device.address)) {
        setState(() {
          _scannedDevices.add(device);
        });
      }
    });

    // Auto stop after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      _stopScan();
    });
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _pairDevice(BluetoothDevice device) async {
    try {
      await bluetooth.pairDevice(device);
      // Give it a moment to pair, then refresh bonded list
      await Future.delayed(const Duration(seconds: 2));
      initPlatformState();
    } catch (e) {
      debugPrint("Pairing error: $e");
      show("Pairing failed: $e", duration: const Duration(seconds: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 2,
          backgroundColor: Colors.blue.shade50,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Bluetooth Printer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: initPlatformState,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isScanning ? _stopScan : _startScan,
          icon: Icon(_isScanning ? Icons.stop : Icons.search),
          label: Text(_isScanning ? "Stop Scan" : "Scan Devices"),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      color: Colors.blue.shade50,
                      child: Text(
                        "Paired Devices",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900),
                      ),
                    ),
                    if (_devices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                            child: Text("No paired devices",
                                style: TextStyle(color: Colors.grey))),
                      ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _devices.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        return _buildPairedDeviceItem(_devices[index]);
                      },
                    ),

                    if (_isScanning || _scannedDevices.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        width: double.infinity,
                        color: Colors.orange.shade50,
                        child: Row(
                          children: [
                            Text(
                              "Available Devices",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900),
                            ),
                            if (_isScanning) ...[
                              const SizedBox(width: 10),
                              const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            ]
                          ],
                        ),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _scannedDevices.length,
                        padding: const EdgeInsets.all(12),
                        itemBuilder: (context, index) {
                          return _buildScannedDeviceItem(
                              _scannedDevices[index]);
                        },
                      ),
                    ],
                    const SizedBox(height: 80), // Fab space
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPairedDeviceItem(BluetoothDevice device) {
    final isSelected = _device?.address == device.address;
    final isReallyConnected = isSelected && _connected;

    return Card(
      elevation: isReallyConnected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isReallyConnected
            ? const BorderSide(color: Colors.green, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor:
              isReallyConnected ? Colors.green.shade100 : Colors.blue.shade50,
          child: Icon(
            Icons.print,
            color: isReallyConnected ? Colors.green : Colors.blue,
          ),
        ),
        title: Text(
          device.name ?? "Unknown Device",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(device.address ?? ""),
        trailing: isReallyConnected
            ? const Chip(
                label: Text("Connected",
                    style: TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: Colors.green,
                side: BorderSide.none,
              )
            : TextButton(
                onPressed: () => _connect(device),
                child: const Text("Connect"),
              ),
        children: [
          if (isReallyConnected)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      if (pathImage != null) {
                        await testPrint.sample(pathImage!);
                      }
                    },
                    icon: const Icon(Icons.receipt_long),
                    label: const Text("Print Test"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text("Disconnect"),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScannedDeviceItem(BluetoothDevice device) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.bluetooth),
        title: Text(device.name ?? "Unknown"),
        subtitle: Text(device.address ?? ""),
        trailing: OutlinedButton(
          onPressed: () => _pairDevice(device),
          child: const Text("Pair"),
        ),
      ),
    );
  }

  void _connect(BluetoothDevice device) {
    setState(() {
      _device = device;
    });
    bluetooth.isConnected.then((isConnected) {
      if (!(isConnected ?? false)) {
        bluetooth.connect(device).catchError((error) {
          setState(() => _connected = false);
          show("Connection failed: $error",
              duration: const Duration(seconds: 5));
        });
        // Removed setState(() => _connected = true); as it's handled by onStateChanged
      }
    });
  }

  void _disconnect() {
    bluetooth.disconnect();
    setState(() => _connected = false);
  }

  //write to app path
  Future<void> writeToFile(ByteData data, String path) {
    final buffer = data.buffer;
    return File(path).writeAsBytes(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  Future show(
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
        duration: duration,
      ),
    );
  }
}
