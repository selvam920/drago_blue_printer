## 1.0.4
* Fix app crash when the printer closes the link (reader thread threw on read -1).
* Fix crashes from null adapter/context/binding and bad argument types; every call now replies once, on the main thread.
* Writes run off the main thread and report failures (`write_error`) instead of false success; dead links are detected and marked disconnected.
* Check BLUETOOTH_CONNECT / BLUETOOTH_SCAN on Android 12+ before use (`no_permissions` error instead of SecurityException).
* Safe connect/disconnect (locked, reconnect to another printer closes the old one); receivers registered once and unregistered safely; scan cancel stops discovery.
* Reconnecting right after a disconnect waits for the old RFCOMM channel to close (fixes hang/fail on re-tap).
* Coroutine scope survives activity rotation.
* `getBondedDevices`/`scan` no longer return empty on Android 12+ because of `Permission.bluetooth`.
* New: `BluetoothDevice.battery` and `connected` for bonded printers, `queryStatus(query, timeout)` to read a printer status reply.
* `pairDevice` returns the real `createBond()` result.
* Example: connect settles from `connect()`'s result, so the spinner no longer sticks after disconnect -> reconnect.

## 1.0.2
* Fix android AGP

## 1.0.2
* Upgrade android AGP

## 1.0.1
* update permission_handler v13.0.0

## 1.0.0
-- added batch printing

## 0.0.9

* Renamed iOS plugin files from BlueThermalPrinter to DragoBluePrinter
* Updated iOS podspec file name to drago_blue_printer.podspec

## 0.0.8

* Bluetooth printer only return

## 0.0.7

* Migrated from java to kotlin

## 0.0.6

* Gradle upgrade to > 8.0

## 0.0.5

* Migrated to flutter >= 3.3.0

## 0.0.3
* Removed Print QR Code

## 0.0.2
* Updated to Android 12

## 0.0.1

* initial release.