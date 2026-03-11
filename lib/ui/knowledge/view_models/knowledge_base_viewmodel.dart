import 'package:flutter/foundation.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/result.dart';

/// ViewModel for the Knowledge base page. Holds recent files, category counts.
class KnowledgeBaseViewModel extends ChangeNotifier {
  KnowledgeBaseViewModel({required MemexRouter router}) : _router = router;

  final MemexRouter _router;

  bool isLoading = false;
  List<Map<String, dynamic>> recentFiles = [];
  Map<String, int> categoryCounts = {};

  int countItems(String category) => categoryCounts[category] ?? 0;

  Future<void> fetchData() async {
    isLoading = true;
    notifyListeners();
    final listResult = await _router.listPkmDirectory();
    listResult.when(onOk: (_) {}, onError: (_, __) {});
    final countResult = await _router
        .countPkmItems(['Projects', 'Areas', 'Resources', 'Archives']);
    categoryCounts =
        countResult.when(onOk: (c) => c, onError: (_, __) => <String, int>{});
    final recentResult = await _router.getRecentPkmFiles();
    recentFiles = recentResult.when(
        onOk: (r) => r, onError: (_, __) => <Map<String, dynamic>>[]);
    isLoading = false;
    notifyListeners();
  }
}
