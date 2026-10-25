import 'package:flutter/material.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
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
      Ok<PersonalDataHubRuntime>(:final value) => FoodScreen(
          service: FoodService(
            store: value.hub.storeFor('food_entries'),
            clock: value.clock,
          ),
          clock: value.clock,
        ),
      Error<PersonalDataHubRuntime>() => Scaffold(
          appBar: AppBar(title: const Text('饮食')),
          body: const Center(child: Text('暂时无法打开饮食记录，请返回后重试。')),
        ),
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
