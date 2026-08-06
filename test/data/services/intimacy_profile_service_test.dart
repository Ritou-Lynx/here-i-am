import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/intimacy_profile_service.dart';

void main() {
  group('IntimacyProfile', () {
    test('defaultProfile carries the user-stated intensity grammar', () {
      final profile = IntimacyProfile.defaultProfile();
      expect(profile.hardLimits, isEmpty);
      expect(profile.intensityGrammar.resistanceHandling, contains('更用力压住'));
      expect(profile.intensityGrammar.languageStyle, '粗俗直白');
      expect(profile.buildProfileText(), isNotEmpty);
      expect(profile.buildProfileText(), contains('强度语法'));
    });

    test('buildProfileText includes hard limits when present', () {
      const profile = IntimacyProfile(
        hardLimits: ['不要角色扮演陌生人'],
        intensityGrammar: IntensityGrammar(
          resistanceHandling: '',
          painTolerance: '',
          aftercare: '',
          pacing: '',
          languageStyle: '',
        ),
      );
      final text = profile.buildProfileText();
      expect(text, contains('硬边界（绝对禁止）'));
      expect(text, contains('不要角色扮演陌生人'));
    });

    test('empty profile renders empty text', () {
      const profile = IntimacyProfile(
        hardLimits: [],
        intensityGrammar: IntensityGrammar(
          resistanceHandling: '',
          painTolerance: '',
          aftercare: '',
          pacing: '',
          languageStyle: '',
        ),
      );
      expect(profile.isEmpty, isTrue);
      expect(profile.buildProfileText(), isEmpty);
    });

    test('json round-trip preserves all fields', () {
      const profile = IntimacyProfile(
        hardLimits: ['A', 'B'],
        intensityGrammar: IntensityGrammar(
          resistanceHandling: 'R',
          painTolerance: 'P',
          aftercare: 'A',
          pacing: 'Pace',
          languageStyle: 'L',
        ),
        styleNotes: [
          IntimacyProfileEntry(text: 'note', source: 'inferred', confidence: 0.7),
        ],
      );
      final restored = IntimacyProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(profile.toJson()))),
      );
      expect(restored.hardLimits, ['A', 'B']);
      expect(restored.intensityGrammar.pacing, 'Pace');
      expect(restored.styleNotes.single.source, 'inferred');
      expect(restored.styleNotes.single.confidence, 0.7);
    });
  });
}
