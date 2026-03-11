import 'package:flutter/material.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/user_setup/widgets/setup_model_config_page.dart';

/// User setup screen. Shown when user opens app for the first time or no local userId.
class UserSetupScreen extends StatefulWidget {
  final VoidCallback onUserCreated;

  const UserSetupScreen({
    super.key,
    required this.onUserCreated,
  });

  @override
  State<UserSetupScreen> createState() => _UserSetupScreenState();
}

class _UserSetupScreenState extends State<UserSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userIdController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final userId = _userIdController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      // save userId
      await UserStorage.saveUser(userId);

      // check LLM config
      final configs = await UserStorage.getLLMConfigs();
      final defaultConfig = configs.firstWhere(
        (c) => c.key == LLMConfig.defaultClientKey,
        orElse: () => LLMConfig.createDefaultClient(),
      );

      final isValid = defaultConfig.isValid;

      if (mounted) {
        if (isValid) {
          ToastHelper.showSuccess(context, UserStorage.l10n.userCreatedSuccess);
          widget.onUserCreated();
        } else {
          setState(() {
            _isSubmitting = false;
          });
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SetupModelConfigPage(
                config: defaultConfig,
                onComplete: () {
                  if (mounted) {
                    Navigator.pop(context);
                    ToastHelper.showSuccess(
                        context, UserStorage.l10n.userCreatedSuccess);
                    widget.onUserCreated();
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ToastHelper.showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo/Icon
                  Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(bottom: 32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),

                  // Title
                  Text(
                    UserStorage.l10n.welcomeToMemex,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    UserStorage.l10n.createUserIdToStart,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  // User ID Input
                  TextFormField(
                    controller: _userIdController,
                    decoration: InputDecoration(
                      labelText: UserStorage.l10n.userIdLabel,
                      hintText: UserStorage.l10n.userIdHint,
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return UserStorage.l10n.pleaseEnterUserId;
                      }
                      if (value.trim().length > 50) {
                        return UserStorage.l10n.userIdMaxLength;
                      }
                      return null;
                    },
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleSubmit(),
                    enabled: !_isSubmitting,
                  ),

                  const SizedBox(height: 24),

                  // Submit Button
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            UserStorage.l10n.startUsing,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Info Text
                  Text(
                    UserStorage.l10n.userIdTip,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
