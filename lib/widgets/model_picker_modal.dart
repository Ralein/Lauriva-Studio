import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/llm_provider.dart';
import '../providers/llm_settings_provider.dart';
import '../providers/theme_provider.dart';
import 'lauriva_skeleton.dart';

void showModelPickerModal({
  required BuildContext context,
  required LlmProvider provider,
  required String currentModel,
  required ValueChanged<String> onModelSelected,
  String? apiKey,
  String? customBaseUrl,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ModelPickerModal(
      provider: provider,
      currentModel: currentModel,
      onModelSelected: onModelSelected,
      apiKey: apiKey,
      customBaseUrl: customBaseUrl,
    ),
  );
}

class ModelPickerModal extends StatefulWidget {
  final LlmProvider provider;
  final String currentModel;
  final ValueChanged<String> onModelSelected;
  /// The key to live-fetch models with. Callers should pass whatever is
  /// currently typed in their API key field — even if unsaved — so the
  /// catalog reflects the key the user just pasted, not a stale saved one.
  final String? apiKey;
  final String? customBaseUrl;

  const ModelPickerModal({
    super.key,
    required this.provider,
    required this.currentModel,
    required this.onModelSelected,
    this.apiKey,
    this.customBaseUrl,
  });

  @override
  State<ModelPickerModal> createState() => _ModelPickerModalState();
}

enum ModelFilterType {
  all,
  freeOnly,
  paidOnly,
  reasoning,
  fast,
}

class _ModelPickerModalState extends State<ModelPickerModal> {
  late final TextEditingController _searchController;
  late final TextEditingController _customModelController;
  late final TextEditingController _apiKeyController;
  late List<LlmModelInfo> _models;
  // Local mirror of the selected model id. Needed separately from
  // `widget.currentModel` because a post-fetch auto-selection happens while
  // this modal is still open — updating the parent's state alone wouldn't
  // rebuild this already-mounted widget with a new `currentModel`.
  late String _selectedModelId;
  bool _isLoadingLive = false;
  ModelFilterType _activeFilter = ModelFilterType.all;
  bool _showCustomInput = false;

  bool get _hasUsableKey =>
      !widget.provider.requiresKey || _apiKeyController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _customModelController = TextEditingController();
    final existingKey = (widget.apiKey != null && widget.apiKey!.trim().isNotEmpty)
        ? widget.apiKey!.trim()
        : context.read<LlmSettingsProvider>().getApiKeyForProvider(widget.provider.id);
    _apiKeyController = TextEditingController(text: existingKey);
    _selectedModelId = widget.currentModel;

    // Do not show or initialize models until an API key is available
    if (_hasUsableKey) {
      _models = List.from(widget.provider.models);
      if (widget.provider.supportsModelDiscovery) {
        _fetchLiveCatalog();
      }
    } else {
      _models = [];
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customModelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _selectModel(String modelId) {
    setState(() => _selectedModelId = modelId);
    context.read<LlmSettingsProvider>().setModelForProvider(widget.provider.id, modelId);
    widget.onModelSelected(modelId);
  }

  Future<void> _fetchLiveCatalog([String? keyOverride]) async {
    setState(() {
      _isLoadingLive = true;
    });

    final effectiveKey = keyOverride ??
        (_apiKeyController.text.trim().isNotEmpty
            ? _apiKeyController.text.trim()
            : (widget.apiKey ?? ''));

    final llmSettings = context.read<LlmSettingsProvider>();
    final liveModels = await llmSettings.fetchLiveModelsFor(
      provider: widget.provider,
      apiKey: effectiveKey,
      customBaseUrl: widget.customBaseUrl,
    );

    if (!mounted) return;
    setState(() {
      _isLoadingLive = false;
      if (liveModels.isNotEmpty) {
        _models = liveModels;
      } else if (_models.isEmpty) {
        _models = List.from(widget.provider.models);
      }
    });

    if (liveModels.isEmpty) return;
    // Always fetch, then always resolve to a real pick from that catalog —
    // never leave the selection dangling on a stale/default model id just
    // because nobody tapped a row.
    final bestId = await llmSettings.selectBestModel(
      provider: widget.provider,
      liveModels: liveModels,
      currentModel: _selectedModelId,
    );
    if (mounted && bestId != _selectedModelId) {
      setState(() => _selectedModelId = bestId);
      widget.onModelSelected(bestId);
    }
  }

  List<LlmModelInfo> get _filteredModels {
    final query = _searchController.text.trim().toLowerCase();
    return _models.where((model) {
      switch (_activeFilter) {
        case ModelFilterType.freeOnly:
          if (!model.isFree) return false;
          break;
        case ModelFilterType.paidOnly:
          if (model.isFree) return false;
          break;
        case ModelFilterType.reasoning:
          if (model.category != 'reasoning') return false;
          break;
        case ModelFilterType.fast:
          if (model.category != 'fast') return false;
          break;
        case ModelFilterType.all:
          break;
      }
      if (query.isEmpty) return true;
      return model.name.toLowerCase().contains(query) ||
          model.id.toLowerCase().contains(query) ||
          model.description.toLowerCase().contains(query) ||
          model.category.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    try {
      context.watch<ThemeProvider>();
    } catch (_) {}
    final mediaQuery = MediaQuery.of(context);
    final displayedModels = _filteredModels;
    final availableHeight = (mediaQuery.size.height -
            mediaQuery.viewInsets.bottom -
            mediaQuery.padding.top -
            32)
        .clamp(280.0, 680.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: mediaQuery.viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: 600, maxHeight: availableHeight),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.glassBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGlow,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.hub_rounded,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.provider.name} Models',
                                        style: GoogleFonts.outfit(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Choose from curated or live 700+ catalog',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12.5,
                                          color: AppColors.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Open ${widget.provider.name} Catalog',
                                onPressed: () async {
                                  final uri = Uri.parse(widget.provider.catalogUrl);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: Icon(LucideIcons.externalLink, size: 18, color: AppColors.primary),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),

                    const SizedBox(height: 14),

                    if (!_hasUsableKey)
                      _buildApiKeyRequiredView()
                    else ...[
                      // Search & Live Fetch Row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.glassInputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: TextField(
                              controller: _searchController,
                              onChanged: (_) => setState(() {}),
                              style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search models (e.g. llama, r1, flash)...',
                                hintStyle: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted),
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear_rounded, size: 16, color: AppColors.textMuted),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        if (widget.provider.supportsModelDiscovery) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isLoadingLive ? null : _fetchLiveCatalog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentGlow,
                              foregroundColor: AppColors.accent,
                              side: BorderSide(color: AppColors.accent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                            icon: _isLoadingLive
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                  )
                                : const Icon(Icons.cloud_download_rounded, size: 16),
                            label: Text(
                              _isLoadingLive ? 'Fetching...' : 'Fetch Live',
                              style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Filter Chips Row
                    // Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('All (${_models.length})', ModelFilterType.all, AppColors.primary),
                          const SizedBox(width: 8),
                          _buildFilterChip('Free Only (${_models.where((m) => m.isFree).length})', ModelFilterType.freeOnly, AppColors.accent),
                          const SizedBox(width: 8),
                          _buildFilterChip('Paid / Pro (${_models.where((m) => !m.isFree).length})', ModelFilterType.paidOnly, const Color(0xFFF59E0B)),
                          const SizedBox(width: 8),
                          _buildFilterChip('Reasoning (${_models.where((m) => m.category == 'reasoning').length})', ModelFilterType.reasoning, const Color(0xFF8B5CF6)),
                          const SizedBox(width: 8),
                          _buildFilterChip('Fast (${_models.where((m) => m.category == 'fast').length})', ModelFilterType.fast, const Color(0xFF06B6D4)),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            onPressed: () => setState(() => _showCustomInput = !_showCustomInput),
                            icon: Icon(
                              _showCustomInput ? Icons.remove_rounded : Icons.add_rounded,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            label: Text(
                              'Custom Model',
                              style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Optional Custom Model ID Input
                    if (_showCustomInput) ...[
                      const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.glassInputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.glassBorder),
                          ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _customModelController,
                                style: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'Enter exact model ID (e.g. gpt-4o, qwen-2.5-coder)',
                                  hintStyle: GoogleFonts.outfit(fontSize: 13.5, color: AppColors.textMuted),
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                final customId = _customModelController.text.trim();
                                if (customId.isNotEmpty) {
                                  _selectModel(customId);
                                  Navigator.of(context).pop();
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                'Use Model',
                                style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Scrollable List of Models
                    Expanded(
                      child: displayedModels.isEmpty
                          ? (_isLoadingLive
                              ? const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LaurivaListSkeleton(itemCount: 5, itemHeight: 68),
                                )
                              : Center(
                                  child: Text(
                                    'No matching models found.',
                                    style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textMuted),
                                  ),
                                ))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: displayedModels.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final model = displayedModels[index];
                                final isSelected = _selectedModelId == model.id;

                                return InkWell(
                                  onTap: () {
                                    _selectModel(model.id);
                                    Navigator.of(context).pop();
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.primaryGlow
                                            : AppColors.surfaceSubtle,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.glassBorder,
                                        ),
                                      ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked_rounded
                                              : Icons.radio_button_off_rounded,
                                          size: 18,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.textMuted,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  Text(
                                                    model.name,
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (model.isFree)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.accentGlow,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: AppColors.accent, width: 0.8),
                                                      ),
                                                      child: Text(
                                                        'FREE',
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 13.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: AppColors.accent,
                                                        ),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                                      ),
                                                      child: Text(
                                                        'PAID / PRO',
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: const Color(0xFFF59E0B),
                                                        ),
                                                      ),
                                                    ),
                                                  if (model.tag != null && model.tag != 'Free')
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primaryGlow,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        model.tag!,
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                          color: AppColors.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  if (model.contextWindow != null)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.surfaceSubtle,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: AppColors.glassBorder),
                                                      ),
                                                      child: Text(
                                                        '${model.contextWindow! >= 1000000 ? "${(model.contextWindow! / 1000000).toStringAsFixed(0)}M" : "${(model.contextWindow! / 1000).toStringAsFixed(0)}k"} ctx',
                                                        style: GoogleFonts.outfit(
                                                          fontSize: 11,
                                                          color: AppColors.textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                model.id,
                                                style: GoogleFonts.firaCode(
                                                  fontSize: 11.5,
                                                  color: AppColors.textMuted,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (model.description.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  model.description,
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 11,
                                                    color: AppColors.textSecondary,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () async {
                                            final url = widget.provider.getModelDocumentationUrl(model.id);
                                            final uri = Uri.parse(url);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(6),
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              LucideIcons.externalLink,
                                              size: 14,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, ModelFilterType filter, Color activeColor) {
    final isSelected = _activeFilter == filter;
    return FilterChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _activeFilter = filter),
      label: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? activeColor : AppColors.textSecondary,
        ),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      backgroundColor: AppColors.surfaceSubtle,
      selectedColor: activeColor.withValues(alpha: 0.18),
      checkmarkColor: activeColor,
      side: BorderSide(
        color: isSelected ? activeColor : AppColors.glassBorder,
      ),
    );
  }

  Widget _buildApiKeyRequiredView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.keyRound, size: 24, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'API Key Required',
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Paste your ${widget.provider.name} API key to fetch and browse available models.',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textMuted,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: AppColors.glassInputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: GoogleFonts.jetBrainsMono(fontSize: 13.5, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: widget.provider.keyHint.isNotEmpty
                          ? widget.provider.keyHint
                          : 'Paste API Key...',
                      hintStyle: GoogleFonts.jetBrainsMono(fontSize: 13.5, color: AppColors.textMuted),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.clipboard, size: 14),
                  color: AppColors.primary,
                  tooltip: 'Paste from clipboard',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
                      setState(() {
                        _apiKeyController.text = data.text!.trim();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _isLoadingLive
                ? null
                : () async {
                    final key = _apiKeyController.text.trim();
                    if (key.isEmpty) return;
                    context.read<LlmSettingsProvider>().setApiKeyForProvider(widget.provider.id, key);
                    setState(() {});
                    await _fetchLiveCatalog(key);
                  },
            icon: _isLoadingLive
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.cloudDownload, size: 15),
            label: Text(
              _isLoadingLive ? 'Fetching Models...' : 'Fetch Models',
              style: GoogleFonts.outfit(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
