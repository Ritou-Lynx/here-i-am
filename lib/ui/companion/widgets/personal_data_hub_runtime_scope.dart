import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime_owner.dart';
import 'package:memex/utils/result.dart';
import 'personal_data_hub_host.dart';

/// Resets the exposed result before replacing a database-bound runtime.
class PersonalDataHubRuntimeScope extends StatefulWidget {
  const PersonalDataHubRuntimeScope({super.key, required this.child});
  final Widget child;

  @override
  State<PersonalDataHubRuntimeScope> createState() =>
      _PersonalDataHubRuntimeScopeState();
}

class _PersonalDataHubRuntimeScopeState
    extends State<PersonalDataHubRuntimeScope> {
  // Reset FutureProvider's old result without disposing the settings page
  // currently awaiting suspend before it closes the database and reloads.
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final future = context.watch<PersonalDataHubRuntimeOwner>().future;
    return FutureProvider<Result<PersonalDataHubRuntime>?>.value(
      key: ObjectKey(future),
      value: future,
      initialData: null,
      child: KeyedSubtree(
        key: _childKey,
        child: PersonalDataHubHost(child: widget.child),
      ),
    );
  }
}
