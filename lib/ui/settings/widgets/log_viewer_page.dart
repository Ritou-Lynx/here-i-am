import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/file_logger_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  // Config
  bool _autoRefresh = true;
  int _lineCount = 500; // 100, 500, 1000, -1 (All)
  String _levelFilter = 'ALL'; // ALL, WARNING, SEVERE
  String _searchQuery = '';

  // State
  List<File> _logFiles = [];
  File? _selectedFile;
  final List<String> _logLines = [];
  Timer? _refreshTimer;
  int _currentFileOffset = 0;
  bool _isLoading = false;
  bool _isSearching = false;
  String? _loadError;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// Filters
  final List<int> _lineOptions = [100, 500, 1000, -1];
  final List<String> _levelOptions = ['ALL', 'WARNING', 'SEVERE'];

  @override
  void initState() {
    super.initState();
    _loadLogFiles();
    _startAutoRefresh();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_autoRefresh && _selectedFile != null && !_isLoading) {
        _checkAndLoadNewLogs();
      }
    });
  }

  Future<void> _loadLogFiles() async {
    setState(() => _isLoading = true);
    try {
      final files = await FileLoggerService.instance.getAllLogFiles();
      if (!mounted) return;

      // File's == is identity-based — re-reading the directory produces
      // fresh File instances whose paths match the existing _selectedFile
      // but are NOT == to it. Without remapping, the Dropdown sees
      // `value` not present in `items` and asserts. Re-bind _selectedFile
      // to the new instance by matching path.
      File? rebound;
      if (_selectedFile != null) {
        final selectedPath = _selectedFile!.path;
        for (final f in files) {
          if (f.path == selectedPath) {
            rebound = f;
            break;
          }
        }
      }

      // First-time pick: skip 0-byte files. Today's log can be empty when
      // the sink buffer hasn't been flushed since boot; falling back to
      // the most recent non-empty file is much friendlier than rendering
      // a blank screen.
      File? defaultPick;
      if (rebound == null && files.isNotEmpty) {
        for (final f in files) {
          try {
            if (await f.length() > 0) {
              defaultPick = f;
              break;
            }
          } catch (_) {
            // ignore file stat failure; try the next.
          }
        }
        defaultPick ??= files.first;
      }

      bool shouldLoadAfter = false;
      setState(() {
        _logFiles = files;
        if (rebound != null) {
          // Same file as before, just a fresh File handle.
          _selectedFile = rebound;
        } else if (defaultPick != null) {
          _selectedFile = defaultPick;
          shouldLoadAfter = true;
        } else {
          // No log files at all.
          _selectedFile = null;
          _isLoading = false;
        }
      });

      if (shouldLoadAfter) {
        await _loadLogs(isInitial: true);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error loading log files: $e');
    }
  }

  /// Initial load or full reload of the file
  Future<void> _loadLogs({bool isInitial = false}) async {
    if (_selectedFile == null) return;

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final file = _selectedFile!;
      if (!await file.exists()) {
        _logLines.clear();
        _currentFileOffset = 0;
        return;
      }

      // readAsLines() will throw on invalid UTF-8 bytes (and quietly
      // returns [] in some edge cases). Read raw bytes and decode with
      // allowMalformed:true so a stray bad byte doesn't blank the page.
      // Then split on any of \r\n, \n, \r so the splitter doesn't miss
      // platform-mixed line endings.
      final bytes = await file.readAsBytes();
      String decoded;
      try {
        decoded = utf8.decode(bytes, allowMalformed: true);
      } catch (e) {
        decoded = String.fromCharCodes(bytes);
      }
      final lines = decoded.split(RegExp(r'\r\n|\n|\r'));
      // The trailing empty element from a file ending in \n is noise.
      if (lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }
      _logLines.clear();
      _logLines.addAll(lines);
      _currentFileOffset = await file.length(); // Update offset to end of file

      setState(() {});

      // Scroll to bottom on initial load
      if (isInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading logs: $e\n$stack');
      _loadError = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Incremental load
  Future<void> _checkAndLoadNewLogs() async {
    if (_selectedFile == null) return;

    try {
      final file = _selectedFile!;
      if (!await file.exists()) return;

      final len = await file.length();
      if (len > _currentFileOffset) {
        // New content available
        final stream = file.openRead(_currentFileOffset, len);
        final newLines = await stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();

        if (newLines.isNotEmpty) {
          if (mounted) {
            setState(() {
              _logLines.addAll(newLines);
              _currentFileOffset = len;
            });
            // Auto-scroll to bottom if already at bottom
            if (_scrollController.hasClients) {
              final pos = _scrollController.position;
              if (pos.pixels >= pos.maxScrollExtent - 50) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                });
              }
            }
          }
        }
      } else if (len < _currentFileOffset) {
        // File truncated or rotated? Reload fully.
        _loadLogs();
      }
    } catch (e) {
      debugPrint('Error reading new logs: $e');
    }
  }

  List<String> _getFilteredLines() {
    List<String> lines = _logLines;

    // 1. Search Filter
    if (_searchQuery.isNotEmpty) {
      lines = lines
          .where(
              (line) => line.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // 2. Level Filter
    if (_levelFilter != 'ALL') {
      // If WARNING, include WARNING and SEVERE
      if (_levelFilter == 'WARNING') {
        lines = lines
            .where(
                (line) => line.contains('WARNING') || line.contains('SEVERE'))
            .toList();
      } else if (_levelFilter == 'SEVERE') {
        lines = lines.where((line) => line.contains('SEVERE')).toList();
      }
    }

    // 3. Line Count Limit
    // We modify the VIEW, not the source data (_logLines), so we can toggle back to ALL easily.
    if (_lineCount != -1 && lines.length > _lineCount) {
      lines = lines.sublist(lines.length - _lineCount);
    }

    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final filteredLines = _getFilteredLines();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: SpringRainUiTokens.daylightCanvas,
        surfaceTintColor: SpringRainUiTokens.daylightCanvas,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search logs...',
                  border: InputBorder.none,
                ),
                style: const TextStyle(color: SpringRainUiTokens.daylightTextPrimary),
              )
            : Text(UserStorage.l10n.logViewer),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: _buildLogFileSelector(),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildControlBar(filteredLines.length),
          Expanded(
            child: _isLoading && _logLines.isEmpty
                ? Center(child: AgentLogoLoading())
                : filteredLines.isEmpty
                    ? _buildEmptyPlaceholder()
                    : SelectionArea(
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          radius: const Radius.circular(4),
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(8),
                            itemCount: filteredLines.length,
                            itemBuilder: (context, index) {
                              final line = filteredLines[index];
                              return Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'Courier',
                                  fontSize: 12,
                                  color: _getLineColor(line),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'scroll_up',
            mini: true,
            onPressed: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            child: const Icon(Icons.arrow_upward),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'scroll_down',
            mini: true,
            onPressed: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            child: const Icon(Icons.arrow_downward),
          ),
        ],
      ),
    );
  }

  /// Diagnostic placeholder when there's nothing to show — pre-fix, this
  /// page rendered a blank screen and made it look broken. Now it tells
  /// you whether the log directory exists, what its path is, how many
  /// files were found, and gives you a button to write a probe line so
  /// you can confirm the write-pipe end-to-end.
  Widget _buildEmptyPlaceholder() {
    final logDir = FileLoggerService.instance.getLogDirectoryPath();
    final hasFiles = _logFiles.isNotEmpty;
    final reason = !hasFiles
        ? '日志目录中还没有 .log 文件'
        : '当前选中的文件没有匹配的内容（可能是过滤器或文件刚被创建）';
    final diag = FileLoggerService.instance.diagnosticSnapshot();
    final selectedName = _selectedFile?.path.split('/').last;
    final fileSizes = <File, int>{};
    for (final f in _logFiles) {
      try {
        fileSizes[f] = f.lengthSync();
      } catch (_) {
        fileSizes[f] = -1;
      }
    }
    final selectedSize =
        _selectedFile == null ? null : fileSizes[_selectedFile];
    final mostRecentNonEmpty = _logFiles.firstWhere(
      (f) => (fileSizes[f] ?? 0) > 0,
      orElse: () => _logFiles.isNotEmpty ? _logFiles.first : File(''),
    );
    final canJumpToNonEmpty = _logFiles.isNotEmpty &&
        mostRecentNonEmpty.path.isNotEmpty &&
        mostRecentNonEmpty.path != _selectedFile?.path;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.description_outlined,
              size: 48, color: SpringRainUiTokens.daylightIconMuted),
          const SizedBox(height: 16),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: SpringRainUiTokens.daylightTextSecondary),
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SpringRainUiTokens.daylightErrorSoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SpringRainUiTokens.daylightError),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '读取错误：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SpringRainUiTokens.daylightError,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _loadError!,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      color: SpringRainUiTokens.daylightError,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (logDir != null) ...[
            const Text(
              '日志目录：',
              style: TextStyle(fontSize: 12, color: SpringRainUiTokens.daylightTextTertiary),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: logDir));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制日志目录路径'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: SpringRainUiTokens.daylightSurfaceMuted,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: SpringRainUiTokens.daylightDivider),
                ),
                child: Text(
                  logDir,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 11,
                    color: SpringRainUiTokens.daylightTextPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点击复制路径 · 已找到 ${_logFiles.length} 个文件',
              style: const TextStyle(
                fontSize: 11,
                color: SpringRainUiTokens.daylightTextTertiary,
              ),
            ),
          ] else
            const Text(
              '日志目录尚未初始化（FileLoggerService.initialize 可能失败）',
              style: TextStyle(fontSize: 12, color: SpringRainUiTokens.daylightError),
              textAlign: TextAlign.center,
            ),
          if (selectedName != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SpringRainUiTokens.daylightWarningSoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SpringRainUiTokens.daylightWarning),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前选中：$selectedName',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: SpringRainUiTokens.daylightWarning,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '文件大小：${selectedSize ?? '未知'} 字节',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      color: SpringRainUiTokens.daylightWarning,
                    ),
                  ),
                  if (canJumpToNonEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '检测到 ${mostRecentNonEmpty.path.split('/').last} '
                      '(${fileSizes[mostRecentNonEmpty]} 字节) 有内容',
                      style: const TextStyle(
                        fontSize: 11,
                        color: SpringRainUiTokens.daylightWarning,
                      ),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: const Text('切换到这个文件',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _selectedFile = mostRecentNonEmpty;
                          _logLines.clear();
                          _currentFileOffset = 0;
                        });
                        _loadLogs(isInitial: true);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Service-level diagnostics. If you're staring at this because
          // logs are empty, these counters tell you whether the issue is
          // (a) initialize failed, (b) Logger.root listener never fires,
          // or (c) the sink is failing to write.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: SpringRainUiTokens.daylightSurfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SpringRainUiTokens.daylightDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'FileLoggerService 诊断',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SpringRainUiTokens.daylightTextSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                _diagLine('initialize 调用过', diag['initialize_called']),
                _diagLine('initialize 成功', diag['initialize_succeeded']),
                if (diag['initialize_error'] != null)
                  _diagLine('init 错误', diag['initialize_error']),
                _diagLine('sink 已打开', diag['sink_open']),
                _diagLine('当前 sink 日期', diag['current_sink_date']),
                _diagLine('写入尝试次数', diag['write_attempts']),
                _diagLine('写入成功次数', diag['write_successes']),
                _diagLine('最后成功时间', diag['last_success_time']),
                if (diag['last_write_error'] != null)
                  _diagLine('最近写入错误', diag['last_write_error']),
                const Divider(height: 16),
                _diagLine('UI _logLines 行数', _logLines.length),
                _diagLine('UI _isLoading', _isLoading),
                _diagLine('UI 过滤后行数', _getFilteredLines().length),
                _diagLine('UI _lineCount 上限', _lineCount),
                _diagLine('UI _levelFilter', _levelFilter),
                _diagLine('UI _searchQuery',
                    _searchQuery.isEmpty ? '(空)' : _searchQuery),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('通过 Logger 写'),
                  onPressed: () async {
                    Logger('LogViewerProbe').info(
                        'Probe entry at ${DateTime.now().toIso8601String()}');
                    await Future.delayed(const Duration(milliseconds: 800));
                    await _loadLogFiles();
                    if (_selectedFile != null) {
                      await _loadLogs(isInitial: true);
                    }
                    if (!mounted) return;
                    setState(() {}); // refresh diag panel
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已通过 Logger.root 写入'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('绕过 Logger 直写'),
                  onPressed: () async {
                    final ok = await FileLoggerService.instance
                        .writeDirectProbe(
                      'DirectProbe at ${DateTime.now().toIso8601String()}',
                    );
                    await Future.delayed(const Duration(milliseconds: 200));
                    await _loadLogFiles();
                    if (_selectedFile != null) {
                      await _loadLogs(isInitial: true);
                    }
                    if (!mounted) return;
                    setState(() {}); // refresh diag panel
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            ok ? '直写成功' : '直写失败，看上面诊断'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diagLine(String key, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 11,
                color: SpringRainUiTokens.daylightTextTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                color: value == null
                    ? SpringRainUiTokens.daylightIconMuted
                    : (value == false
                        ? SpringRainUiTokens.daylightError
                        : SpringRainUiTokens.daylightTextPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLineColor(String line) {
    if (line.contains('SEVERE')) return SpringRainUiTokens.daylightError;
    if (line.contains('WARNING')) return SpringRainUiTokens.daylightWarning;
    return SpringRainUiTokens.daylightTextPrimary;
  }

  Widget _buildLogFileSelector() {
    if (_logFiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButton<File>(
      value: _selectedFile,
      underline: const SizedBox(),
      style: const TextStyle(color: SpringRainUiTokens.daylightTextPrimary, fontSize: 14),
      dropdownColor: SpringRainUiTokens.daylightSurface,
      items: _logFiles.map((file) {
        final name = file.path.split('/').last;
        return DropdownMenuItem(
          value: file,
          child: Text(name),
        );
      }).toList(),
      onChanged: (File? newValue) {
        if (newValue != null && newValue != _selectedFile) {
          setState(() {
            _selectedFile = newValue;
            _logLines.clear();
            _currentFileOffset = 0;
          });
          _loadLogs(isInitial: true);
        }
      },
    );
  }

  Widget _buildControlBar(int currentCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: SpringRainUiTokens.daylightSurfaceMuted,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Auto Refresh
            Row(
              children: [
                Text(UserStorage.l10n.autoRefresh,
                    style: const TextStyle(fontSize: 12)),
                Switch(
                  value: _autoRefresh,
                  onChanged: (val) => setState(() => _autoRefresh = val),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(width: 16),

            // Line Count
            Row(
              children: [
                Text(UserStorage.l10n.lineCount,
                    style: const TextStyle(fontSize: 12)),
                DropdownButton<int>(
                  value: _lineCount,
                  isDense: true,
                  underline: const SizedBox(),
                  items: _lineOptions.map((n) {
                    return DropdownMenuItem(
                      value: n,
                      child: Text(n == -1 ? UserStorage.l10n.all : '$n'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _lineCount = val);
                  },
                ),
              ],
            ),
            const SizedBox(width: 16),

            // Level
            Row(
              children: [
                const Text('Level: ', style: TextStyle(fontSize: 12)),
                DropdownButton<String>(
                  value: _levelFilter,
                  isDense: true,
                  underline: const SizedBox(),
                  items: _levelOptions
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _levelFilter = val);
                  },
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Probe button — always visible (even when the log view has
            // content), so the user can drop a marker to verify the
            // write pipe and find their place in the stream.
            OutlinedButton.icon(
              icon: const Icon(Icons.bolt, size: 14),
              label: const Text('写测试日志', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              ),
              onPressed: () async {
                Logger('LogViewerProbe').info(
                    'Probe entry at ${DateTime.now().toIso8601String()}');
                await Future.delayed(const Duration(milliseconds: 800));
                await _loadLogFiles();
                if (_selectedFile != null) {
                  await _loadLogs(isInitial: true);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已写入测试日志，已刷新文件'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
