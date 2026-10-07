import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Command object for batch printing. Build a list of these and pass to
/// [DragoBluePrinter.printBatch] to send all commands in a single BT packet.
class PrintCommand {
  final Map<String, dynamic> _data;
  PrintCommand._(this._data);

  Map<String, dynamic> toMap() => _data;

  /// Custom text line
  factory PrintCommand.custom(String message, int size, int align,
          {String? charset}) =>
      PrintCommand._({
        'type': 'custom',
        'message': message,
        'size': size,
        'align': align,
        'charset': charset,
      });

  /// Two-column left/right text
  factory PrintCommand.leftRight(String left, String right, int size,
          {String? charset, String? format}) =>
      PrintCommand._({
        'type': 'leftRight',
        'string1': left,
        'string2': right,
        'size': size,
        'charset': charset,
        'format': format,
      });

  /// Three-column text
  factory PrintCommand.threeColumn(
          String s1, String s2, String s3, int size,
          {String? charset, String? format}) =>
      PrintCommand._({
        'type': '3column',
        'string1': s1,
        'string2': s2,
        'string3': s3,
        'size': size,
        'charset': charset,
        'format': format,
      });

  /// Four-column text
  factory PrintCommand.fourColumn(
          String s1, String s2, String s3, String s4, int size,
          {String? charset, String? format}) =>
      PrintCommand._({
        'type': '4column',
        'string1': s1,
        'string2': s2,
        'string3': s3,
        'string4': s4,
        'size': size,
        'charset': charset,
        'format': format,
      });

  /// New line feed
  factory PrintCommand.newLine() => PrintCommand._({'type': 'newLine'});

  /// Paper cut
  factory PrintCommand.paperCut() => PrintCommand._({'type': 'paperCut'});

  /// Raw ESC/POS bytes
  factory PrintCommand.rawBytes(Uint8List bytes) =>
      PrintCommand._({'type': 'rawBytes', 'bytes': bytes});
}

class DragoBluePrinter {
  static const int STATE_OFF = 10;
  static const int STATE_TURNING_ON = 11;
  static const int STATE_ON = 12;
  static const int STATE_TURNING_OFF = 13;
  static const int STATE_BLE_TURNING_ON = 14;
  static const int STATE_BLE_ON = 15;
  static const int STATE_BLE_TURNING_OFF = 16;
  static const int ERROR = -1;
  static const int CONNECTED = 1;
  static const int DISCONNECTED = 0;
  static const int DISCONNECT_REQUESTED = 2;

  static const String namespace = 'drago_blue_printer';

  static const MethodChannel _channel =
      const MethodChannel('$namespace/methods');

  static const EventChannel _readChannel =
      const EventChannel('$namespace/read');

  static const EventChannel _stateChannel =
      const EventChannel('$namespace/state');

  static const EventChannel _scanChannel =
      const EventChannel('$namespace/scan');

  final StreamController<MethodCall> _methodStreamController =
      new StreamController.broadcast();

  //Stream<MethodCall> get _methodStream => _methodStreamController.stream;

  DragoBluePrinter._() {
    _channel.setMethodCallHandler((MethodCall call) async {
      _methodStreamController.add(call);
    });
  }

  static DragoBluePrinter _instance = new DragoBluePrinter._();

  static DragoBluePrinter get instance => _instance;

  ///onStateChanged()
  Stream<int?> onStateChanged() async* {
    yield await _channel.invokeMethod('state').then((buffer) => buffer);

    yield* _stateChannel.receiveBroadcastStream().map((buffer) => buffer);
  }

  ///onRead()
  Stream<String> onRead() =>
      _readChannel.receiveBroadcastStream().map((buffer) => buffer.toString());

  Future<bool?> get isAvailable async =>
      await _channel.invokeMethod('isAvailable');

  Future<bool?> get isOn async => await _channel.invokeMethod('isOn');

  Future<bool?> get isConnected async {
    try {
      return await _channel.invokeMethod<bool>('isConnected');
    } catch (e) {
      return false;
    }
  }

  Future<bool?> openSettings() async =>
      await _channel.invokeMethod('openSettings');

  /// Requests the runtime Bluetooth permissions. On Android 12+ only
  /// BLUETOOTH_SCAN + BLUETOOTH_CONNECT matter (the legacy
  /// [Permission.bluetooth] can report denied there); below 12
  /// permission_handler reports those two as granted.
  Future<bool> _ensurePermissions({bool location = false}) async {
    try {
      final perms = <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        if (location) Permission.location,
      ];
      final statuses = await perms.request();
      final granted = statuses[Permission.bluetoothScan]?.isGranted == true &&
          statuses[Permission.bluetoothConnect]?.isGranted == true;
      if (!granted &&
          statuses.values.any((s) => s.isPermanentlyDenied)) {
        await openAppSettings();
      }
      return granted;
    } catch (e) {
      // Permission plugin unavailable / already requesting: let the native
      // side decide (it checks and reports no_permissions).
      return true;
    }
  }

  ///getBondedDevices()
  Future<List<BluetoothDevice>> getBondedDevices() async {
    if (!await _ensurePermissions()) return [];
    try {
      final List? list = await _channel.invokeMethod<List>('getBondedDevices');
      return (list ?? const [])
          .whereType<Map>()
          .map((map) => BluetoothDevice.fromMap(map))
          .toList();
    } catch (e) {
      print("Error getting bonded devices: $e");
      return [];
    }
  }

  ///scan()
  Stream<BluetoothDevice> scan() async* {
    // Location is needed for discovery below Android 12; native reports
    // no_permissions if it is missing, which ends the scan quietly here.
    if (!await _ensurePermissions(location: true)) return;
    yield* _scanChannel
        .receiveBroadcastStream()
        .where((map) => map is Map)
        .map((map) => BluetoothDevice.fromMap(map as Map))
        .handleError((Object e) => print("Bluetooth scan error: $e"));
  }

  ///pairDevice(BluetoothDevice device)
  Future<dynamic> pairDevice(BluetoothDevice device) async =>
      await _channel.invokeMethod('pairDevice', device.toMap());

  ///isDeviceConnected(BluetoothDevice device)
  Future<bool?> isDeviceConnected(BluetoothDevice device) async =>
      await _channel.invokeMethod('isDeviceConnected', device.toMap());

  /// Writes [query] on the open connection and returns the printer's first
  /// reply within [timeout], or null when not connected / no reply.
  Future<Uint8List?> queryStatus(
    Uint8List query, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) =>
      _channel.invokeMethod<Uint8List>('queryStatus', {
        'query': query,
        'timeout': timeout.inMilliseconds,
      }).catchError((Object e) {
        print("queryStatus failed: $e");
        return null;
      });

  ///connect(BluetoothDevice device)
  Future<dynamic> connect(BluetoothDevice device) async =>
      await _channel.invokeMethod('connect', device.toMap());

  ///disconnect()
  Future<dynamic> disconnect() async =>
      await _channel.invokeMethod('disconnect');

  ///write(String message)
  Future<dynamic> write(String message) async =>
      await _channel.invokeMethod('write', {'message': message});

  ///writeBytes(Uint8List message)
  Future<dynamic> writeBytes(Uint8List message) async =>
      await _channel.invokeMethod('writeBytes', {'message': message});

  ///printCustom(String message, int size, int align,{String? charset})
  Future<dynamic> printCustom(String message, int size, int align,
          {String? charset}) =>
      _channel.invokeMethod('printCustom', {
        'message': message,
        'size': size,
        'align': align,
        'charset': charset
      });

  ///printNewLine()
  Future<dynamic> printNewLine() => _channel.invokeMethod('printNewLine');

  ///paperCut()
  Future<dynamic> paperCut() => _channel.invokeMethod('paperCut');

  ///printImage(String pathImage)
  Future<dynamic> printImage(String pathImage) async =>
      await _channel.invokeMethod('printImage', {'pathImage': pathImage});

  ///printImageBytes(Uint8List bytes)
  Future<dynamic> printImageBytes(Uint8List bytes) async =>
      await _channel.invokeMethod('printImageBytes', {'bytes': bytes});

  ///printLeftRight(String string1, String string2, int size,{String? charset, String? format})
  Future<dynamic> printLeftRight(String string1, String string2, int size,
          {String? charset, String? format}) async =>
      await _channel.invokeMethod('printLeftRight', {
        'string1': string1,
        'string2': string2,
        'size': size,
        'charset': charset,
        'format': format
      });

  ///print3Column(String string1, String string2, String string3, int size,{String? charset, String? format})
  Future<dynamic> print3Column(
          String string1, String string2, String string3, int size,
          {String? charset, String? format}) =>
      _channel.invokeMethod('print3Column', {
        'string1': string1,
        'string2': string2,
        'string3': string3,
        'size': size,
        'charset': charset,
        'format': format
      });

  ///print4Column(String string1, String string2, String string3,String string4, int size,{String? charset, String? format})
  Future<dynamic> print4Column(String string1, String string2, String string3,
          String string4, int size,
          {String? charset, String? format}) =>
      _channel.invokeMethod('print4Column', {
        'string1': string1,
        'string2': string2,
        'string3': string3,
        'string4': string4,
        'size': size,
        'charset': charset,
        'format': format
      });

  /// Send multiple print commands in a **single** method channel call.
  ///
  /// This is dramatically faster than calling individual print methods because:
  /// - Only 1 Dart→Native round-trip instead of N
  /// - All commands are merged into a single byte buffer on the native side
  /// - The buffer is sent over Bluetooth in optimally-sized chunks
  ///
  /// Example:
  /// ```dart
  /// await printer.printBatch([
  ///   PrintCommand.custom('RECEIPT', 3, 1),
  ///   PrintCommand.newLine(),
  ///   PrintCommand.leftRight('Item', 'Price', 1),
  ///   PrintCommand.leftRight('Coffee', '\$3.50', 0),
  ///   PrintCommand.newLine(),
  ///   PrintCommand.custom('Thank you!', 0, 1),
  ///   PrintCommand.paperCut(),
  /// ]);
  /// ```
  Future<dynamic> printBatch(List<PrintCommand> commands) =>
      _channel.invokeMethod('printBatch', {
        'commands': commands.map((c) => c.toMap()).toList(),
      });
}

class BluetoothDevice {
  final String? name;
  final String? address;
  final int type = 0;
  bool connected = false;

  /// Battery % when the printer reports it to the phone, else null.
  int? battery;

  BluetoothDevice(this.name, this.address);

  BluetoothDevice.fromMap(Map map)
      : name = map['name'],
        address = map['address'],
        connected = map['connected'] == true,
        battery = map['battery'] is int ? map['battery'] as int : null;

  Map<String, dynamic> toMap() => {
        'name': this.name,
        'address': this.address,
        'type': this.type,
        'connected': this.connected,
      };

  operator ==(Object other) {
    return other is BluetoothDevice && other.address == this.address;
  }

  @override
  int get hashCode => address.hashCode;
}
