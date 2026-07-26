import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:memex/data/services/asr/alibaba_nls_token_cache.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Alibaba Cloud NLS real-time streaming ASR client.
///
/// Connects to the NLS gateway via WebSocket, streams PCM audio chunks, and
/// emits sentence-level events driven by server-side VAD. The NLS server VAD
/// is far more robust at distinguishing speech from background noise than the
/// amplitude-based endpoint detection previously used in [VoiceInputController],
/// and [SentenceBeginEvent]s enable barge-in while TTS is playing.
///
/// Protocol reference:
/// https://help.aliyun.com/zh/isi/developer-reference/websocket
///
/// ```
/// client -> server: StartTranscription (text frame, JSON)
/// server -> client: TranscriptionStarted
/// client -> server: binary PCM chunks (16kHz mono 16-bit LE)
/// server -> client: SentenceBegin / TranscriptionResultChanged / SentenceEnd
/// client -> server: StopTranscription
/// server -> client: TranscriptionCompleted
/// ```
class AlibabaStreamingAsrClient {
  static final Logger _logger = getLogger('AlibabaStreamingAsrClient');

  static const String _gatewayWsEndpoint =
      'wss://nls-gateway-cn-shanghai.aliyuncs.com/ws/v1';

  final AsrConfig config;

  final String _taskId;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  Completer<void>? _startCompleter;
  Completer<void>? _stopCompleter;
  bool _stopped = false;
  bool _disposed = false;

  StreamController<StreamingAsrEvent>? _eventController;

  AlibabaStreamingAsrClient(this.config) : _taskId = _generateTaskId();

  /// Connect to the gateway, send [StartTranscription], and return a stream
  /// of [StreamingAsrEvent]s. Audio chunks can be sent via [sendAudio] after
  /// the returned future completes.
  Future<Stream<StreamingAsrEvent>> start() async {
    if (_disposed) {
      throw StateError('AlibabaStreamingAsrClient already disposed');
    }
    if (_ws != null) {
      throw StateError('Already started');
    }

    final token = await AlibabaNlsTokenCache.ensureToken(config);
    final uri = Uri.parse('$_gatewayWsEndpoint?token=$token');
    _logger.info('Connecting to NLS streaming gateway');
    _ws = WebSocketChannel.connect(uri);
    _eventController = StreamController<StreamingAsrEvent>.broadcast();
    _startCompleter = Completer<void>();

    _wsSub = _ws!.stream.listen(
      _onData,
      onError: (Object e, StackTrace st) {
        _logger.warning('NLS WS error: $e');
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.completeError(e, st);
        }
        _eventController?.addError(e, st);
      },
      onDone: () {
        _logger.info('NLS WS closed');
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.completeError(
            AsrException('NLS WebSocket closed before TranscriptionStarted'),
          );
        }
        if (!(_stopCompleter?.isCompleted ?? true)) {
          _stopCompleter!.complete();
        }
        _eventController?.close();
      },
      cancelOnError: true,
    );

    _sendStartTranscription();
    await _startCompleter!.future;
    _logger.info('NLS streaming session started (taskId=$_taskId)');
    return _eventController!.stream;
  }

  void _sendStartTranscription() {
    final messageId = _generateTaskId();
    final msg = {
      'header': {
        'message_id': messageId,
        'task_id': _taskId,
        'namespace': 'SpeechTranscriber',
        'name': 'StartTranscription',
        'appkey': config.appKey,
      },
      'payload': {
        'format': 'pcm',
        'sample_rate': 16000,
        'enable_intermediate_result': true,
        'enable_punctuation_prediction': true,
        'enable_inverse_text_normalization': true,
        'max_sentence_silence': 800,
        'speech_noise_threshold': -0.5,
      },
      'context': {
        'sdk': {
          'name': 'memex-flutter',
          'version': '1.0.0',
        },
      },
    };
    _ws!.sink.add(jsonEncode(msg));
    _logger.fine('Sent StartTranscription (message_id=$messageId)');
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (e) {
      _logger.warning('NLS WS non-JSON text frame: $e');
      return;
    }
    final header = msg['header'] as Map<String, dynamic>?;
    if (header == null) return;
    final name = header['name'] as String?;
    final status = header['status'] as int?;
    _logger.fine('NLS event: $name status=$status');

    switch (name) {
      case 'TranscriptionStarted':
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.complete();
        }
        break;
      case 'SentenceBegin':
        final payload = msg['payload'] as Map<String, dynamic>?;
        final index = payload?['index'] as int? ?? 0;
        final time = payload?['time'] as int? ?? 0;
        _eventController?.add(SentenceBeginEvent(index: index, timeMs: time));
        break;
      case 'TranscriptionResultChanged':
        final payload = msg['payload'] as Map<String, dynamic>?;
        final index = payload?['index'] as int? ?? 0;
        final result = payload?['result'] as String? ?? '';
        _eventController?.add(
          TranscriptionResultChangedEvent(index: index, text: result),
        );
        break;
      case 'SentenceEnd':
        final payload = msg['payload'] as Map<String, dynamic>?;
        final index = payload?['index'] as int? ?? 0;
        final result = payload?['result'] as String? ?? '';
        final confidence = payload?['confidence'] as double?;
        _eventController?.add(
          SentenceEndEvent(index: index, text: result, confidence: confidence),
        );
        break;
      case 'TranscriptionCompleted':
        if (!(_stopCompleter?.isCompleted ?? true)) {
          _stopCompleter!.complete();
        }
        _eventController?.close();
        break;
      case 'TaskFailed':
        final message = header['status_message'] as String? ?? 'unknown';
        _logger.severe('NLS TaskFailed: status=$status message=$message');
        final err = AsrException('NLS TaskFailed: $status $message');
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.completeError(err);
        }
        _eventController?.addError(err);
        break;
      default:
        _logger.fine('NLS unhandled event: $name');
    }
  }

  /// Send a PCM audio chunk (16kHz, mono, 16-bit LE) to the server as a binary
  /// WebSocket frame. Must be called after [start] completes.
  void sendAudio(Uint8List pcmBytes) {
    if (_ws == null || _stopped || _disposed) return;
    _ws!.sink.add(pcmBytes);
  }

  /// Send [StopTranscription] and wait for [TranscriptionCompleted]. Safe to
  /// call multiple times; subsequent calls are no-ops.
  Future<void> stop() async {
    if (_ws == null || _stopped) return;
    _stopped = true;
    _stopCompleter = Completer<void>();
    final msg = {
      'header': {
        'message_id': _generateTaskId(),
        'task_id': _taskId,
        'namespace': 'SpeechTranscriber',
        'name': 'StopTranscription',
        'appkey': config.appKey,
      },
    };
    try {
      _ws!.sink.add(jsonEncode(msg));
    } catch (e) {
      _logger.warning('Failed to send StopTranscription: $e');
    }
    await _stopCompleter!.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _logger.warning('StopTranscription timed out');
      },
    );
  }

  /// Immediately tear down the WebSocket without the graceful stop handshake.
  /// Use when the caller needs to abort (e.g. user hung up mid-session).
  Future<void> dispose() async {
    _disposed = true;
    _stopped = true;
    try {
      await _wsSub?.cancel();
    } catch (e) {
      _logger.warning('WS sub cancel error: $e');
    }
    try {
      await _ws?.sink.close();
    } catch (e) {
      _logger.warning('WS close error: $e');
    }
    _ws = null;
    _wsSub = null;
    if (!(_startCompleter?.isCompleted ?? true)) {
      _startCompleter!.completeError(StateError('Disposed before started'));
    }
    if (!(_stopCompleter?.isCompleted ?? true)) {
      _stopCompleter!.complete();
    }
    if (_eventController != null && !_eventController!.isClosed) {
      _eventController!.close();
    }
    _eventController = null;
    _logger.info('NLS streaming session disposed (taskId=$_taskId)');
  }

  static String _generateTaskId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Events emitted by [AlibabaStreamingAsrClient.start].
sealed class StreamingAsrEvent {
  const StreamingAsrEvent();
}

/// Server-side VAD detected the start of a spoken sentence.
class SentenceBeginEvent extends StreamingAsrEvent {
  final int index;
  final int timeMs;
  const SentenceBeginEvent({required this.index, required this.timeMs});
}

/// Intermediate recognition result for the current sentence (not yet final).
class TranscriptionResultChangedEvent extends StreamingAsrEvent {
  final int index;
  final String text;
  const TranscriptionResultChangedEvent({
    required this.index,
    required this.text,
  });
}

/// Server-side VAD detected the end of a sentence, with the final text.
class SentenceEndEvent extends StreamingAsrEvent {
  final int index;
  final String text;
  final double? confidence;
  const SentenceEndEvent({
    required this.index,
    required this.text,
    this.confidence,
  });
}
