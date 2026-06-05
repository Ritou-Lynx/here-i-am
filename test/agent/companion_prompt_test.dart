import 'package:memex/agent/companion_agent/prompt.dart';
import 'package:test/test.dart';

void main() {
  test('companion relationship prompt keeps dual-mode and safety boundaries',
      () {
    expect(companionRelationshipPrompt, contains('ongoing relationship'));
    expect(companionRelationshipPrompt, contains('Default to companion mode'));
    expect(companionRelationshipPrompt, contains('Switch into assistant mode'));
    expect(companionRelationshipPrompt, contains('Do not end every reply'));
    expect(companionRelationshipPrompt, contains('real-world relationships'));
    expect(companionRelationshipPrompt, contains('delusional beliefs'));
  });
}
