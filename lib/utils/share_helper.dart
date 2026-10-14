import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrapper around share_plus v13+ for native OS share sheet integration.
class ShareHelper {
  ShareHelper._();

  /// Share plain text via the native OS share sheet.
  static Future<void> shareText({
    required String title,
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: title,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Share a forensic executive summary with score data.
  static Future<void> shareForensicSummary({
    required String inputText,
    required double aiScore,
    required double plagiarismScore,
    Rect? sharePositionOrigin,
  }) async {
    final aiPercent = (aiScore * 100).toStringAsFixed(1);
    final humanPercent = ((1.0 - aiScore) * 100).clamp(0.0, 100.0).toStringAsFixed(1);
    final plagPercent = (plagiarismScore * 100).toStringAsFixed(1);
    final origPercent = ((1.0 - plagiarismScore) * 100).clamp(0.0, 100.0).toStringAsFixed(1);
    final wordCount = inputText.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final isClean = aiScore < 0.35 && plagiarismScore < 0.15;
    final isModerate = aiScore < 0.65 && plagiarismScore < 0.30;
    final verdictEmoji = isClean ? '✅' : (isModerate ? '⚖️' : '⚠️');
    final verdictLabel = isClean
        ? 'AUTHENTIC HUMAN PROSE ($humanPercent%)'
        : (isModerate ? 'MIXED / PARTIAL AI ($aiPercent%)' : 'AI-GENERATED ($aiPercent%)');

    final cleanExcerpt = inputText.trim();
    final excerptSnippet = cleanExcerpt.length > 180
        ? '${cleanExcerpt.substring(0, 180)}…'
        : cleanExcerpt;

    final summary = '''
🛡️ *LAURIVA FORENSIC AUDIT SUMMARY*
─────────────────────────────
$verdictEmoji *Verdict:* $verdictLabel
📊 *AI Authorship:* $aiPercent%
🌿 *Human Authenticity:* $humanPercent%
🔍 *Literature Overlap:* $plagPercent% ($origPercent% Original)
📝 *Document Scope:* $wordCount words

💬 *Passage Excerpt:*
_"$excerptSnippet"_

─────────────────────────────
✨ *Audited with Lauriva* · Deep Forensic & Literature Intelligence
'''.trim();

    await SharePlus.instance.share(
      ShareParams(
        text: summary,
        subject: 'Lauriva Forensic Audit Report',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Share humanized text with a brief context note.
  static Future<void> shareHumanizedText({
    required String text,
    Rect? sharePositionOrigin,
  }) async {
    final cleanText = text.trim();
    final wordCount = cleanText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final formatted = '''
🌿 *HUMANIZED DOCUMENT*
─────────────────────────────
$cleanText

─────────────────────────────
📝 $wordCount words · Audited & Humanized via Lauriva Studio
'''.trim();

    await SharePlus.instance.share(
      ShareParams(
        text: formatted,
        subject: 'Humanized Text — Lauriva Studio',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  /// Share an academic markdown document with embedded references / bibliography.
  static Future<void> shareMarkdownWithBibliography({
    required String title,
    required String markdownContent,
    required String bibliography,
    Rect? sharePositionOrigin,
  }) async {
    final fullDocument = '''
# $title

$markdownContent

─────────────────────────────
## Works Cited & References

$bibliography

─────────────────────────────
✨ Verified by Lauriva Academic & Forensic Intelligence
'''.trim();

    await SharePlus.instance.share(
      ShareParams(
        text: fullDocument,
        subject: title,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
