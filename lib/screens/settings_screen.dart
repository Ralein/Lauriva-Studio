import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/llm_provider.dart';
import '../models/toast_notification.dart';
import '../providers/llm_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/toast_provider.dart';
import '../widgets/background_glow.dart';
import '../widgets/header_bar.dart';
import '../widgets/settings/about_section.dart';
import '../widgets/settings/advanced_params_section.dart';
import '../widgets/settings/api_key_section.dart';
import '../widgets/settings/model_section.dart';
import '../widgets/settings/provider_selector_section.dart';
import '../widgets/settings/interactive_config_guide_modal.dart';

/// Full-screen Settings page — fully reactive, auto-persisting, zero-friction surface.
/// All API key entries, model selections, custom endpoints, and hyperparameter changes
/// are verified and saved atomically without requiring a manual save button.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late LlmProvider _selectedProvider;
  late final TextEditingController _keyController;
  late final TextEditingController _customUrlController;
  late String _selectedModel;
  bool _isAutoVerifying = false;
  String? _autoVerifyStatus;
  Timer? _keyDebounceTimer;

  @override
  void initState() {
    super.initState();
    final llmSettings = context.read<LlmSettingsProvider>();
    _selectedProvider = llmSettings.activeProvider;
    _selectedModel = llmSettings.activeModel;
    final initialKey = llmSettings.getApiKeyForProvider(_selectedProvider.id);
    _keyController = TextEditingController(
      text: initialKey,
    );
    _customUrlController = TextEditingController(
      text: llmSettings.customBaseUrl ?? _selectedProvider.baseUrl,
    );
    _customUrlController.addListener(_onCustomUrlChanged);

    // If first time / user didn't set a model, automatically fetch & select the free model
    if (!llmSettings.hasUserSelectedModel(_selectedProvider.id) &&
        (initialKey.isNotEmpty || !_selectedProvider.requiresKey || _selectedProvider.isCustom)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoFetchFreeModel(_selectedProvider, initialKey);
      });
    }
  }

  @override
  void dispose() {
    _keyDebounceTimer?.cancel();
    _customUrlController.removeListener(_onCustomUrlChanged);
    _keyController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  void _onCustomUrlChanged() {
    final url = _customUrlController.text.trim();
    if (_selectedProvider.isCustom && url.isNotEmpty) {
      context.read<LlmSettingsProvider>().setCustomBaseUrl(url);
    }
  }

  Future<void> _autoFetchFreeModel(LlmProvider provider, String apiKey) async {
    final llmSettings = context.read<LlmSettingsProvider>();
    if (llmSettings.hasUserSelectedModel(provider.id)) return;

    final customUrl = provider.isCustom ? _customUrlController.text.trim() : null;
    final freeModel = await llmSettings.autoSelectFreeModelIfUnset(
      provider: provider,
      apiKey: apiKey,
      customBaseUrl: customUrl,
    );
    if (mounted && freeModel != null && _selectedProvider.id == provider.id) {
      setState(() {
        _selectedModel = freeModel;
        _autoVerifyStatus = 'Active with $freeModel';
      });
    }
  }

  void _onProviderChanged(LlmProvider newProvider, {String? preserveCurrentKey}) async {
    if (_selectedProvider.id == newProvider.id) return;
    _keyDebounceTimer?.cancel();
    final llmSettings = context.read<LlmSettingsProvider>();

    final providerKey = preserveCurrentKey ?? llmSettings.getApiKeyForProvider(newProvider.id);
    final savedModel = llmSettings.getSavedModelForProvider(newProvider.id);
    final activeModel = savedModel ?? newProvider.defaultModel;

    setState(() {
      _selectedProvider = newProvider;
      _keyController.text = providerKey;
      _selectedModel = activeModel;
      _autoVerifyStatus = providerKey.isNotEmpty ? 'Key saved · $activeModel' : null;
      _isAutoVerifying = false;
      if (newProvider.isCustom && llmSettings.customBaseUrl != null) {
        _customUrlController.text = llmSettings.customBaseUrl!;
      } else {
        _customUrlController.text = newProvider.baseUrl;
      }
    });

    // Auto-save active provider if key exists or provider is keyless
    if (!newProvider.requiresKey || providerKey.isNotEmpty) {
      await llmSettings.setActiveProvider(newProvider.id);
      await llmSettings.setActiveModel(activeModel);
    }

    if (savedModel == null && (providerKey.isNotEmpty || !newProvider.requiresKey || newProvider.isCustom)) {
      _autoFetchFreeModel(newProvider, providerKey);
    }
  }

  /// Handles key typing and pasting with smart prefix detection, debouncing,
  /// automatic verification, model provisioning, and auto-saving.
  void _handleKeyChanged() {
    _keyDebounceTimer?.cancel();

    final rawKey = _keyController.text.trim();
    if (rawKey.isEmpty) {
      // Auto-save clearing of key
      final llmSettings = context.read<LlmSettingsProvider>();
      llmSettings.setApiKeyForProvider(_selectedProvider.id, '');
      setState(() {
        _autoVerifyStatus = null;
        _isAutoVerifying = false;
      });
      return;
    }

    // 1. Smart Provider Auto-Detection from prefix
    final detectedProviderId = LlmProvider.detectProviderFromKey(rawKey);
    if (detectedProviderId != null && detectedProviderId != _selectedProvider.id) {
      final newProvider = LlmProvider.getById(detectedProviderId);
      HapticFeedback.mediumImpact();
      _onProviderChanged(newProvider, preserveCurrentKey: rawKey);
      context.read<ToastProvider>().showToast(
        'Detected ${newProvider.name} API key',
        ToastType.info,
      );
      if (_isValidApiKeyFormat(rawKey)) {
        _keyDebounceTimer = Timer(const Duration(milliseconds: 600), () {
          _autoVerifyAndSave(rawKey);
        });
      }
      return;
    }

    // 2. Format validation check immediately on paste/type
    if (rawKey.startsWith('http') || rawKey.startsWith('www.') || rawKey.contains('://')) {
      setState(() {
        _isAutoVerifying = false;
        _autoVerifyStatus = 'URLs are not valid API keys';
      });
      HapticFeedback.vibrate();
      return;
    }

    // 3. Debounce auto-verification & auto-save (600ms)
    if (rawKey.length >= 8) {
      _keyDebounceTimer = Timer(const Duration(milliseconds: 600), () {
        _autoVerifyAndSave(rawKey);
      });
    }
  }

  bool _isValidApiKeyFormat(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('www.') ||
        trimmed.contains('://')) {
      return false;
    }
    if (trimmed.contains(RegExp(r'\s'))) return false;
    if (trimmed.length < 8) return false;
    return true;
  }

  Future<void> _autoVerifyAndSave(String apiKey) async {
    if (!mounted) return;
    final provider = _selectedProvider;
    final customUrl = provider.isCustom ? _customUrlController.text.trim() : null;
    final llmSettings = context.read<LlmSettingsProvider>();
    final toast = context.read<ToastProvider>();

    final trimmedKey = apiKey.trim();

    // 1. Format validation: reject URLs, whitespace, or invalid strings
    if (!_isValidApiKeyFormat(trimmedKey)) {
      if (mounted) {
        setState(() {
          _isAutoVerifying = false;
          _autoVerifyStatus = trimmedKey.startsWith('http') ||
                  trimmedKey.startsWith('www.') ||
                  trimmedKey.contains('://')
              ? 'URLs are not valid API keys'
              : 'Invalid key format';
        });
        HapticFeedback.vibrate();
      }
      return;
    }

    setState(() {
      _isAutoVerifying = true;
      _autoVerifyStatus = 'Verifying key…';
    });

    try {
      // 2. Genuine API auth probe: checks /models, /auth/key, or completions
      final isKeyValid = await llmSettings.testConnection(
        provider: provider,
        apiKey: trimmedKey,
        model: _selectedModel,
        customBaseUrl: customUrl,
      );

      if (!mounted || _selectedProvider.id != provider.id) return;

      if (isKeyValid) {
        // 3. Authenticated successfully! Fetch live model catalog if supported
        List<LlmModelInfo> liveModels = [];
        try {
          liveModels = await llmSettings.fetchLiveModelsFor(
            provider: provider,
            apiKey: trimmedKey,
            customBaseUrl: customUrl,
          );
        } catch (_) {}

        String chosenModel = _selectedModel;
        if (liveModels.isNotEmpty) {
          chosenModel = await llmSettings.selectBestModel(
            provider: provider,
            liveModels: liveModels,
            currentModel: _selectedModel,
          );
        } else if (!llmSettings.hasUserSelectedModel(provider.id)) {
          chosenModel = provider.defaultModel;
        }

        // 4. Atomic Auto-Save
        await llmSettings.setApiKeyForProvider(provider.id, trimmedKey);
        await llmSettings.setActiveProvider(provider.id);
        await llmSettings.setModelForProvider(provider.id, chosenModel);
        await llmSettings.setActiveModel(chosenModel);
        if (provider.isCustom && customUrl != null && customUrl.isNotEmpty) {
          await llmSettings.setCustomBaseUrl(customUrl);
        }

        if (mounted) {
          setState(() {
            _isAutoVerifying = false;
            _selectedModel = chosenModel;
            _autoVerifyStatus = 'Verified & saved';
          });
          HapticFeedback.lightImpact();
          toast.showToast(
            '${provider.name} connected & saved with $chosenModel!',
            ToastType.success,
          );
        }
      } else {
        // Probe returned unauthorized / invalid key: REJECT
        if (mounted) {
          setState(() {
            _isAutoVerifying = false;
            _autoVerifyStatus = 'Invalid API key';
          });
          HapticFeedback.vibrate();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAutoVerifying = false;
          _autoVerifyStatus = 'Connection error';
        });
      }
    }
  }

  /// Re-reads provider/key/model after the interactive guide modal saves.
  void _syncWithSavedSettings() {
    final llmSettings = context.read<LlmSettingsProvider>();
    final active = llmSettings.activeProvider;
    setState(() {
      _selectedProvider = active;
      _keyController.text = llmSettings.getApiKeyForProvider(active.id);
      _selectedModel = llmSettings.getSavedModelForProvider(active.id) ?? active.defaultModel;
      _autoVerifyStatus = 'Saved & Active';
    });
  }

  Future<void> _launchUrl(String url) async {
    final toast = context.read<ToastProvider>();
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await Clipboard.setData(ClipboardData(text: url));
        toast.showToast('Link copied to clipboard!', ToastType.info);
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      toast.showToast('Link copied to clipboard!', ToastType.info);
    }
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty && _selectedProvider.requiresKey && !_selectedProvider.isCustom) {
      setState(() {
        _autoVerifyStatus = 'API key required';
      });
      return;
    }

    if (_selectedProvider.requiresKey && !_selectedProvider.isCustom && !_isValidApiKeyFormat(key)) {
      setState(() {
        _autoVerifyStatus = key.startsWith('http') || key.startsWith('www.') || key.contains('://')
            ? 'URLs are not valid API keys'
            : 'Invalid key format';
      });
      HapticFeedback.vibrate();
      return;
    }

    setState(() {
      _isAutoVerifying = true;
      _autoVerifyStatus = 'Verifying key…';
    });

    final llmSettings = context.read<LlmSettingsProvider>();
    final toast = context.read<ToastProvider>();

    final success = await llmSettings.testConnection(
      provider: _selectedProvider,
      apiKey: key,
      model: _selectedModel,
      customBaseUrl: _selectedProvider.isCustom ? _customUrlController.text.trim() : null,
    );

    if (mounted) {
      setState(() {
        _isAutoVerifying = false;
        _autoVerifyStatus = success
            ? 'Verified & saved'
            : 'Invalid API key';
      });
      if (success) {
        await llmSettings.setApiKeyForProvider(_selectedProvider.id, key);
        await llmSettings.setActiveProvider(_selectedProvider.id);
        await llmSettings.setModelForProvider(_selectedProvider.id, _selectedModel);
        await llmSettings.setActiveModel(_selectedModel);
        HapticFeedback.lightImpact();
        toast.showToast('${_selectedProvider.name} connected & saved!', ToastType.success);
      } else {
        HapticFeedback.vibrate();
        toast.showToast('Invalid API key for ${_selectedProvider.name}', ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final llmSettings = context.watch<LlmSettingsProvider>();
    final theme = context.watch<ThemeProvider>();
    final canPop = Navigator.canPop(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Page Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: HeaderBar(
            title: 'Settings',
            showSettings: false,
            leading: canPop
                ? IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    color: AppColors.textPrimary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            trailing: InkWell(
              onTap: () async {
                HapticFeedback.lightImpact();
                await showInteractiveConfigGuideModal(
                  context,
                  initialProviderId: _selectedProvider.id,
                );
                if (mounted) _syncWithSavedSettings();
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.paletteTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: AppColors.paletteTeal.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.compass,
                      size: 14,
                      color: AppColors.paletteTeal,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Guide',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.paletteTeal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        // ── Scrollable Body ──────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. AI Provider Selection
                ProviderSelectorSection(
                  selectedProvider: _selectedProvider,
                  onProviderSelected: _onProviderChanged,
                  llmSettings: llmSettings,
                ),

                const SizedBox(height: 20),

                // 2. API Key Configuration with Auto-Detection & Auto-Save
                ApiKeySection(
                  selectedProvider: _selectedProvider,
                  controller: _keyController,
                  isVerifying: _isAutoVerifying,
                  verifyStatus: _autoVerifyStatus,
                  onLaunchKeyPortal: () => _launchUrl(_selectedProvider.keyPortalUrl),
                  onKeyChanged: _handleKeyChanged,
                ),

                if (_selectedProvider.requiresKey) const SizedBox(height: 20),

                // 3. Model Picker & Custom Base URL (Auto-saves on selection)
                ModelSection(
                  selectedProvider: _selectedProvider,
                  selectedModel: _selectedModel,
                  apiKeyController: _keyController,
                  customUrlController: _customUrlController,
                  onLaunchCatalog: () => _launchUrl(_selectedProvider.catalogUrl),
                  onModelSelected: (picked) async {
                    if (mounted) {
                      setState(() {
                        _selectedModel = picked;
                        _autoVerifyStatus = 'Active with $picked';
                      });
                      HapticFeedback.lightImpact();
                      await llmSettings.setModelForProvider(_selectedProvider.id, picked);
                      await llmSettings.setActiveModel(picked);
                      if (context.mounted) {
                        context.read<ToastProvider>().showToast(
                          'Active model set to $picked',
                          ToastType.info,
                        );
                      }
                    }
                  },
                ),

                const SizedBox(height: 20),

                // 4. Advanced Hyperparameters (Auto-saves on change)
                AdvancedParamsSection(llmSettings: llmSettings),

                const SizedBox(height: 20),

                // 5. Appearance Theme Switcher (Auto-saves on change)
                _sectionLabel('APPEARANCE'),
                const SizedBox(height: 10),
                _buildThemeToggle(theme),

                const SizedBox(height: 24),

                // 7. Ambient Real-Time Auto-Save Status
                _buildAutoSaveStatusCard(llmSettings),

                const SizedBox(height: 24),

                // 7. About & Version Info
                AboutSection(),
              ],
            ),
          ),
        ),
      ],
    );

    if (canPop) {
      return Scaffold(
        body: BackgroundGlow(
          child: SafeArea(
            child: content,
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: content,
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildThemeToggle(ThemeProvider theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.glassBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              _buildThemeChoice('light', LucideIcons.sun, 'Light', theme),
              const SizedBox(width: 4),
              _buildThemeChoice('system', LucideIcons.monitor, 'System', theme),
              const SizedBox(width: 4),
              _buildThemeChoice('dark', LucideIcons.moon, 'Dark', theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeChoice(
    String mode,
    IconData icon,
    String label,
    ThemeProvider theme,
  ) {
    final isSelected = theme.themeMode == mode;

    return Expanded(
      child: InkWell(
        onTap: () => theme.setThemeMode(mode),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoSaveStatusCard(LlmSettingsProvider llmSettings) {
    final provider = _selectedProvider;
    final key = _keyController.text.trim();
    final hasKeyOrKeyless = !provider.requiresKey || key.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasKeyOrKeyless
              ? AppColors.success.withValues(alpha: 0.25)
              : AppColors.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (hasKeyOrKeyless ? AppColors.success : AppColors.textMuted)
                  .withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasKeyOrKeyless ? LucideIcons.check : LucideIcons.info,
              size: 13,
              color: hasKeyOrKeyless ? AppColors.success : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasKeyOrKeyless
                      ? 'Settings auto-saved & active'
                      : 'API key required to activate',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: hasKeyOrKeyless ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasKeyOrKeyless
                      ? '${provider.name} · $_selectedModel'
                      : provider.name,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    color: hasKeyOrKeyless ? AppColors.accentText : AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isAutoVerifying)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            )
          else if (hasKeyOrKeyless)
            InkWell(
              onTap: _testConnection,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  LucideIcons.refreshCw,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

}
