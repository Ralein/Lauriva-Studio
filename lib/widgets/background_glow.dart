import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/theme_provider.dart';

/// App background — pure flat solid background with zero gradients.
/// Dark mode: solid obsidian slate (#0F1216).
/// Light mode: clean airy off-white (#F8FAF9).
class BackgroundGlow extends StatelessWidget {
  final Widget child;

  const BackgroundGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.bgCenter,
      child: child,
    );
  }
}
