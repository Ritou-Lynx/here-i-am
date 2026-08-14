/// Stable asset reference for media blocks in a [RichTextDocument].
///
/// Images and attachments only save a stable asset reference — never a
/// temporary filesystem path or a large binary blob. The reference points to
/// content-addressed object storage (via [objectRef]) and carries enough
/// metadata (mime type, dimensions, alt text) to render without re-reading
/// the binary.
library;

/// A stable, serializable reference to a media asset inside a rich text doc.
class RichTextAssetRef {
  final String refId;
  final String objectRef;
  final String mimeType;
  final int? width;
  final int? height;
  final String? alt;
  final String? caption;

  const RichTextAssetRef({
    required this.refId,
    required this.objectRef,
    required this.mimeType,
    this.width,
    this.height,
    this.alt,
    this.caption,
  });

  factory RichTextAssetRef.fromJson(Map<String, dynamic> json) {
    return RichTextAssetRef(
      refId: json['ref_id'] as String,
      objectRef: json['object_ref'] as String,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      alt: json['alt'] as String?,
      caption: json['caption'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'ref_id': refId,
        'object_ref': objectRef,
        'mime_type': mimeType,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (alt != null) 'alt': alt,
        if (caption != null) 'caption': caption,
      };

  @override
  bool operator ==(Object other) =>
      other is RichTextAssetRef && other.refId == refId;

  @override
  int get hashCode => refId.hashCode;
}