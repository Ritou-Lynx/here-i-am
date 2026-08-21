import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fontAsset = 'assets/fonts/whiteboard/CascadiaCode-Regular.ttf';
const _licenseAsset = 'assets/fonts/whiteboard/CascadiaCode-OFL.txt';
const _fontSha256 =
    'c33ef522cdfeff99907fb54f3e97152bb18bfb9b56ec2fef4d4ceec51c8974a4';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cascadia Code official asset, license and family stay aligned',
      () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('- family: Cascadia Code'));
    expect(pubspec, contains('- asset: $_fontAsset'));

    final license = await rootBundle.loadString(_licenseAsset);
    expect(license, contains('Reserved Font Name Cascadia Code'));
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));

    final data = await rootBundle.load(_fontAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    expect(bytes.length, 598060);
    expect(bytes.take(4), [0, 1, 0, 0]);
    expect(sha256.convert(bytes).toString(), _fontSha256);
  });
}
