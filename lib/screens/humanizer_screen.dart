import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/toast_notification.dart';
import '../providers/humanizer_provider.dart';
import '../providers/llm_settings_provider.dart';
import '../providers/speech_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/toast_provider.dart';
import '../widgets/header_bar.dart';
import '../widgets/humanizer/comparison_view.dart';
import '../widgets/humanizer/failover_alert_banner.dart';
import '../widgets/humanizer/humanizer_input_section.dart';
import '../widgets/humanizer/tone_style_selector.dart';
import 'settings_screen.dart';

/// Dedicated screen for transforming robotic or AI-flagged writing into
/// authentic, natural human prose, organized into Studio's consistent 3-zone hierarchy.
/// Fully decoupled from Studio and Plagiarism states.
class HumanizerScreen extends StatefulWidget {
  final VoidCallback? onNavigateToStudio;
  final VoidCallback? onNavigateToSettings;

  const HumanizerScreen({
    super.key,
    this.onNavigateToStudio,
    this.onNavigateToSettings,
  });

  @override
  State<HumanizerScreen> createState() => _HumanizerScreenState();
}

class _HumanizerScreenState extends State<HumanizerScreen> {
  late final TextEditingController _inputController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    String initialText = '';
    try {
      final humanizer = Provider.of<HumanizerProvider?>(context, listen: false);
      if (humanizer != null) initialText = humanizer.inputText;
    } catch (_) {}
    _inputController = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final humanizer = Provider.of<HumanizerProvider?>(context, listen: false);
    final toast = Provider.of<ToastProvider?>(context, listen: false);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
      _inputController.text = data.text!;
      humanizer?.setInputText(data.text!);
      toast?.showToast('Pasted text from clipboard', ToastType.info);
    } else {
      toast?.showToast('Clipboard is empty', ToastType.error);
    }
  }

  Future<void> _runHumanize([String? toneOverride]) async {
    final humanizer = Provider.of<HumanizerProvider?>(context, listen: false);
    if (humanizer == null) return;
    humanizer.setInputText(_inputController.text);
    await humanizer.runHumanize(toneOverride: toneOverride);
  }

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    final humanizer = Provider.of<HumanizerProvider?>(context);
    final speech = Provider.of<SpeechProvider?>(context);
    final llmSettings = Provider.of<LlmSettingsProvider?>(context);
    final isLoading = humanizer?.isLoading ?? false;
    final isRecording = speech?.isRecording ?? false;
    final outputText = humanizer?.outputText ?? '';
    final inputText = humanizer?.inputText ?? '';

    // Keep controller in sync with provider if updated externally (like voice dictation)
    if (_inputController.text != inputText && (!_focusNode.hasFocus || isRecording)) {
      _inputController.text = inputText;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              HeaderBar(
                title: 'Humanizer',
                onSettingsPressed: widget.onNavigateToSettings ?? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Failover Session Alert Banner
              if (llmSettings != null && llmSettings.hasPendingFailover)
                FailoverAlertBanner(
                  providerName: llmSettings.pendingFailoverProvider?.name ?? '',
                  modelName: llmSettings.pendingFailoverModel ?? '',
                  onSaveDefault: () async {
                    final toast = Provider.of<ToastProvider?>(context, listen: false);
                    await llmSettings.savePendingFailoverAsDefault();
                    toast?.showToast(
                      'Saved as default model.',
                      ToastType.success,
                    );
                  },
                  onDismiss: () {
                    llmSettings.dismissPendingFailover();
                  },
                ),

              const SizedBox(height: 6),

              // ── ZONE 1: Input Section ─────────────────────────────────────
              HumanizerInputSection(
                controller: _inputController,
                focusNode: _focusNode,
                isLoading: isLoading,
                onChanged: (val) => humanizer?.setInputText(val),
                onPaste: _pasteFromClipboard,
                onClear: () {
                  _inputController.clear();
                  humanizer?.clearInput();
                },
                onHumanize: () => _runHumanize(),
              ),

              const SizedBox(height: 14),

              // ── ZONE 2: Writing Profile & Tone Selector ───────────────────
              ToneStyleSelector(
                selectedTone: humanizer?.selectedTone ?? 'professional',
                selectedStyle: humanizer?.selectedStyle ?? 'balanced',
                isLoading: isLoading,
                onToneSelected: (tone) => humanizer?.setTone(tone),
                onStyleSelected: (style) => humanizer?.setStyle(style),
              ),

              const SizedBox(height: 16),

              // ── ZONE 3: Output Area & Comparison View ─────────────────────
              ComparisonView(
                inputText: _inputController.text,
                outputText: outputText,
                isLoading: isLoading,
                outputReport: humanizer?.outputPlagiarismReport,
                inputReport: humanizer?.inputPlagiarismReport,
                semanticPreservationScore: humanizer?.preservationReport?.preservationScore,
                onReverify: () => _runHumanize(),
                onUseAsInput: () {
                  humanizer?.useOutputAsInput();
                  if (humanizer != null) {
                    _inputController.text = humanizer.inputText;
                  }
                  Provider.of<ToastProvider?>(context, listen: false)?.showToast('Applied to input editor!', ToastType.success);
                },
                onShowToast: (msg, type) => Provider.of<ToastProvider?>(context, listen: false)?.showToast(msg, type),
              ),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }
}
