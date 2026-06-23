/// Lightweight model that carries a saved-on-disk media asset and its AI
/// analysis through the Record Organizer pipeline.
///
/// Each instance represents one image/audio/video attachment that has been
/// persisted to the filesystem and (optionally) analyzed by a vision/audio
/// model.  Entries with a non-null [error] are skipped when feeding media
/// context to the Record Organizer LLM.
class MediaInputAttachment {
  const MediaInputAttachment({
    this.savedRelativePath,
    this.analysisText,
    this.error,
    this.kind = 'image',
  });

  /// Relative path under the workspace data root, e.g.
  /// `Facts/assets/img_20260623_ts_1719123456_no_1.webp`.
  final String? savedRelativePath;

  /// Cleaned analysis text from [AssetAnalysisTool], or null when analysis
  /// failed / was skipped.
  final String? analysisText;

  /// When non-null, save or analysis failed with this message.  Attachments
  /// with errors are excluded from the LLM media context.
  final String? error;

  /// `"image"` (default), `"audio"`, or `"video"`.
  final String kind;

  bool get isUsable => savedRelativePath != null && error == null;
}
