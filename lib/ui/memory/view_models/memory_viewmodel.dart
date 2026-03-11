import 'package:flutter/foundation.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/result.dart';

/// ViewModel for the Memory page. Holds memory data and delegates to [MemexRouter].
class MemoryViewModel extends ChangeNotifier {
  MemoryViewModel({required MemexRouter router}) : _router = router;

  final MemexRouter _router;

  Map<String, dynamic>? memoryData;
  bool isLoading = true;
  String? error;

  Future<void> loadMemory() async {
    isLoading = true;
    error = null;
    notifyListeners();
    final result = await _router.getMemory();
    result.when(
      onOk: (data) {
        memoryData = data;
        error = null;
      },
      onError: (e, __) => error = e.toString(),
    );
    isLoading = false;
    notifyListeners();
  }
}
