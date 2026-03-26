import 'package:flutter/material.dart';

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
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
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
        return const Icon(Icons.check_circle, color: Colors.green, size: 28);
      case StatusType.error:
        return const Icon(Icons.cancel, color: Colors.red, size: 28);
      case StatusType.warning:
        return const Icon(Icons.warning, color: Colors.orange, size: 28);
      case StatusType.loading:
        return const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case StatusType.info:
        return const Icon(Icons.info, color: Colors.blue, size: 28);
    }
  }
}
