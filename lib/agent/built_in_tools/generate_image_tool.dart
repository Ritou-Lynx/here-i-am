import 'dart:convert';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/data/services/image_gen/image_gen_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';

/// Builds the `generate_image` tool for the companion agent.
///
/// When the user asks the character to create an image, the agent calls this
/// tool.  The generated image is attached as an addendum to a character message
/// and rendered inline in the chat via [ImageAddendumWidget].
Tool buildGenerateImageTool({required String characterId}) {
  return Tool(
    name: 'generate_image',
    description: '''Generate an AI image and send it as a message attachment.

Use this when the user asks you to draw, create, or generate an image / picture /
illustration / artwork.  This is for CREATING new images — NOT for searching the
web for existing images.

IMPORTANT — always write your spoken text reply BEFORE calling this tool.  The
generated image will appear as a separate message right after your text.

Parameters:
- prompt: A detailed image description in the user's language.  Describe the
  subject, setting, composition, colors, mood, lighting, and style.  For Chinese
  users, write the prompt in natural Chinese.
- style (optional): Visual style hint.  Examples: "photorealistic", "anime",
  "watercolor", "oil painting", "3D render", "pencil sketch".
- size (optional): "1024x1024" (square, default), "1792x1024" (landscape),
  "1024x1792" (portrait).''',
    parameters: {
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description':
              'Image generation prompt. Describe the image in detail. '
              'Write in the language the user is speaking.',
        },
        'style': {
          'type': 'string',
          'description':
              'Visual style. Examples: "photorealistic", "anime", '
              '"watercolor", "oil painting". Default: natural/realistic.',
        },
        'size': {
          'type': 'string',
          'enum': ['1024x1024', '1792x1024', '1024x1792'],
          'description': 'Image dimensions. Default: 1024x1024 (square).',
        },
      },
      'required': ['prompt'],
    },
    executable: (String prompt, [String? style, String? size]) async {
      try {
        if (prompt.trim().isEmpty) {
          return 'Error: prompt cannot be empty.';
        }

        debugPrint('[ImageGen] Tool called: prompt="$prompt" style=$style size=$size');
        final result = await ImageGenService.generateImage(
          prompt: prompt.trim(),
          style: style?.trim(),
          size: size?.trim() ?? '1024x1024',
        );
        debugPrint('[ImageGen] Tool result: ${result.images.length} image(s) from ${result.providerModel}');

        for (final bytes in result.images) {
          final base64 = base64Encode(bytes);
          debugPrint('[ImageGen] Storing image as character message (base64 ${base64.length} chars)');
          await PersonaChatService.instance.addCharacterMessage(
            characterId,
            '', // image-only message — text is the agent's spoken reply
            addenda: [
              {
                'type': 'image',
                'mimeType': 'image/png',
                'base64': base64,
              },
            ],
            isRead: true,
          );
        }

        return 'Image generated successfully. '
            '${result.images.length} image(s) attached. '
            'Model: ${result.providerModel}. '
            'Prompt: "$prompt"';
      } catch (e) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        debugPrint('[ImageGen] FAILED: $msg');
        return 'Error generating image: $msg';
      }
    },
  );
}
