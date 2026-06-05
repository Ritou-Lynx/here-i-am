import 'dart:async';

import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

final _log = getLogger('ModelTestService');

enum ModelTestType {
  text,
  vision,
}

class ModelTestResult {
  final bool success;
  final ModelTestType testType;
  final Duration responseTime;
  final String? responseText;
  final String? error;
  final String? model;

  const ModelTestResult({
    required this.success,
    required this.testType,
    required this.responseTime,
    this.responseText,
    this.error,
    this.model,
  });
}

class ModelTestService {
  // Minimal 64x64 PNG: a red circle on a white background.
  static const _testImageBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAA90lEQVR4nO3aOxKDUAxDU'
      'fa/6SRdJkVA8k+Phzy02PcMLcfr5nOoA7JjgHoMUI8B6ukHHL0nqrd/cpGn8GDRGqy7QZ'
      'JeEU4vYiReLklPM6KA8vqoIQRoqg8ZeEBrPW8gAQP1pIEBjNUzBhgwXA8bMICkHjM8AS'
      'CsBwzbA+T1VwYDlgbIuwGDAQYYsC1AXowZNv4CBhhggD46C1jHcBJowOKAFQzndQ8AaA'
      '2Xac8AqAxIFwqYN4BRBGDSgBdxgBkDlUMDug1sSwTQZwiEBAEdhlhFHFDIyNzPApKM/OX'
      '8it99Q93fg4W7/ly41/9C42OAegxQjwHqeQNx8d3ytD3rzgAAAABJRU5ErkJggg==';

  static Future<ModelTestResult> testConfig(
    LLMConfig config, {
    ModelTestType testType = ModelTestType.text,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      if (!config.isValid) {
        stopwatch.stop();
        return ModelTestResult(
          success: false,
          testType: testType,
          responseTime: stopwatch.elapsed,
          error: UserStorage.l10n.invalidConfigurationWarning,
        );
      }

      final resources = await UserStorage.buildLLMResources(config);
      final response = await resources.client
          .generate(
            _buildTestMessages(testType),
            modelConfig: resources.modelConfig,
          )
          .timeout(const Duration(seconds: 30));

      stopwatch.stop();
      final text = response.textOutput?.trim() ?? '';
      if (text.isEmpty) {
        return ModelTestResult(
          success: false,
          testType: testType,
          responseTime: stopwatch.elapsed,
          error: 'Empty response from model',
          model: response.model,
        );
      }

      _log.info(
        'Model test ($testType) success: ${config.type}/${config.modelId} '
        'in ${stopwatch.elapsedMilliseconds}ms',
      );
      return ModelTestResult(
        success: true,
        testType: testType,
        responseTime: stopwatch.elapsed,
        responseText: text.length > 150 ? '${text.substring(0, 150)}...' : text,
        model: response.model,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ModelTestResult(
        success: false,
        testType: testType,
        responseTime: stopwatch.elapsed,
        error: 'Request timed out (30s)',
      );
    } catch (e) {
      stopwatch.stop();
      _log.warning(
        'Model test ($testType) failed: ${config.type}/${config.modelId}: $e',
      );
      var error = e
          .toString()
          .replaceFirst('Exception: ', '')
          .replaceFirst('FormatException: ', '');
      if (error.length > 200) {
        error = '${error.substring(0, 200)}...';
      }
      return ModelTestResult(
        success: false,
        testType: testType,
        responseTime: stopwatch.elapsed,
        error: error,
      );
    }
  }

  static List<LLMMessage> _buildTestMessages(ModelTestType testType) {
    switch (testType) {
      case ModelTestType.text:
        return [
          SystemMessage(
            'You are a helpful assistant. Follow instructions precisely.',
          ),
          UserMessage([TextPart('Reply with "ok" only.')]),
        ];
      case ModelTestType.vision:
        return [
          SystemMessage('You are a vision assistant. Describe images briefly.'),
          UserMessage([
            TextPart('Describe this image in one short sentence.'),
            ImagePart(_testImageBase64, 'image/png'),
          ]),
        ];
    }
  }
}
