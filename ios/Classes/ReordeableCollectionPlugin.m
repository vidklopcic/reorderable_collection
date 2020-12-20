#import "ReordeableCollectionPlugin.h"
#if __has_include(<reordeable_collection/reordeable_collection-Swift.h>)
#import <reordeable_collection/reordeable_collection-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "reordeable_collection-Swift.h"
#endif

@implementation ReordeableCollectionPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftReordeableCollectionPlugin registerWithRegistrar:registrar];
}
@end
