import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/utils/result.dart';

/// Owns resume refresh even when the planning/capture pages are closed.
class PersonalDataHubHost extends StatefulWidget {
  const PersonalDataHubHost({super.key, required this.child});
  final Widget child;
  @override
  State<PersonalDataHubHost> createState() => _PersonalDataHubHostState();
}

class _PersonalDataHubHostState extends State<PersonalDataHubHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final result = context.read<Result<PersonalDataHubRuntime>?>();
    if (result case Ok<PersonalDataHubRuntime>(:final value)) {
      unawaited(runResultVoid(value.refresh));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
