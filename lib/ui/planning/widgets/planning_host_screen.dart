import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/utils/result.dart';
import 'planning_screen.dart';

class PlanningHostScreen extends StatelessWidget {
  const PlanningHostScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<Result<PersonalDataHubRuntime>?>();
    return switch (state) {
      Ok<PersonalDataHubRuntime>(:final value) =>
        PlanningScreen(service: value),
      Error<PersonalDataHubRuntime>() => Scaffold(
          appBar: AppBar(title: const Text('今天 / 本周')),
          body: const Center(child: Text('暂时无法打开规划，请返回后重试。'))),
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
