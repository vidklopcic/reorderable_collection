import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reordeable_collection/reordeable_collection.dart';

void main() {
  const MethodChannel channel = MethodChannel('reordeable_collection');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });
}
