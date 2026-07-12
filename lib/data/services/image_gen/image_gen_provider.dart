import 'dart:typed_data';

/// Supported image generation providers.
enum ImageGenProvider {
  tongyiWanxiang,
  minimax,
  openaiCompatible;

  static ImageGenProvider fromString(String value) {
    switch (value) {
      case 'minimax':
        return ImageGenProvider.minimax;
      case 'openai_compatible':
        return ImageGenProvider.openaiCompatible;
      default:
        return ImageGenProvider.tongyiWanxiang;
    }
  }

  String get storageKey {
    switch (this) {
      case ImageGenProvider.tongyiWanxiang:
        return 'tongyi_wanxiang';
      case ImageGenProvider.minimax:
        return 'minimax';
      case ImageGenProvider.openaiCompatible:
        return 'openai_compatible';
    }
  }

  String get displayName {
    switch (this) {
      case ImageGenProvider.tongyiWanxiang:
        return '通义万相 (Aliyun)';
      case ImageGenProvider.minimax:
        return 'MiniMax';
      case ImageGenProvider.openaiCompatible:
        return '自定义 (OpenAI 兼容)';
    }
  }
}

class ImageGenerationRequest {
  const ImageGenerationRequest({
    required this.prompt,
    this.negativePrompt,
    this.size = '1024x1024',
    this.style,
    this.numImages = 1,
  });

  final String prompt;
  final String? negativePrompt;
  final String size;
  final String? style;
  final int numImages;
}

class ImageGenerationResult {
  const ImageGenerationResult({
    required this.images,
    this.revisedPrompt,
    required this.providerModel,
  });

  final List<Uint8List> images;
  final String? revisedPrompt;
  final String providerModel;
}
