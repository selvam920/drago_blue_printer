#import "DragoBluePrinterPlugin.h"
#import <drago_blue_printer/drago_blue_printer-Swift.h>

@implementation DragoBluePrinterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftDragoBluePrinterPlugin registerWithRegistrar:registrar];
}
@end
