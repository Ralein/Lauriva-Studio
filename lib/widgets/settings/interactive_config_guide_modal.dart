import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/llm_provider.dart';
import '../../models/toast_notification.dart';
import '../../providers/llm_settings_provider.dart';
import '../../providers/toast_provider.dart';

/// Shows a how-to for getting an API key for every provider the app supports.
/// Styled like the other app sheets (Mini Settings, History): glass surface,
/// 20px top radius, safe-area aware, 36x4 handle, icon-chip header.
Future<void> showInteractiveConfigGuideModal(BuildContext context, {String? initialProviderId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.glassBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => InteractiveConfigGuideModal(initialProviderId: initialProviderId),
  );
}

class _GuideStep {
  final String title;
  final String detail;
  const _GuideStep(this.title, this.detail);
}

/// Hand-written steps for providers whose console flow is worth spelling out.
/// Every other provider in [LlmProvider.allProviders] gets generic steps built
/// from its own portal URL, so the guide never drifts from the real list.
const Map<String, List<_GuideStep>> _curatedSteps = {
  'groq': [
    _GuideStep('Open the Groq Console', 'Tap the button below. It opens the "API Keys" page.'),
    _GuideStep('Sign in', 'Choose "Continue with Google" or GitHub.'),
    _GuideStep('Create the key', 'Tap "Create API Key" at the top right, name it "Lauriva", then tap "Submit".'),
    _GuideStep('Copy it now', 'Tap "Copy" in the pop-up. Groq shows the key only once.'),
  ],
  'gemini': [
    _GuideStep('Open Google AI Studio', 'Tap the button below. It opens the "API keys" page.'),
    _GuideStep('Sign in', 'Use any Google account and accept the terms if asked.'),
    _GuideStep('Create the key', 'Tap "Create API key", then pick a project (or "Create API key in new project").'),
    _GuideStep('Copy it', 'Tap the copy icon next to your new key.'),
  ],
  'cerebras': [
    _GuideStep('Open Cerebras Cloud', 'Tap the button below.'),
    _GuideStep('Sign in', 'Create a free account or sign in with Google.'),
    _GuideStep('Create the key', 'Open "API Keys" in the left menu, then tap "Generate API Key".'),
    _GuideStep('Copy it', 'Tap the copy icon next to the key.'),
  ],
  'openrouter': [
    _GuideStep('Open OpenRouter Keys', 'Tap the button below.'),
    _GuideStep('Sign in', 'Use Google, GitHub or email.'),
    _GuideStep('Create the key', 'Tap "Create Key", name it "Lauriva". Leave the credit limit empty.'),
    _GuideStep('Copy it now', 'Tap "Copy". OpenRouter shows the key only once.'),
  ],
  'github': [
    _GuideStep('Open GitHub tokens', 'Tap the button below.'),
    _GuideStep('Sign in', 'Use your GitHub account.'),
    _GuideStep('Generate a token', 'Tap "Generate new token", name it "Lauriva". No extra scopes are needed.'),
    _GuideStep('Copy it now', 'GitHub shows the token only once. It starts with "ghp_" or "github_pat_".'),
  ],
  'huggingface': [
    _GuideStep('Open Hugging Face tokens', 'Tap the button below.'),
    _GuideStep('Sign in', 'Create a free account or sign in.'),
    _GuideStep('Create a token', 'Tap "Create new token", pick "Read" (or "Fine-grained" with Inference access) and name it "Lauriva".'),
    _GuideStep('Copy it now', 'The token starts with "hf_" and is shown only once.'),
  ],
};

/// Providers that need a paid balance rather than a free tier.
const Set<String> _paidProviders = {'openai', 'anthropic', 'deepseek', 'perplexity'};

/// Extra provider-specific notes shown at the end of the troubleshooting list.
const Map<String, String> _providerNotes = {
  'gemini': 'Gemini is not available in every country. If AI Studio says it is unavailable, try another provider.',
  'openrouter': 'Free models can be busy at peak times. Try again later or pick another ":free" model in Settings.',
  'cloudflare': 'Cloudflare needs your account ID inside the endpoint URL. Use "FreeLLMAPI & Custom Endpoint" with https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/ai/v1 and your API token.',
  'siliconflow': 'SiliconFlow is a China-based service. It may be slow or blocked in some regions.',
  'zhipu': 'Zhipu (bigmodel.cn) and ModelScope sign-ups are in Chinese. Use your browser\'s translate option.',
  'modelscope': 'ModelScope sign-up is in Chinese. Use your browser\'s translate option.',
};

List<_GuideStep> _stepsFor(LlmProvider p) {
  final curated = _curatedSteps[p.id];
  if (curated != null) return curated;
  final paid = _paidProviders.contains(p.id);
  return [
    _GuideStep('Open ${p.name}', 'Tap the button below. It opens the key page.'),
    _GuideStep(
      'Sign in',
      paid
          ? 'Sign in and add billing or credits if asked. This provider has no free tier.'
          : 'Create a free account or sign in.',
    ),
    const _GuideStep('Create the key', 'Create a new API key and name it "Lauriva".'),
    const _GuideStep('Copy it now', 'Many providers show the key only once. Copy all of it.'),
  ];
}

class InteractiveConfigGuideModal extends StatefulWidget {
  final String? initialProviderId;

  const InteractiveConfigGuideModal({
    super.key,
    this.initialProviderId,
  });

  @override
  State<InteractiveConfigGuideModal> createState() => _InteractiveConfigGuideModalState();
}

class _InteractiveConfigGuideModalState extends State<InteractiveConfigGuideModal> {
  late String _selectedProviderId;
  late final TextEditingController _keyInputController;
  bool _isTesting = false;
  bool? _testSuccess;
  String? _testMessage;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final llmSettings = context.read<LlmSettingsProvider>();
    _selectedProviderId = widget.initialProviderId ?? llmSettings.activeProvider.id;
    if (!LlmProvider.allProviders.any((p) => p.id == _selectedProviderId)) {
      _selectedProviderId = 'groq';
    }
    _keyInputController = TextEditingController(
      text: llmSettings.getApiKeyForProvider(_selectedProviderId),
    );
  }

  @override
  void dispose() {
    _keyInputController.dispose();
    super.dispose();
  }

  LlmProvider get _active => LlmProvider.getById(_selectedProviderId);

  void _selectProvider(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedProviderId = id;
      _testSuccess = null;
      _testMessage = null;
      _keyInputController.text = context.read<LlmSettingsProvider>().getApiKeyForProvider(id);
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      context.read<ToastProvider>().showToast('Could not open the link. Try "Copy link".', ToastType.error);
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      context.read<ToastProvider>().showToast('Link copied to clipboard', ToastType.info);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      context.read<ToastProvider>().showToast('Clipboard is empty', ToastType.error);
      return;
    }
    setState(() {
      _keyInputController.text = text;
      _testSuccess = null;
      _testMessage = null;
    });
  }

  Future<void> _testAndSaveKey() async {
    final key = _keyInputController.text.trim();
    if (key.isEmpty) {
      context.read<ToastProvider>().showToast('Paste your API key first', ToastType.error);
      return;
    }
    if (key.startsWith('http://') ||
        key.startsWith('https://') ||
        key.startsWith('www.') ||
        key.contains('://')) {
      context.read<ToastProvider>().showToast('URLs are not valid API keys', ToastType.error);
      return;
    }

    setState(() {
      _isTesting = true;
      _testSuccess = null;
      _testMessage = null;
    });

    final llmSettings = context.read<LlmSettingsProvider>();
    final provider = _active;
    final name = provider.name;

    try {
      final success = await llmSettings.testConnection(
        provider: provider,
        apiKey: key,
        // Probe with this provider's own model, never the active provider's.
        model: llmSettings.getSavedModelForProvider(provider.id) ?? provider.defaultModel,
      );
      if (!mounted) return;

      if (success) {
        await llmSettings.setApiKeyForProvider(_selectedProviderId, key);
        await llmSettings.setActiveProvider(_selectedProviderId);
        if (!mounted) return;
        setState(() {
          _isTesting = false;
          _testSuccess = true;
          _testMessage = '$name is connected and active.';
        });
        HapticFeedback.lightImpact();
        context.read<ToastProvider>().showToast('$name key saved & activated!', ToastType.success);
      } else {
        setState(() {
          _isTesting = false;
          _testSuccess = false;
          _testMessage = 'That key did not work. See "Something not working?" below.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testSuccess = false;
          _testMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _activateZeroConfigProvider(String providerId) async {
    final llmSettings = context.read<LlmSettingsProvider>();
    await llmSettings.setActiveProvider(providerId);
    HapticFeedback.selectionClick();
    if (mounted) {
      context.read<ToastProvider>().showToast('Switched to ${_active.name}', ToastType.success);
      Navigator.pop(context);
    }
  }

  TextStyle _body({Color? color, FontWeight? weight, double size = 13}) => GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.textSecondary,
        height: 1.4,
      );

  @override
  Widget build(BuildContext context) {
    final provider = _active;
    final media = MediaQuery.of(context);

    // Same shell as Mini Settings: SafeArea keeps the sheet clear of the
    // system navigation bar; the keyboard inset lifts the form above it.
    return SafeArea(
      bottom: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _sectionLabel('PROVIDER'),
                  const SizedBox(height: 8),
                  _buildProviderChooser(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + media.viewInsets.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProviderIntro(provider),
                    const SizedBox(height: 20),
                    if (!provider.requiresKey)
                      _buildKeyless(provider)
                    else ...[
                      _buildStepper(provider),
                      const SizedBox(height: 20),
                      _buildOpenButtons(provider),
                      const SizedBox(height: 22),
                      _buildHaveKeyCard(provider),
                    ],
                    if (provider.requiresKey) ...[
                      const SizedBox(height: 8),
                      _buildTroubleshooting(provider),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textMuted,
        ),
      );

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.compass, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'Provider Guide',
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 18),
          color: AppColors.textMuted,
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  /// One scrollable row with every provider the app supports.
  Widget _buildProviderChooser() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: LlmProvider.allProviders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _providerChip(LlmProvider.allProviders[i]),
      ),
    );
  }

  Widget _providerChip(LlmProvider item) {
    final selected = item.id == _selectedProviderId;
    return Semantics(
      button: true,
      selected: selected,
      label: item.name,
      child: InkWell(
        onTap: () => _selectProvider(item.id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.glassBorder,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            item.name,
            style: GoogleFonts.outfit(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProviderIntro(LlmProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.name,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          p.tag,
          style: _body(size: 12, weight: FontWeight.w600, color: AppColors.accentText),
        ),
        const SizedBox(height: 6),
        Text(p.description, style: _body()),
      ],
    );
  }

  /// Providers that need no key: Pollinations, Api.Airforce, Ollama, Custom.
  Widget _buildKeyless(LlmProvider p) {
    final String body;
    if (p.isCustom) {
      body = 'Set your endpoint URL (and a key if it needs one) under Settings, then switch to it.';
    } else if (p.id == 'ollama') {
      body = 'Install Ollama on the same device, run "ollama pull ${p.defaultModel}", keep it running, then switch to it.';
    } else {
      body = 'No account or key needed. Switch to it and start.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('SETUP'),
        const SizedBox(height: 8),
        Text(body, style: _body()),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _activateZeroConfigProvider(p.id),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: Text(
            'Use ${p.name}',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// Connected numbered pipeline (circle + vertical connector per step).
  Widget _buildStepper(LlmProvider p) {
    final steps = _stepsFor(p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('STEPS'),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            color: AppColors.primary.withValues(alpha: 0.25),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < steps.length - 1 ? 16 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            steps[i].title,
                            style: _body(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(steps[i].detail, style: _body()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Key format: ${p.keyHint}',
          style: _body(size: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildOpenButtons(LlmProvider p) {
    final url = p.keyPortalUrl;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _launchUrl(url),
            icon: const Icon(LucideIcons.externalLink, size: 16),
            label: Text(
              'Open ${p.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _copyUrl(url),
          icon: const Icon(LucideIcons.copy, size: 18),
          tooltip: 'Copy link',
          color: AppColors.textSecondary,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: AppColors.glassBorder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHaveKeyCard(LlmProvider p) {
    final ok = _testSuccess == true;
    final statusColor = ok ? AppColors.primary : AppColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('PASTE YOUR KEY'),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: AppColors.glassInputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keyInputController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GoogleFonts.firaCode(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: p.keyHint,
                    hintStyle: _body(color: AppColors.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {
                    _testSuccess = null;
                    _testMessage = null;
                  }),
                ),
              ),
              IconButton(
                icon: Icon(_obscureKey ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                color: AppColors.textMuted,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
              IconButton(
                icon: const Icon(LucideIcons.clipboard, size: 18),
                tooltip: 'Paste from clipboard',
                color: AppColors.textMuted,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _pasteFromClipboard,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _isTesting ? null : _testAndSaveKey,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _isTesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Check & Save Key',
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                ),
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  ok ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                  size: 16,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_testMessage!, style: _body(size: 13, color: statusColor))),
            ],
          ),
          if (ok) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Done', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildTroubleshooting(LlmProvider guide) {
    Widget item(String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 12),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '$title. ', style: _body(size: 13, weight: FontWeight.w600, color: AppColors.textPrimary)),
                      TextSpan(text: text, style: _body(size: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AppColors.textMuted,
        collapsedIconColor: AppColors.textMuted,
        title: Text(
          'Something not working?',
          style: _body(size: 14, weight: FontWeight.w500, color: AppColors.textSecondary),
        ),
        children: [
          item('Key rejected', 'Copy the whole key again with no spaces. Expected format: ${guide.keyHint}'),
          item('Quota reached', 'Free tiers reset after a while. Wait a bit or switch provider.'),
          item('Not in your region', 'Try another provider, or Pollinations.ai which needs no key.'),
          if (_providerNotes[guide.id] != null) item('Good to know', _providerNotes[guide.id]!),
        ],
      ),
    );
  }
}
