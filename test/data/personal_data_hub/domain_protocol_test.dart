import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';

void main() {
  test('canonical numbers match Node JSON.stringify IEEE-754 vectors', () {
    // Expected strings independently obtained from Node's JSON.stringify over
    // Buffer.readDoubleBE; these tests do not require Node on Flutter CI.
    const vectors = {
      '0000000000000000': '0',
      '8000000000000000': '0',
      '0000000000000001': '5e-324',
      '8000000000000001': '-5e-324',
      '7fefffffffffffff': '1.7976931348623157e+308',
      'ffefffffffffffff': '-1.7976931348623157e+308',
      '4340000000000000': '9007199254740992',
      '4430000000000000': '295147905179352830000',
      '44b52d02c7e14af5': '9.999999999999997e+22',
      '44b52d02c7e14af6': '1e+23',
      '44b52d02c7e14af7': '1.0000000000000001e+23',
      '444b1ae4d6e2ef4e': '999999999999999700000',
      '444b1ae4d6e2ef4f': '999999999999999900000',
      '444b1ae4d6e2ef50': '1e+21',
      '3eb0c6f7a0b5ed8c': '9.999999999999997e-7',
      '3eb0c6f7a0b5ed8d': '0.000001',
      '41b3de4355555553': '333333333.3333332',
      '41b3de4355555554': '333333333.33333325',
      '41b3de4355555555': '333333333.3333333',
    };
    for (final entry in vectors.entries) {
      final bytes = ByteData(8);
      for (var i = 0; i < 8; i++) {
        bytes.setUint8(
            i, int.parse(entry.key.substring(i * 2, i * 2 + 2), radix: 16));
      }
      expect(canonicalJson(bytes.getFloat64(0)), entry.value,
          reason: entry.key);
    }
    expect(
        canonicalJson([1e-7, 1e-6, 1e20, 1e21, 1.0, -0.0, 1000000000000000100]),
        '[1e-7,0.000001,100000000000000000000,1e+21,1,0,1000000000000000100]');
  });

  test(
      'canonical objects follow Core index key enumeration and nested encoding',
      () {
    expect(
        canonicalJson({
          'z': [
            1e20,
            {'a': 1.0}
          ],
          '10': 'ten',
          '2': 'two',
          '01': 'leading',
          '4294967295': false,
          '4294967294': true,
          'a': '中文\n😀'
        }),
        '{"2":"two","10":"ten","4294967294":true,"01":"leading",'
        '"4294967295":false,"a":"中文\\n😀","z":[100000000000000000000,{"a":1}]}');
  });

  test('nonfinite JSON values fail closed instead of weakening digests', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      expect(
          () => canonicalJson({
                'nested': [value]
              }),
          throwsA(isA<DomainFailure>()));
    }
    expect(() => canonicalJson({1: 'nonstring key'}),
        throwsA(isA<DomainFailure>()));
  });
}
