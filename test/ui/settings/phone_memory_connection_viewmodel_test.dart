import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/settings/view_models/phone_memory_connection_viewmodel.dart';
import 'package:memex/utils/result.dart';

void main() {
  test('connect rejects a blank code before it reaches the facade', () async {
    final facade = _FakeFacade();
    final viewModel = PhoneMemoryConnectionViewModel(facade: facade);

    await viewModel.connect.execute('   ');

    expect(viewModel.connect.error, isTrue);
    expect(facade.lastConnectionCode, isNull);
    viewModel.dispose();
  });

  test('receipt projection rebuilds counts and removes nested secrets', () {
    final facade = _FakeFacade()
      ..receipt = const {
        'source': 'phone_v3_live',
        'status': 'available',
        'counts': {
          'episodes': 1,
          'fragments': -1,
          'sagas': 'not-a-count',
          'token': 'nested-secret',
          'dreaming': {'narrative': 'nested-body'},
        },
        'captured_at': '2026-09-05T10:00:00Z',
        'token': 'must-not-escape',
        'query': 'must-not-escape',
        'dreaming': 'must-not-escape',
      };
    final viewModel = PhoneMemoryConnectionViewModel(facade: facade);

    expect(viewModel.lastReceipt, {
      'source': 'phone_v3_live',
      'status': 'available',
      'counts': {'episodes': 1},
      'time': '2026-09-05T10:00:00.000Z',
    });
    viewModel.dispose();
  });
}

class _FakeFacade extends PhoneMemoryConnectionFacade {
  Map<String, Object?>? receipt;
  String? lastConnectionCode;

  @override
  bool get isDesktopConfigured => false;

  @override
  DateTime? get desktopExpiresAt => null;

  @override
  bool get isPhoneRunning => false;

  @override
  Map<String, Object?>? get lastReceipt => receipt;

  @override
  PhoneMemoryConnectionSession? get phoneSession => null;

  @override
  Future<Result<void>> connect(String connectionCode) async {
    lastConnectionCode = connectionCode;
    return const Ok.v();
  }

  @override
  void disconnect() {}

  @override
  Future<Result<PhoneMemoryConnectionSession>> startPhone() async =>
      Error(StateError('not used'));

  @override
  Future<Result<void>> stopPhone() async => const Ok.v();
}
