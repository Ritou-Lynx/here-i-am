import 'package:flutter/material.dart';
import 'package:memex/data/services/image_gen/image_gen_provider.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/user_storage.dart';

/// Focused image-generation settings page.
///
/// This replaces the image-generation block that used to be buried inside the
/// legacy all-in-one SettingsPage.
class ImageGenerationSettingsPage extends StatefulWidget {
  const ImageGenerationSettingsPage({super.key});

  @override
  State<ImageGenerationSettingsPage> createState() =>
      _ImageGenerationSettingsPageState();
}

class _ImageGenerationSettingsPageState
    extends State<ImageGenerationSettingsPage> {
  static const _defaultComfyUrl = 'http://192.0.2.1:8188';
  static const _defaultComfyModel = 'juggernautXL_ragnarok.safetensors';

  final TextEditingController _comfyUrlController = TextEditingController();

  bool _loading = true;
  bool _savingComfy = false;
  ImageGenProvider _provider = ImageGenProvider.tongyiWanxiang;
  String? _llmConfigKey;
  List<LLMConfig> _llmConfigs = const [];
  String _comfyModel = _defaultComfyModel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object?>([
      UserStorage.getImageGenProvider(),
      UserStorage.getImageGenLlmConfigKey(),
      UserStorage.getLLMConfigs(),
      UserStorage.getComfyuiUrl(),
      UserStorage.getComfyuiModel(),
    ]);
    if (!mounted) return;
    final provider = ImageGenProvider.fromString(values[0]! as String);
    final configs = values[2]! as List<LLMConfig>;
    final savedConfigKey = values[1] as String?;
    final savedUrl = values[3] as String?;
    final savedModel = values[4] as String?;
    setState(() {
      _provider = provider;
      _llmConfigs = configs;
      _llmConfigKey = configs.any((config) => config.key == savedConfigKey)
          ? savedConfigKey
          : null;
      _comfyUrlController.text = savedUrl?.trim().isNotEmpty == true
          ? savedUrl!.trim()
          : _defaultComfyUrl;
      _comfyModel = savedModel?.trim().isNotEmpty == true
          ? savedModel!.trim()
          : _defaultComfyModel;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _comfyUrlController.dispose();
    super.dispose();
  }

  Future<void> _selectProvider(ImageGenProvider provider) async {
    if (_provider == provider) return;
    final previous = _provider;
    setState(() => _provider = provider);
    try {
      await UserStorage.setImageGenProvider(provider.storageKey);
      if (mounted) _showMessage('已切换为${_providerTitle(provider)}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _provider = previous);
      _showMessage('没有保存成功，请稍后再试', error: true);
    }
  }

  Future<void> _selectLlmConfig(String? key) async {
    if (key == null) return;
    setState(() => _llmConfigKey = key);
    try {
      await UserStorage.setImageGenLlmConfigKey(key);
      if (mounted) _showMessage('模型配置已保存');
    } catch (_) {
      if (mounted) _showMessage('没有保存成功，请稍后再试', error: true);
    }
  }

  Future<void> _saveComfy() async {
    if (_savingComfy) return;
    final url = _comfyUrlController.text.trim();
    if (url.isEmpty) {
      _showMessage('请填写 ComfyUI 地址', error: true);
      return;
    }
    setState(() => _savingComfy = true);
    try {
      await UserStorage.setComfyuiUrl(url);
      await UserStorage.setComfyuiModel(_comfyModel);
      if (mounted) _showMessage('本地生成设置已保存');
    } catch (_) {
      if (mounted) _showMessage('没有保存成功，请稍后再试', error: true);
    } finally {
      if (mounted) setState(() => _savingComfy = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                error ? Icons.error_outline_rounded : Icons.check_rounded,
                size: 18,
                color: error
                    ? context.springRainUi.gold
                    : context.springRainUi.textOnAccent,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return SpringRainUiScope(
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(title: const Text('图片生成')),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(context),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = context.springRainUi;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        tokens.space20,
        tokens.space8,
        tokens.space20,
        tokens.space40,
      ),
      children: [
        _CurrentProviderHeader(provider: _provider),
        SizedBox(height: tokens.space24),
        Text('生成服务', style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: tokens.space8),
        _ProviderCard(
          provider: ImageGenProvider.tongyiWanxiang,
          icon: Icons.cloud_outlined,
          title: '通义万相',
          description: '复用模型服务中的通义千问 API Key',
          selected: _provider == ImageGenProvider.tongyiWanxiang,
          onTap: _selectProvider,
        ),
        SizedBox(height: tokens.space8),
        _ProviderCard(
          provider: ImageGenProvider.minimax,
          icon: Icons.auto_awesome_outlined,
          title: 'MiniMax',
          description: '使用已有的 MiniMax API Key',
          selected: _provider == ImageGenProvider.minimax,
          onTap: _selectProvider,
        ),
        SizedBox(height: tokens.space8),
        _ProviderCard(
          provider: ImageGenProvider.openaiCompatible,
          icon: Icons.tune_rounded,
          title: 'OpenAI 兼容服务',
          description: '复用一个已配置的模型服务与图片生成端点',
          selected: _provider == ImageGenProvider.openaiCompatible,
          onTap: _selectProvider,
        ),
        SizedBox(height: tokens.space8),
        _ProviderCard(
          provider: ImageGenProvider.comfyuiLocal,
          icon: Icons.computer_rounded,
          title: '本地 ComfyUI',
          description: '连接局域网或 Tailscale 内的 ComfyUI',
          selected: _provider == ImageGenProvider.comfyuiLocal,
          onTap: _selectProvider,
        ),
        if (_provider == ImageGenProvider.openaiCompatible) ...[
          SizedBox(height: tokens.space24),
          _buildOpenAiConfiguration(context),
        ],
        if (_provider == ImageGenProvider.comfyuiLocal) ...[
          SizedBox(height: tokens.space24),
          _buildComfyConfiguration(context),
        ],
        SizedBox(height: tokens.space24),
        const _InfoNote(
          icon: Icons.chat_bubble_outline_rounded,
          text: '这里选择的是角色对话里调用的图片生成服务；聊天模型不会因此改变。',
        ),
      ],
    );
  }

  Widget _buildOpenAiConfiguration(BuildContext context) {
    final tokens = context.springRainUi;
    return _SettingsSurface(
      title: '模型配置',
      subtitle: '请求会发送到所选配置的 /images/generations 端点。',
      child: _llmConfigs.isEmpty
          ? Container(
              padding: EdgeInsets.all(tokens.space16),
              decoration: BoxDecoration(
                color: tokens.warningSoft,
                borderRadius: BorderRadius.circular(tokens.radius14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: tokens.warning, size: tokens.iconMedium),
                  SizedBox(width: tokens.space12),
                  Expanded(
                    child: Text(
                      '还没有可用的模型配置。请先返回“模型服务”添加一个 OpenAI 兼容配置。',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: tokens.warning),
                    ),
                  ),
                ],
              ),
            )
          : DropdownButtonFormField<String>(
              initialValue: _llmConfigKey,
              decoration: const InputDecoration(
                labelText: '使用哪一个模型配置',
              ),
              items: _llmConfigs
                  .map(
                    (config) => DropdownMenuItem(
                      value: config.key,
                      child: Text(
                        '${config.key} · ${config.modelId}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _selectLlmConfig,
            ),
    );
  }

  Widget _buildComfyConfiguration(BuildContext context) {
    final tokens = context.springRainUi;
    return _SettingsSurface(
      title: '本地连接',
      subtitle: '保存地址与工作流使用的基础模型。',
      child: Column(
        children: [
          TextField(
            controller: _comfyUrlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'ComfyUI 地址',
              hintText: 'http://127.0.0.1:8188',
            ),
          ),
          SizedBox(height: tokens.space12),
          DropdownButtonFormField<String>(
            initialValue: _comfyModel,
            decoration: const InputDecoration(labelText: '基础模型'),
            items: const [
              DropdownMenuItem(
                value: 'juggernautXL_ragnarok.safetensors',
                child: Text('Juggernaut XL · 写实'),
              ),
              DropdownMenuItem(
                value: 'ponyDiffusionV6XL.safetensors',
                child: Text('Pony V6 XL · 动漫'),
              ),
              DropdownMenuItem(
                value: 'cyberrealistic_final.safetensors',
                child: Text('CyberRealistic · SD 1.5'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _comfyModel = value);
            },
          ),
          SizedBox(height: tokens.space16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _savingComfy ? null : _saveComfy,
              icon: _savingComfy
                  ? SizedBox.square(
                      dimension: tokens.iconSmall,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_savingComfy ? '正在保存' : '保存本地设置'),
            ),
          ),
        ],
      ),
    );
  }

  static String _providerTitle(ImageGenProvider provider) {
    return switch (provider) {
      ImageGenProvider.tongyiWanxiang => '通义万相',
      ImageGenProvider.minimax => 'MiniMax',
      ImageGenProvider.openaiCompatible => 'OpenAI 兼容服务',
      ImageGenProvider.comfyuiLocal => '本地 ComfyUI',
    };
  }
}

class _CurrentProviderHeader extends StatelessWidget {
  const _CurrentProviderHeader({required this.provider});

  final ImageGenProvider provider;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Container(
      padding: EdgeInsets.all(tokens.space20),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(tokens.radius18),
        border: Border.all(color: tokens.outline),
      ),
      child: Row(
        children: [
          Container(
            width: tokens.controlLarge,
            height: tokens.controlLarge,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(tokens.radius14),
            ),
            child: Icon(Icons.image_outlined, color: tokens.accent),
          ),
          SizedBox(width: tokens.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前服务', style: Theme.of(context).textTheme.bodySmall),
                SizedBox(height: tokens.space2),
                Text(
                  _ImageGenerationSettingsPageState._providerTitle(provider),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space12,
              vertical: tokens.space6,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(tokens.radiusPill),
            ),
            child: Text(
              '使用中',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final ImageGenProvider provider;
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final ValueChanged<ImageGenProvider> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Material(
      color: selected ? tokens.surfaceSelected : tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius18),
        side: BorderSide(
          color: selected ? tokens.accent : tokens.divider,
          width: selected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius18),
        onTap: () => onTap(provider),
        child: Padding(
          padding: EdgeInsets.all(tokens.space16),
          child: Row(
            children: [
              Container(
                width: tokens.controlMedium,
                height: tokens.controlMedium,
                decoration: BoxDecoration(
                  color: selected ? tokens.surfaceRaised : tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(tokens.radius14),
                ),
                child: Icon(icon, color: tokens.accent),
              ),
              SizedBox(width: tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: tokens.space2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.space8),
              AnimatedContainer(
                duration: SpringRainUiTokens.motionFast,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? tokens.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? tokens.accent : tokens.outline,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check_rounded,
                        size: 15, color: tokens.textOnAccent)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Container(
      padding: EdgeInsets.all(tokens.space20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radius18),
        border: Border.all(color: tokens.divider),
        boxShadow: tokens.shadowLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: tokens.space4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: tokens.space16),
          child,
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: tokens.iconSmall, color: tokens.iconMuted),
        SizedBox(width: tokens.space8),
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}
