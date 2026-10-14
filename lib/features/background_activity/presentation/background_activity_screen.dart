import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../constants/app_colors.dart';
import '../../../widgets/background_glow.dart';
import '../../../widgets/glass_card.dart';
import '../../../widgets/header_bar.dart';
import '../domain/background_task.dart';
import '../domain/background_task_status.dart';
import 'background_activity_controller.dart';

/// Luxury dashboard providing visibility, permission controls, platform insights,
/// and history for Lauriva's native background processing.
class BackgroundActivityScreen extends StatelessWidget {
  const BackgroundActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BackgroundActivityController>();
    final currentTask = controller.currentTask;
    final isRunning = controller.isRunning;

    return Scaffold(
      body: BackgroundGlow(
        child: SafeArea(
          child: Column(
            children: [
              HeaderBar(
                title: 'Background Activity',
                showSettings: false,
                showHistory: false,
                leading: IconButton(
                  icon: Icon(LucideIcons.arrowLeft, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                trailing: isRunning
                    ? null
                    : IconButton(
                        icon: Icon(LucideIcons.play, size: 18),
                        onPressed: () => controller.simulateTestTask(),
                      ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Hero Status Card (Running or Idle)
                        _buildHeroStatusCard(context, controller, currentTask),

                        const SizedBox(height: 18),

                        // 2. Notification Preferences & System Permissions
                        _buildNotificationControlCard(context, controller),

                        const SizedBox(height: 18),

                        // 3. Platform Capabilities & Architecture Explainer
                        _buildPlatformArchitectureCard(context),

                        const SizedBox(height: 18),

                        // 4. Task Execution History
                        _buildActivityHistorySection(context, controller),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Active execution state or system idle hero card.
  Widget _buildHeroStatusCard(
    BuildContext context,
    BackgroundActivityController controller,
    BackgroundTask? currentTask,
  ) {
    final isRunning = controller.isRunning && currentTask != null;

    if (isRunning) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.glassBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.paletteTeal.withValues(alpha: 0.5),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.paletteTeal.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.paletteTeal.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.loader2,
                    size: 18,
                    color: AppColors.paletteTeal,
                  )
                          .animate(onPlay: (c) => c.repeat())
                          .rotate(duration: 1200.ms),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'CURRENT ACTIVITY',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.paletteTeal,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusPill(currentTask.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentTask.title,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  currentTask.formattedProgress,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.paletteTeal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: currentTask.progress > 0 ? currentTask.progress : null,
                minHeight: 6,
                backgroundColor: AppColors.textMuted.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.paletteTeal,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    currentTask.stage ?? 'Processing document audit…',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Elapsed: ${currentTask.formattedDuration}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => controller.cancelCurrentTask(),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.x,
                          size: 13,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Cancel',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Idle Hero
    final lastTime = controller.lastActivityTime;
    final lastTimeFormatted = lastTime != null
        ? _formatRelativeTime(lastTime)
        : 'None recently';

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.checkCircle2,
                  size: 18,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS: IDLE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All Forensic Tasks Completed',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.simulateTestTask(),
                icon: Icon(LucideIcons.play, size: 12),
                label: Text(
                  'Test Run',
                  style: GoogleFonts.outfit(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.paletteTeal,
                  side: BorderSide(
                    color: AppColors.paletteTeal.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.clock, size: 13, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Last Activity:',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lastTimeFormatted,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Notification preference and operating-system permission management.
  Widget _buildNotificationControlCard(
    BuildContext context,
    BackgroundActivityController controller,
  ) {
    final hasPerm = controller.hasNotificationPermission;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.paletteCerulean.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.bell,
                  size: 16,
                  color: AppColors.paletteCerulean,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background Notifications',
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Live alerts when analyzing or matching in background',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.notificationsEnabled,
                onChanged: (val) => controller.toggleNotifications(val),
                activeThumbColor: AppColors.paletteTeal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasPerm
                    ? AppColors.success.withValues(alpha: 0.3)
                    : AppColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasPerm ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                  size: 16,
                  color: hasPerm ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPerm
                            ? 'Operating System Permission: Granted'
                            : 'Operating System Permission: Required',
                        style: GoogleFonts.outfit(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: hasPerm
                              ? AppColors.textPrimary
                              : AppColors.warning,
                        ),
                      ),
                      Text(
                        hasPerm
                            ? 'Lauriva has permission to dispatch progress notifications.'
                            : 'Notification permission is required on Android 13+ and iOS.',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hasPerm)
                  TextButton(
                    onPressed: () => controller.requestNotificationPermission(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Grant',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.paletteTeal,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Platform architecture explainer detailing Android vs iOS background execution.
  Widget _buildPlatformArchitectureCard(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.paletteTeal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.cpu,
                  size: 16,
                  color: AppColors.paletteTeal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Platform Execution & Capabilities',
                      style: GoogleFonts.outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'How Android & iOS manage on-device AI tasks',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Notifications report actual progress, but the mobile OS governs background execution lifetime:',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _buildPlatformDetailRow(
            icon: LucideIcons.smartphone,
            platform: 'Android Architecture',
            detail: 'Uses foreground services with active progress notifications. Android 13+ enforces POST_NOTIFICATIONS, and Doze mode can defer CPU cycles when the device is locked.',
          ),
          const SizedBox(height: 8),
          _buildPlatformDetailRow(
            icon: LucideIcons.apple,
            platform: 'iOS Architecture',
            detail: 'Suspends background isolates shortly after leaving the app. BGTaskScheduler manages scheduled work non-deterministically. On-device ONNX inference is memory-monitored.',
          ),
          const SizedBox(height: 8),
          _buildPlatformDetailRow(
            icon: LucideIcons.shieldCheck,
            platform: 'Lauriva Interruption Recovery',
            detail: 'If the operating system terminates the process during analysis, Lauriva automatically marks the task as Interrupted upon relaunch and preserves your document state.',
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformDetailRow({
    required IconData icon,
    required String platform,
    required String detail,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.paletteTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// History of completed, interrupted, and failed activities.
  Widget _buildActivityHistorySection(
    BuildContext context,
    BackgroundActivityController controller,
  ) {
    final tasks = controller.recentTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACTIVITY HISTORY (${tasks.length})',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            if (tasks.isNotEmpty)
              InkWell(
                onTap: () => controller.clearHistory(),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.trash2,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Clear',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.glassBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.inbox, size: 28, color: AppColors.textMuted),
                const SizedBox(height: 8),
                Text(
                  'No activity recorded yet',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _buildTaskHistoryItem(task);
            },
          ),
      ],
    );
  }

  Widget _buildTaskHistoryItem(BackgroundTask task) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: task.status == BackgroundTaskStatus.interrupted
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.glassBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildStatusPill(task.status),
            ],
          ),
          const SizedBox(height: 4),
          if (task.stage != null && task.stage!.isNotEmpty)
            Text(
              task.stage!,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          if (task.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                task.errorMessage!,
                style: GoogleFonts.outfit(
                  fontSize: 11.5,
                  color: AppColors.warning,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTimestamp(task.startedAt),
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                'Duration: ${task.formattedDuration}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BackgroundTaskStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: status.color.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Text(
        status.badgeText,
        style: GoogleFonts.outfit(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: status.color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatTimestamp(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '${time.month}/${time.day} $hour:$minute:$second';
  }
}
