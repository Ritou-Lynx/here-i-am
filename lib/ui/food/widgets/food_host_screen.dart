import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/personal_data_hub/food_connection.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/utils/result.dart';
import 'package:provider/provider.dart';

import 'food_screen.dart';

class FoodHostScreen extends StatelessWidget {
  const FoodHostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<Result<PersonalDataHubRuntime>?>();
    return switch (state) {
      Ok<PersonalDataHubRuntime>(:final value) =>
        _FoodConnectionHost(runtime: value),
      Error<PersonalDataHubRuntime>() => Scaffold(
          appBar: AppBar(title: const Text('饮食')),
          body: const Center(child: Text('暂时无法打开饮食记录，请返回后重试。')),
        ),
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

class _FoodConnectionHost extends StatefulWidget {
  const _FoodConnectionHost({required this.runtime});
  final PersonalDataHubRuntime runtime;

  @override
  State<_FoodConnectionHost> createState() => _FoodConnectionHostState();
}

class _FoodConnectionHostState extends State<_FoodConnectionHost> {
  StreamSubscription<PersonalDataHubChange>? _subscription;
  Object? _lastStore;
  bool _attachTried = false;
  FoodService? _service;
  (Object?, String, String?)? _serviceKey;

  @override
  void initState() {
    super.initState();
    _subscription = widget.runtime.hub.changes.listen((_) => _changed());
    FoodConnector.instance.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnOpen());
  }

  @override
  void didUpdateWidget(covariant _FoodConnectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime.hub, widget.runtime.hub)) {
      unawaited(_subscription?.cancel());
      _subscription = widget.runtime.hub.changes.listen((_) => _changed());
      _lastStore = null;
      _attachTried = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOnOpen());
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _syncOnOpen();
  }

  void _syncOnOpen() {
    final store = widget.runtime.hub.storeFor(foodDomainName);
    if (store == null) {
      // Opening the page before the first chat sync still connects once.
      if (_attachTried) return;
      _attachTried = true;
      unawaited(FoodConnector.instance
          .ensureAttached(widget.runtime.hub)
          .catchError((Object _) {}));
      return;
    }
    if (identical(store, _lastStore)) return;
    _lastStore = store;
    unawaited(_syncFood());
  }

  Future<void> _syncFood() async {
    try {
      await widget.runtime.hub.syncOnce(foodDomainName);
    } catch (_) {
      // The connector exposes a short retry state while retaining old data.
    }
    await FoodConnector.instance.handleSyncResult(widget.runtime.hub);
  }

  Future<void> _refresh() async {
    await FoodConnector.instance.ensureAttached(widget.runtime.hub);
    if (widget.runtime.hub.storeFor(foodDomainName) != null) {
      await _syncFood();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FoodConnector.instance.removeListener(_changed);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  // Unrelated hub changes rebuild this widget; reuse the reader unless what it
  // shows changed, so the day view is not recreated and reloaded each time.
  FoodService _currentService() {
    final status = FoodConnector.instance.status;
    final store = widget.runtime.hub.storeFor(foodDomainName);
    final failure = status.phase == FoodConnectionPhase.failed
        ? status.screenMessage
        : null;
    final key = (store, status.screenMessage, failure);
    final existing = _service;
    if (existing != null &&
        _serviceKey != null &&
        identical(_serviceKey!.$1, key.$1) &&
        _serviceKey!.$2 == key.$2 &&
        _serviceKey!.$3 == key.$3) {
      return existing;
    }
    _serviceKey = key;
    return _service = FoodService(
      store: store,
      clock: widget.runtime.clock,
      missingStoreError: status.screenMessage,
      connectionError: failure,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FoodScreen(
      service: _currentService(),
      synchronize: _refresh,
      clock: widget.runtime.clock,
    );
  }
}
