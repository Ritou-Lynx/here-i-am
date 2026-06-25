import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/data/services/image_gen/minimax_image_service.dart';
import 'package:memex/data/services/image_gen/tongyi_wanxiang_image_service.dart';
import 'package:memex/utils/user_storage.dart';

/// Mirrors the [TtsService] pattern: route to the configured provider.
class ImageGenService {
  ImageGenService._();

  static Future<ImageGenerationResult> generateImage({
    required String prompt,
    String? negativePrompt,
    String size = '1024x1024',
    String? style,
    int numImages = 1,
  }) async {
    final providerStr = await UserStorage.getImageGenProvider();
    final provider = ImageGenProvider.fromString(providerStr);
    final request = ImageGenerationRequest(
      prompt: prompt,
      negativePrompt: negativePrompt,
      size: size,
      style: style,
      numImages: numImages,
    );

    switch (provider) {
      case ImageGenProvider.minimax:
        return MiniMaxImageService.generate(request);
      case ImageGenProvider.tongyiWanxiang:
        return TongyiWanxiangImageService.generate(request);
    }
  }
}
