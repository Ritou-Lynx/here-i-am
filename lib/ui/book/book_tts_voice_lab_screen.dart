import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:memex/data/services/book/book_tts_bakeoff_service.dart';
import 'package:memex/data/services/book/book_tts_melo_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _LabEngine { kokoro, melo }

class BookTtsVoiceLabScreen extends StatefulWidget {
  const BookTtsVoiceLabScreen({super.key});

  @override
  State<BookTtsVoiceLabScreen> createState() =>
      _BookTtsVoiceLabScreenState();
}

class _BookTtsVoiceLabScreenState extends State<BookTtsVoiceLabScreen> {
  static const _ratingsKey = 'book_tts_bakeoff_ratings_v1';
  static const _paper = Color(0xFFF4F1E8);
  static const _ink = Color(0xFF283127);
  static const _muted = Color(0xFF667063);
  static const _moss = Color(0xFF6E774A);

  final _service = BookTtsBakeoffService();
  final _melo = BookTtsMeloService();
  final _player = AudioPlayer();
  final Map<String, BookTtsVoiceRating> _ratings = {
    for (final candidate in BookTtsBakeoffService.candidates)
      candidate.label: const BookTtsVoiceRating(),
  };
  final Map<String, BookTtsSampleResult> _results = {};

  _LabEngine _engine = _LabEngine.kokoro;
  bool _checking = true;
  bool _modelReady = false;
  bool _installing = false;
  bool _generating = false;
  bool _revealed = false;
  double _installProgress = 0;
  double _speed = 1.0;
  String _installMessage = '';
  String? _activeLabel;
  String? _error;

  bool _meloReady = false;
  bool _meloInstalling = false;
  double _meloInstallProgress = 0;
  String _meloInstallMessage = '';
  BookTtsSampleResult? _meloResult;

  @override
  void initState() {
    super.initState();
    _initialize();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_ratingsKey);
    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            _ratings[entry.key] =
                BookTtsVoiceRating.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      } catch (_) {
        // A stale lab draft should never prevent the lab from opening.
      }
    }
    final ready = await _service.isModelReady();
    final meloReady = await _melo.isModelReady();
    if (!mounted) return;
    setState(() {
      _modelReady = ready;
      _meloReady = meloReady;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _installProgress = 0;
      _installMessage = '准备下载';
    });
    try {
      await _service.downloadAndPrepare(onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _installProgress = progress.value;
          _installMessage = progress.message;
        });
      });
      if (!mounted) return;
      setState(() => _modelReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _installMelo() async {
    setState(() {
      _meloInstalling = true;
      _error = null;
      _meloInstallProgress = 0;
      _meloInstallMessage = '准备下载';
    });
    try {
      await _melo.downloadAndPrepare(onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _meloInstallProgress = progress.value;
          _meloInstallMessage = progress.message;
        });
      });
      if (!mounted) return;
      setState(() => _meloReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _meloInstalling = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('HttpException') ||
        text.contains('TimeoutException') ||
        text.contains('ClientException')) {
      return '网络中断，下载没有完成。已下载的部分会保留，下次会自动从断点继续，不需要重新下载整个模型。请换一个稳定的网络后重试。';
    }
    return '没有完成：$text';
  }

  Future<void> _listen(BookTtsCandidate candidate) async {
    if (_generating || !_modelReady) return;
    if (_activeLabel == candidate.label && _player.playing) {
      await _player.pause();
      return;
    }
    final cached = _results[candidate.label];
    if (cached != null) {
      await _playResult(candidate.label, cached);
      return;
    }

    setState(() {
      _generating = true;
      _activeLabel = candidate.label;
      _error = null;
    });
    try {
      final result =
          await _service.generateSample(candidate: candidate, speed: _speed);
      _results[candidate.label] = result;
      await _playResult(candidate.label, result);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _playResult(String label, BookTtsSampleResult result) async {
    _activeLabel = label;
    await _player.setFilePath(result.audioPath);
    await _player.play();
    if (mounted) setState(() {});
  }

  Future<void> _listenMelo() async {
    if (_generating || !_meloReady) return;
    if (_meloResult != null && _player.playing) {
      await _player.pause();
      return;
    }
    setState(() {
      _generating = true;
      _activeLabel = 'M';
      _error = null;
    });
    try {
      final result = await _melo.generateSample(speed: _speed);
      _meloResult = result;
      await _playResult('M', result);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveRatings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _ratingsKey,
      jsonEncode({for (final e in _ratings.entries) e.key: e.value.toJson()}),
    );
  }

  Future<void> _export() async {
    final report = encodeBookTtsBakeoffReport(
      speed: _speed,
      ratings: _ratings,
      results: _results,
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('赛马结果已复制，可以直接发给我分析')),
    );
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地音色模型？'),
        content: Text(
          _engine == _LabEngine.kokoro
              ? '会释放约 215 MB 空间，评分会保留；下次试听需要重新下载。'
              : '会释放约 170 MB 空间；下次试听需要重新下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _player.stop();
    if (_engine == _LabEngine.kokoro) {
      await _service.deleteModelAndSamples();
      if (!mounted) return;
      setState(() {
        _modelReady = false;
        _results.clear();
        _activeLabel = null;
      });
    } else {
      await _melo.deleteModelAndSamples();
      if (!mounted) return;
      setState(() {
        _meloReady = false;
        _meloResult = null;
        _activeLabel = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        title: const Text('本地音色实验室'),
        backgroundColor: _paper,
        actions: [
          if ((_engine == _LabEngine.kokoro && _modelReady) ||
              (_engine == _LabEngine.melo && _meloReady))
            IconButton(
              tooltip: '管理本地模型',
              onPressed: _generating ? null : _deleteModel,
              icon: const Icon(Icons.storage_outlined),
            ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
              children: [
                _introCard(),
                const SizedBox(height: 14),
                _engineSelector(),
                const SizedBox(height: 14),
                if (_engine == _LabEngine.kokoro)
                  ..._kokoroContent()
                else
                  ..._meloContent(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _errorCard(_error!),
                ],
              ],
            ),
    );
  }

  List<Widget> _kokoroContent() {
    if (!_modelReady) return [_installCard()];
    return [
      _testTextCard(),
      const SizedBox(height: 14),
      _speedSelector(),
      const SizedBox(height: 18),
      for (final candidate in BookTtsBakeoffService.candidates) ...[
        _candidateCard(candidate),
        const SizedBox(height: 12),
      ],
      _finishCard(),
    ];
  }

  List<Widget> _meloContent() {
    if (!_meloReady) return [_meloInstallCard()];
    return [
      _testTextCard(),
      const SizedBox(height: 14),
      _speedSelector(),
      const SizedBox(height: 18),
      _meloListenCard(),
    ];
  }

  Widget _engineSelector() => Row(children: [
        Expanded(
          child: ChoiceChip(
            label: Text('Kokoro ${_modelReady ? '' : '（未下载）'}'),
            selected: _engine == _LabEngine.kokoro,
            onSelected: _generating
                ? null
                : (_) => setState(() {
                      _engine = _LabEngine.kokoro;
                      _error = null;
                      _activeLabel = null;
                    }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ChoiceChip(
            label: Text('MeloTTS ${_meloReady ? '' : '（未下载）'}'),
            selected: _engine == _LabEngine.melo,
            onSelected: _generating
                ? null
                : (_) => setState(() {
                      _engine = _LabEngine.melo;
                      _error = null;
                      _activeLabel = null;
                    }),
          ),
        ),
      ]);

  Widget _introCard() => _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('先听，再看名字',
                style: TextStyle(
                    color: _ink, fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(
            'Kokoro 赛马三种匿名中文女声，MeloTTS 是单音色对比组。同文同速，声音全在手机里生成，不上传书籍内容，也不产生按次费用。',
            style: TextStyle(color: _muted, height: 1.6),
          ),
          ],
        ),
      );

  Widget _installCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.download_for_offline_outlined, color: _moss),
              SizedBox(width: 9),
              Expanded(
                child: Text(BookTtsBakeoffService.modelName,
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              '首次需要联网下载，安装后约占 215 MB。下载、解压和校验可能需要几分钟；网络中断时会保留进度，下次自动从断点继续。',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (_installing) ...[
              LinearProgressIndicator(value: _installProgress, color: _moss),
              const SizedBox(height: 9),
              Text('$_installMessage · ${(_installProgress * 100).round()}%',
                  style: const TextStyle(color: _muted)),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('下载并安装本地模型'),
                ),
              ),
          ],
        ),
      );

  Widget _meloInstallCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.download_for_offline_outlined, color: _moss),
              SizedBox(width: 9),
              Expanded(
                child: Text(BookTtsMeloService.modelName,
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              '首次需要联网下载，安装后约占 170 MB。下载、解压和校验可能需要几分钟；网络中断时会保留进度，下次自动从断点继续。',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 16),
            if (_meloInstalling) ...[
              LinearProgressIndicator(value: _meloInstallProgress, color: _moss),
              const SizedBox(height: 9),
              Text('$_meloInstallMessage · ${(_meloInstallProgress * 100).round()}%',
                  style: const TextStyle(color: _muted)),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _installMelo,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('下载并安装本地模型'),
                ),
              ),
          ],
        ),
      );

  Widget _meloListenCard() {
    final result = _meloResult;
    final isGenerating = _generating && _activeLabel == 'M';
    final isPlaying = _activeLabel == 'M' && _player.playing;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(
              backgroundColor: _moss,
              foregroundColor: Colors.white,
              child: Text('M'),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('MeloTTS · 中英混读单音色',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            FilledButton.tonalIcon(
              onPressed: _generating ? null : _listenMelo,
              icon: isGenerating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow),
              label: Text(isGenerating
                  ? '生成中'
                  : isPlaying
                      ? '暂停'
                      : '试听'),
            ),
          ]),
          if (result != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 7, children: [
              _metric('首段 ${result.firstChunkMs} ms'),
              _metric('RTF ${result.realTimeFactor.toStringAsFixed(2)}'),
              _metric('冷启动 ${result.initMs} ms'),
              _metric('内存 +${(result.peakRssBytes / 1048576).round()} MB'),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _testTextCard() => _card(
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('统一测试段落',
                style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
            SizedBox(height: 9),
            Text(BookTtsBakeoffService.testText,
                style: TextStyle(color: _ink, height: 1.75, fontSize: 15)),
          ],
        ),
      );

  Widget _speedSelector() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('朗读速度',
              style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final speed in const [1.0, 1.25, 1.5])
                ChoiceChip(
                  label: Text('$speed×'),
                  selected: _speed == speed,
                  onSelected: _generating
                      ? null
                      : (_) async {
                          await _player.stop();
                          setState(() {
                            _speed = speed;
                            _results.clear();
                            _meloResult = null;
                            _activeLabel = null;
                          });
                        },
                ),
            ],
          ),
        ],
      );

  Widget _candidateCard(BookTtsCandidate candidate) {
    final rating = _ratings[candidate.label]!;
    final result = _results[candidate.label];
    final isActive = _activeLabel == candidate.label;
    final isPlaying = isActive && _player.playing;
    final isGenerating = isActive && _generating;
    return _card(
      borderColor: isActive ? _moss : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: _moss,
              foregroundColor: Colors.white,
              child: Text(candidate.label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _revealed
                    ? '音色 ${candidate.label} · 中文女声 ${candidate.speakerId}'
                    : '匿名音色 ${candidate.label}',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _generating ? null : () => _listen(candidate),
              icon: isGenerating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow),
              label: Text(isGenerating
                  ? '生成中'
                  : isPlaying
                      ? '暂停'
                      : '试听'),
            ),
          ]),
          if (result != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 7, children: [
              _metric('首段 ${result.firstChunkMs} ms'),
              _metric('RTF ${result.realTimeFactor.toStringAsFixed(2)}'),
              _metric('冷启动 ${result.initMs} ms'),
              _metric('内存 +${(result.peakRssBytes / 1048576).round()} MB'),
            ]),
          ],
          const Divider(height: 28),
          _scoreRow('自然度', rating.naturalness,
              (v) => rating.copyWith(naturalness: v), candidate.label),
          _scoreRow('情绪感', rating.emotion,
              (v) => rating.copyWith(emotion: v), candidate.label),
          _scoreRow('咬字', rating.pronunciation,
              (v) => rating.copyWith(pronunciation: v), candidate.label),
          _scoreRow('久听不累', rating.longListening,
              (v) => rating.copyWith(longListening: v), candidate.label),
          _scoreRow('对白表现', rating.dialogue,
              (v) => rating.copyWith(dialogue: v), candidate.label),
          Align(
            alignment: Alignment.centerRight,
            child: Text('平均 ${rating.average.toStringAsFixed(1)} / 5',
                style: const TextStyle(
                    color: _moss, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _scoreRow(
    String label,
    int score,
    BookTtsVoiceRating Function(int value) update,
    String candidateLabel,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 74, child: Text(label)),
          Expanded(
            child: Wrap(
              spacing: 5,
              alignment: WrapAlignment.end,
              children: [
                for (var value = 1; value <= 5; value++)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() => _ratings[candidateLabel] = update(value));
                      _saveRatings();
                    },
                    child: Container(
                      width: 31,
                      height: 31,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value <= score
                            ? _moss
                            : _moss.withValues(alpha: 0.10),
                      ),
                      child: Text('$value',
                          style: TextStyle(
                              color: value <= score ? Colors.white : _muted,
                              fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _finishCard() {
    final ranked = [...BookTtsBakeoffService.candidates]
      ..sort((a, b) => _ratings[b.label]!
          .average
          .compareTo(_ratings[a.label]!.average));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('完成这一轮',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(
            _revealed
                ? '当前领先：${ranked.first.label}（${_ratings[ranked.first.label]!.average.toStringAsFixed(1)} 分）'
                : '至少完整听过一次 A、B、C，再揭晓会更公平。',
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _revealed = !_revealed),
                child: Text(_revealed ? '重新隐藏' : '揭晓音色'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('复制结果'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _metric(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _moss.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text,
            style: const TextStyle(color: _muted, fontSize: 12)),
      );

  Widget _errorCard(String text) => _card(
        borderColor: const Color(0xFFC87663),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFA75042)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
        ]),
      );

  Widget _card({required Widget child, Color? borderColor}) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.9),
              width: borderColor == null ? 1 : 1.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D1D271C), blurRadius: 18, offset: Offset(0, 7)),
          ],
        ),
        child: child,
      );
}
