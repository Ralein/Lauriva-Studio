import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../constants/app_colors.dart';
import '../../providers/llm_settings_provider.dart';

/// Collapsible Advanced Parameters panel (Temperature, Max Tokens, Auto-Failover).
class AdvancedParamsSection extends StatefulWidget {
  final LlmSettingsProvider llmSettings;

  const AdvancedParamsSection({
    super.key,
    required this.llmSettings,
  });

  @override
  State<AdvancedParamsSection> createState() => _AdvancedParamsSectionState();
}

class _AdvancedParamsSectionState extends State<AdvancedParamsSection> {
  bool _showAdvancedParams = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _showAdvancedParams = !_showAdvancedParams),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              Text(
                'ADVANCED PARAMETERS',
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Icon(
                _showAdvancedParams ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        if (_showAdvancedParams) ...[
          const SizedBox(height: 12),
          _buildSliderRow(
            'Temperature',
            widget.llmSettings.temperature,
            0.0,
            2.0,
            (v) => widget.llmSettings.setTemperature(v),
            subtitle: 'Controls randomness. Higher = more creative.',
          ),
          const SizedBox(height: 12),
          _buildSliderRow(
            'Max Tokens',
            widget.llmSettings.maxTokens.toDouble(),
            256,
            8192,
            (v) => widget.llmSettings.setMaxTokens(v.round()),
            subtitle: 'Maximum response length.',
            divisions: 31,
            valueFormatter: (v) => v.round().toString(),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Smart Auto-Failover',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Automatically fall over to alternate free providers when rate limited or unavailable.',
              style: GoogleFonts.outfit(fontSize: 12.5, color: AppColors.textMuted),
            ),
            value: widget.llmSettings.autoFailover,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => widget.llmSettings.setAutoFailover(v),
          ),
        ],
      ],
    );
  }


  Widget _buildSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String? subtitle,
    int? divisions,
    String Function(double)? valueFormatter,
  }) {
    final formatted = valueFormatter != null
        ? valueFormatter(value)
        : value.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                formatted,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.glassBorder,
        ),
      ],
    );
  }
}
