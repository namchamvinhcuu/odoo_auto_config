import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

enum StatusType { success, error, warning, loading, info }

class StatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final StatusType status;
  final Widget? trailing;

  const StatusCard({
    super.key,
    required this.title,
    this.subtitle = '',
    this.status = StatusType.info,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: 0),
      child: ListTile(
        leading: _buildIcon(),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
        trailing: trailing,
      ),
    );
  }

  Widget _buildIcon() {
    switch (status) {
      case StatusType.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: AppIconSize.xl);
      case StatusType.error:
        return const Icon(Icons.cancel, color: Colors.red, size: AppIconSize.xl);
      case StatusType.warning:
        return const Icon(Icons.warning, color: Colors.orange, size: AppIconSize.xl);
      case StatusType.loading:
        return const SizedBox(
          width: AppIconSize.xl,
          height: AppIconSize.xl,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StatusType.info:
        return const Icon(Icons.info, color: Colors.blue, size: AppIconSize.xl);
    }
  }
}
