class SentenceSplitter {
  SentenceSplitter({this.onSentence});

  void Function(String sentence)? onSentence;
  final _buffer = StringBuffer();

  static final _sentenceEnd = RegExp(r'[。！？!?.;；\n]');

  void feed(String chunk) {
    _buffer.write(chunk);
    _flush();
  }

  void finish() {
    final remaining = _buffer.toString().trim();
    _buffer.clear();
    if (remaining.isNotEmpty) {
      onSentence?.call(remaining);
    }
  }

  void reset() {
    _buffer.clear();
  }

  void _flush() {
    final text = _buffer.toString();
    var start = 0;
    for (final match in _sentenceEnd.allMatches(text)) {
      final end = match.end;
      final sentence = text.substring(start, end).trim();
      start = end;
      if (sentence.isNotEmpty) {
        onSentence?.call(sentence);
      }
    }
    _buffer
      ..clear()
      ..write(text.substring(start));
  }
}
