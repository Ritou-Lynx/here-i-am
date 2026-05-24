import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/ui/character/widgets/persona_chat_navigation.dart';

void main() {
  setUp(() {
    personaChatNavigatorObserver.resetForTesting();
  });

  testWidgets('openPersonaChat reuses an existing character chat route',
      (tester) async {
    const characterId = 'companion-1';

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [personaChatNavigatorObserver],
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  openPersonaChat(
                    context,
                    characterId: characterId,
                    builder: (_) => const _FakeChatPage(
                      characterId: characterId,
                    ),
                  );
                },
                child: const Text('Open chat'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    expect(find.text('Chat companion-1'), findsOneWidget);
    expect(
      personaChatNavigatorObserver.routeCountForName(
        personaChatRouteName(characterId),
      ),
      1,
    );

    await tester.tap(find.text('Cover chat'));
    await tester.pumpAndSettle();

    expect(find.text('Temporary page'), findsOneWidget);

    await tester.tap(find.text('Notification tap'));
    await tester.pumpAndSettle();

    expect(find.text('Chat companion-1'), findsOneWidget);
    expect(find.text('Temporary page'), findsNothing);
    expect(
      personaChatNavigatorObserver.routeCountForName(
        personaChatRouteName(characterId),
      ),
      1,
    );
  });
}

class _FakeChatPage extends StatelessWidget {
  const _FakeChatPage({required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('Chat $characterId'),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _TemporaryPage(characterId: characterId),
                ),
              );
            },
            child: const Text('Cover chat'),
          ),
        ],
      ),
    );
  }
}

class _TemporaryPage extends StatelessWidget {
  const _TemporaryPage({required this.characterId});

  final String characterId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Temporary page'),
          TextButton(
            onPressed: () {
              openPersonaChat(
                context,
                characterId: characterId,
                builder: (_) => _FakeChatPage(characterId: characterId),
              );
            },
            child: const Text('Notification tap'),
          ),
        ],
      ),
    );
  }
}
