import FlutterMacOS
import AppKit

public class DragoBluePrinterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "drago_blue_printer", binaryMessenger: registrar.messenger)
    let instance = DragoBluePrinterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // result("iOS " + UIDevice.current.systemVersion)
    result(NSNumber(value: 0))
  }
}
