import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/ui/timeline/view_models/timeline_viewmodel.dart';

final personaChatNavigatorObserver = PersonaChatNavigatorObserver();

String personaChatRouteName(String characterId) => 'persona-chat:$characterId';

Route<void> buildPersonaChatRoute(
  String characterId, {
  WidgetBuilder? builder,
}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(
      name: personaChatRouteName(characterId),
      arguments: characterId,
    ),
    builder: builder ??
        (context) => PersonaChatScreen(
              characterId: characterId,
              enableRichCapture: true,
              onOpenSpaces: () {
                final vm = TimelineViewModel(router: MemexRouter());
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CompanionLifeSpaceScreen(timelineViewModel: vm),
                  ),
                );
              },
            ),
  );
}

void openPersonaChat(
  BuildContext context, {
  required String characterId,
  bool rootNavigator = false,
  WidgetBuilder? builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: rootNavigator);
  final existingRoute = personaChatNavigatorObserver.routeForName(
    personaChatRouteName(characterId),
  );

  if (existingRoute != null) {
    navigator.popUntil((route) => identical(route, existingRoute));
    return;
  }

  navigator.push(
    buildPersonaChatRoute(
      characterId,
      builder: builder,
    ),
  );
}

class PersonaChatNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  Route<dynamic>? routeForName(String name) {
    for (var i = _routes.length - 1; i >= 0; i--) {
      final route = _routes[i];
      if (route.settings.name == name) {
        return route;
      }
    }
    return null;
  }

  @visibleForTesting
  int routeCountForName(String name) =>
      _routes.where((route) => route.settings.name == name).length;

  @visibleForTesting
  void resetForTesting() {
    _routes.clear();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final oldIndex = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldIndex >= 0) {
      if (newRoute != null) {
        _routes[oldIndex] = newRoute;
      } else {
        _routes.removeAt(oldIndex);
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
