
/// Abstract interface for automatic data collectors (Photos, Calendar, Audio, etc.)
abstract class DataCollector {
  /// The identifiable name of the source (e.g. 'photos', 'calendar', 'notes')
  String get sourceName;

  /// Collect new data items since the last run.
  ///
  /// The returned `List<Map<String, dynamic>>` should conform to the
  /// `AutoInputItem` schema expected by `SubmitAutoInputRequest`, e.g.:
  /// {
  ///   'type': 'image_url', // or 'text', 'input_audio'
  ///   'client_hash': '...',
  ///   'client_time': '2023-01-01 12:00:00',
  ///   'image_url': {
  ///     'filePath': '...',
  ///   }
  /// }
  Future<List<Map<String, dynamic>>> collect();
}
