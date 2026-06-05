import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/ui/settings/widgets/agent_config_list_page.dart';
import 'package:memex/ui/settings/widgets/model_config_list_page.dart';
import 'package:memex/ui/settings/widgets/system_authorization_page.dart';
import 'package:memex/ui/settings/widgets/debug_settings_page.dart';
import 'package:memex/ui/settings/widgets/settings_page.dart';
import 'package:memex/utils/permission_utils.dart';
import 'package:memex/ui/core/widgets/avatar_picker.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Personal center screen
class PersonalCenterScreen extends StatefulWidget {
  const PersonalCenterScreen({super.key});

  @override
  State<PersonalCenterScreen> createState() => _PersonalCenterScreenState();
}

class _PersonalCenterScreenState extends State<PersonalCenterScreen> {
  final MemexRouter _memexRouter = MemexRouter();
  final Logger _logger = getLogger('PersonalCenterScreen');
  String? _userId;
  String? _userEmail;

  bool _isReprocessingCards = false;
  bool _isReprocessingComments = false;
  bool _isReprocessingKnowledgeBase = false;
  bool _isRebuildingSearchIndex = false;
  bool _showAuthBadge = false;
  String? _userAvatar;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _checkPermissionBadge();
  }

  Future<void> _checkPermissionBadge() async {
    final granted = await PermissionUtils.isFitnessPermissionGranted();
    if (mounted) {
      setState(() => _showAuthBadge = !granted);
    }
  }

  Future<void> _loadUserInfo() async {
    final userId = await UserStorage.getUserId();
    final avatar = await _memexRouter.getUserAvatar();
    if (mounted) {
      setState(() {
        _userId = userId ?? UserStorage.l10n.notSet;
        _userEmail = userId != null ? '$userId@memex.local' : null;
        _userAvatar = avatar;
      });
    }
  }

  Future<void> _changeAvatar() async {
    final picked = await showAvatarPicker(
      context,
      _userAvatar ?? UserStorage.defaultAvatarSeed,
      onPickGallery: _pickUserAvatarFromGallery,
    );
    if (picked != null && mounted) {
      await _memexRouter.updateUserAvatar(picked);
      final resolvedAvatar = await _memexRouter.getUserAvatar();
      if (!mounted) return;
      setState(() => _userAvatar = resolvedAvatar);
    }
  }

  Future<String?> _pickUserAvatarFromGallery() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;

    final pickedPath = await pickAvatarImageFromGallery();
    if (pickedPath == null) return null;

    final imported = await MediaService.instance.importImage(
      userId: userId,
      sourcePath: pickedPath,
    );
    return imported.relativePath;
  }

  Future<void> _clearToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.confirmClear),
        content: Text(UserStorage.l10n.confirmClearTokenMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(UserStorage.l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await UserStorage.clearUser();
        // Reset user-related globals so next login re-inits (DB, router, task executor).
        _memexRouter.resetForLogout();
        if (mounted) {
          ToastHelper.showSuccessWithKey(
            _scaffoldMessengerKey,
            UserStorage.l10n.tokenCleared,
          );
          // navigate to setup screen
          context.go(AppRoutes.userSetup);
        }
      } catch (e) {
        if (mounted) {
          ToastHelper.showErrorWithKey(
            _scaffoldMessengerKey,
            UserStorage.l10n.clearTokenFailed(e.toString()),
          );
        }
      }
    }
  }

  Future<void> _reprocessCards() async {
    if (_isReprocessingCards) return;

    // show dialog for user to choose params
    DateTime? dateFrom;
    DateTime? dateTo;
    int? limit;
    var reanalyzeAssets = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UserStorage.l10n.reprocessCards),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UserStorage.l10n.selectDateRangeOptional),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(UserStorage.l10n.startDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateFrom = date;
                        });
                      }
                    },
                    child: Text(
                      dateFrom == null
                          ? UserStorage.l10n.select
                          : '${dateFrom!.year}-${dateFrom!.month.toString().padLeft(2, '0')}-${dateFrom!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                ListTile(
                  title: Text(UserStorage.l10n.endDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dateTo ?? DateTime.now(),
                        firstDate: dateFrom ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateTo = date;
                        });
                      }
                    },
                    child: Text(
                      dateTo == null
                          ? UserStorage.l10n.select
                          : '${dateTo!.year}-${dateTo!.month.toString().padLeft(2, '0')}-${dateTo!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: UserStorage.l10n.processLimitOptional,
                    hintText: UserStorage.l10n.leaveEmptyForAll,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    limit = int.tryParse(value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reanalyzeAssets,
                  title: Text(
                    UserStorage.l10n.reanalyzeMediaAssets,
                  ),
                  subtitle: Text(
                    UserStorage.l10n.reanalyzeMediaAssetsDesc,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      reanalyzeAssets = value;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UserStorage.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UserStorage.l10n.startProcessing),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isReprocessingCards = true;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isReprocessingCards = false;
          });
          ToastHelper.showErrorWithKey(
            _scaffoldMessengerKey,
            UserStorage.l10n.userIdNotFound,
          );
        }
        return;
      }

      // build payload
      final payload = <String, dynamic>{};
      final dateFromValue = dateFrom;
      if (dateFromValue != null) {
        payload['date_from'] = dateFromValue.toIso8601String().substring(0, 10);
      }
      final dateToValue = dateTo;
      if (dateToValue != null) {
        payload['date_to'] = dateToValue.toIso8601String().substring(0, 10);
      }
      final limitValue = limit;
      if (limitValue != null && limitValue > 0) {
        payload['limit'] = limitValue;
      }
      if (reanalyzeAssets) {
        payload['reanalyze_assets'] = true;
      }

      // enqueue task
      await _memexRouter.enqueueTask(
        taskType: 'reprocess_cards_task',
        payload: payload,
        bizId: 'reprocess_cards_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        setState(() {
          _isReprocessingCards = false;
        });
        ToastHelper.showSuccessWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.reprocessCardsTaskCreated,
        );
      }
    } catch (e) {
      _logger.severe('Error reprocessing cards: $e', e);
      if (mounted) {
        setState(() {
          _isReprocessingCards = false;
        });
        ToastHelper.showErrorWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.createTaskFailed(e),
        );
      }
    }
  }

  Future<void> _reprocessComments() async {
    if (_isReprocessingComments) return;

    // show dialog for user to choose params
    DateTime? dateFrom;
    DateTime? dateTo;
    int? limit;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UserStorage.l10n.regenerateComments),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UserStorage.l10n.selectDateRangeOptional),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(UserStorage.l10n.startDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateFrom = date;
                        });
                      }
                    },
                    child: Text(
                      dateFrom == null
                          ? UserStorage.l10n.select
                          : '${dateFrom!.year}-${dateFrom!.month.toString().padLeft(2, '0')}-${dateFrom!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                ListTile(
                  title: Text(UserStorage.l10n.endDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dateTo ?? DateTime.now(),
                        firstDate: dateFrom ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateTo = date;
                        });
                      }
                    },
                    child: Text(
                      dateTo == null
                          ? UserStorage.l10n.select
                          : '${dateTo!.year}-${dateTo!.month.toString().padLeft(2, '0')}-${dateTo!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: UserStorage.l10n.processLimitOptional,
                    hintText: UserStorage.l10n.leaveEmptyForAll,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    limit = int.tryParse(value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UserStorage.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UserStorage.l10n.startProcessing),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isReprocessingComments = true;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isReprocessingComments = false;
          });
          ToastHelper.showErrorWithKey(
            _scaffoldMessengerKey,
            UserStorage.l10n.userIdNotFound,
          );
        }
        return;
      }

      // build payload
      final payload = <String, dynamic>{};
      final dateFromValue = dateFrom;
      if (dateFromValue != null) {
        payload['date_from'] = dateFromValue.toIso8601String().substring(0, 10);
      }
      final dateToValue = dateTo;
      if (dateToValue != null) {
        payload['date_to'] = dateToValue.toIso8601String().substring(0, 10);
      }
      final limitValue = limit;
      if (limitValue != null && limitValue > 0) {
        payload['limit'] = limitValue;
      }

      // enqueue task
      await _memexRouter.enqueueTask(
        taskType: 'reprocess_comments_task',
        payload: payload,
        bizId: 'reprocess_comments_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        setState(() {
          _isReprocessingComments = false;
        });
        ToastHelper.showSuccessWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.regenerateCommentsTaskCreated,
        );
      }
    } catch (e) {
      _logger.severe('Error reprocessing comments: $e', e);
      if (mounted) {
        setState(() {
          _isReprocessingComments = false;
        });
        ToastHelper.showErrorWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.createTaskFailed(e),
        );
      }
    }
  }

  Future<void> _reprocessKnowledgeBase() async {
    if (_isReprocessingKnowledgeBase) return;

    // show dialog for user to choose params
    DateTime? dateFrom;
    DateTime? dateTo;
    int? limit;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(UserStorage.l10n.reprocessKnowledgeBase),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UserStorage.l10n.selectDateRangeOptional),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(UserStorage.l10n.startDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateFrom = date;
                        });
                      }
                    },
                    child: Text(
                      dateFrom == null
                          ? UserStorage.l10n.select
                          : '${dateFrom!.year}-${dateFrom!.month.toString().padLeft(2, '0')}-${dateFrom!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                ListTile(
                  title: Text(UserStorage.l10n.endDate),
                  trailing: TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: dateTo ?? DateTime.now(),
                        firstDate: dateFrom ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setDialogState(() {
                          dateTo = date;
                        });
                      }
                    },
                    child: Text(
                      dateTo == null
                          ? UserStorage.l10n.select
                          : '${dateTo!.year}-${dateTo!.month.toString().padLeft(2, '0')}-${dateTo!.day.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: UserStorage.l10n.processLimitOptional,
                    hintText: UserStorage.l10n.leaveEmptyForAll,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    limit = int.tryParse(value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UserStorage.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(UserStorage.l10n.startProcessing),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isReprocessingKnowledgeBase = true;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) {
          setState(() {
            _isReprocessingKnowledgeBase = false;
          });
          ToastHelper.showErrorWithKey(
            _scaffoldMessengerKey,
            UserStorage.l10n.userIdNotFound,
          );
        }
        return;
      }

      // build payload
      final payload = <String, dynamic>{};
      final dateFromValue = dateFrom;
      if (dateFromValue != null) {
        payload['date_from'] = dateFromValue.toIso8601String().substring(0, 10);
      }
      final dateToValue = dateTo;
      if (dateToValue != null) {
        payload['date_to'] = dateToValue.toIso8601String().substring(0, 10);
      }
      final limitValue = limit;
      if (limitValue != null && limitValue > 0) {
        payload['limit'] = limitValue;
      }

      // enqueue task
      await _memexRouter.enqueueTask(
        taskType: 'reprocess_knowledge_base_task',
        payload: payload,
        bizId:
            'reprocess_knowledge_base_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        setState(() {
          _isReprocessingKnowledgeBase = false;
        });
        ToastHelper.showSuccessWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.reprocessTaskCreated,
        );
      }
    } catch (e) {
      _logger.severe('Error reprocessing knowledge base: $e', e);
      if (mounted) {
        setState(() {
          _isReprocessingKnowledgeBase = false;
        });
        ToastHelper.showErrorWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.createTaskFailed(e),
        );
      }
    }
  }

  bool _isClearingData = false;

  Future<void> _rebuildSearchIndex() async {
    if (_isRebuildingSearchIndex) return;
    setState(() => _isRebuildingSearchIndex = true);
    try {
      await _memexRouter.rebuildAllFtsIndexes();
      if (mounted) {
        ToastHelper.showSuccessWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.rebuildSearchIndexSuccess,
        );
      }
    } catch (e) {
      _logger.severe('Error rebuilding search index: $e', e);
      if (mounted) {
        ToastHelper.showErrorWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.rebuildSearchIndexFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRebuildingSearchIndex = false);
      }
    }
  }

  Future<void> _clearData() async {
    if (_isClearingData) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.clearData),
        content: Text(
          '${UserStorage.l10n.confirmClearDataMessage}\n'
          '${UserStorage.l10n.confirmClearDataKeepFactsMessage}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(UserStorage.l10n.confirmClear),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClearingData = true;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        throw Exception(UserStorage.l10n.userIdNotFound);
      }

      // use MemexRouter to clear all data
      await _memexRouter.clearData();

      // Clear cached agent data
      await UserStorage.saveCachedAgentData('pkm', null);
      await UserStorage.saveCachedAgentData('card', null);

      if (mounted) {
        ToastHelper.showSuccessWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.dataClearedSuccess,
        );
      }
    } catch (e, stack) {
      _logger.severe('Clear data failed: $e', e, stack);
      if (mounted) {
        ToastHelper.showErrorWithKey(
          _scaffoldMessengerKey,
          UserStorage.l10n.clearDataFailed(e),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingData = false;
        });
      }
    }
  }

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Future<T?> _pushThemed<T>(Widget page) {
    return Navigator.push<T>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          key: const ValueKey('personal_center_settings_list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            _buildProfileTile(),
            const SizedBox(height: 16),
            _buildFunctionTab(
              icon: Icons.security_outlined,
              title: UserStorage.l10n.systemAuthorization,
              showBadge: _showAuthBadge,
              onTap: () {
                _pushThemed(const SystemAuthorizationPage())
                    .then((_) => _checkPermissionBadge());
              },
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.settings_input_component_outlined,
              title: UserStorage.l10n.modelConfig,
              onTap: () => _pushThemed(const ModelConfigListPage()),
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.people_outline,
              title: UserStorage.l10n.agentConfig,
              onTap: () => _pushThemed(const AgentConfigListPage()),
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.memory,
              title: UserStorage.l10n.memoryTitle,
              onTap: () => context.push(AppRoutes.memory),
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.psychology,
              title: UserStorage.l10n.aiCharacterConfig,
              onTap: () => context.push(AppRoutes.characterConfig),
              isLoading: false,
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.settings_outlined,
              title: UserStorage.l10n.settings,
              onTap: () {
                _pushThemed(const SettingsPage()).then((_) {
                  if (mounted) setState(() {});
                });
              },
            ),
            const SizedBox(height: 12),
            _buildFunctionTab(
              icon: Icons.bug_report_outlined,
              title: 'Debugging',
              onTap: () {
                _pushThemed(DebugSettingsPage(
                  onClearToken: () async => _clearToken(),
                  onClearData: () async => _clearData(),
                  onReprocessCards: () async => _reprocessCards(),
                  onReprocessComments: () async => _reprocessComments(),
                  onReprocessKnowledgeBase: () async =>
                      _reprocessKnowledgeBase(),
                  onRebuildSearchIndex: () async =>
                      _rebuildSearchIndex(),
                  isClearingData: _isClearingData,
                  isReprocessingCards: _isReprocessingCards,
                  isReprocessingComments: _isReprocessingComments,
                  isReprocessingKnowledgeBase:
                      _isReprocessingKnowledgeBase,
                  isRebuildingSearchIndex: _isRebuildingSearchIndex,
                ));
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile() {
    return GestureDetector(
      onTap: _changeAvatar,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.textTertiary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: CharacterAvatar(
                    avatar: _userAvatar ?? UserStorage.defaultAvatarSeed,
                    name: _userId ?? '',
                    size: 52,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit, size: 10, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userId ?? UserStorage.l10n.notSet,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_userEmail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _userEmail!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFunctionTab({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isLoading = false,
    bool showBadge = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.textTertiary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: AppColors.primary, size: 24),
                  if (showBadge)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: isLoading ? AppColors.textTertiary : AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
