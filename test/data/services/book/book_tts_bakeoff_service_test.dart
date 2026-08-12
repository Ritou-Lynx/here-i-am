import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/book/book_tts_bakeoff_service.dart';

void main() {
  test('voice candidates stay anonymous and use distinct Chinese speakers', () {
    const candidates = BookTtsBakeoffService.candidates;
    expect(candidates.map((e) => e.label), ['A', 'B', 'C']);
    expect(candidates.map((e) => e.speakerId).toSet(), hasLength(3));
    expect(candidates.every((e) => e.speakerId >= 3 && e.speakerId <= 57),
        isTrue);
  });

  test('sample result calculates real-time factor', () {
    const result = BookTtsSampleResult(
      audioPath: 'sample.wav',
      initMs: 200,
      firstChunkMs: 300,
      generationMs: 2500,
      audioDurationMs: 10000,
      peakRssBytes: 1024,
    );
    expect(result.realTimeFactor, 0.25);
  });

  test('rating average and report remain machine-readable', () {
    const rating = BookTtsVoiceRating(
      naturalness: 5,
      emotion: 4,
      pronunciation: 3,
      longListening: 5,
      dialogue: 3,
    );
    expect(rating.average, 4);

    final report = encodeBookTtsBakeoffReport(
      speed: 1.25,
      ratings: const {'A': rating},
      results: const {},
    );
    final decoded = jsonDecode(report) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    expect(decoded['speed'], 1.25);
    expect(decoded['voices']['A']['rating']['naturalness'], 5);
  });
}
