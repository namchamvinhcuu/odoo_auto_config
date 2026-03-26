import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../models/python_info.dart';
import '../services/python_checker_service.dart';
import '../widgets/status_card.dart';

class PythonCheckScreen extends StatefulWidget {
  const PythonCheckScreen({super.key});

  @override
  State<PythonCheckScreen> createState() => _PythonCheckScreenState();
}

class _PythonCheckScreenState extends State<PythonCheckScreen> {
  final _checker = PythonCheckerService();
  List<PythonInfo>? _results;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _checker.detectAll();
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search, size: AppIconSize.xl),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Python Configuration Check',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _loading ? null : _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('Rescan'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Detect installed Python versions, pip, and venv module availability.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (_loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: AppSpacing.lg),
                    Text('Scanning for Python installations...'),
                  ],
                ),
              ),
            )
          else if (_error != null)
            StatusCard(
              title: 'Error',
              subtitle: _error!,
              status: StatusType.error,
            )
          else if (_results != null && _results!.isEmpty)
            const StatusCard(
              title: 'No Python Found',
              subtitle:
                  'No Python installation detected. Please install Python 3.8+.',
              status: StatusType.warning,
            )
          else if (_results != null)
            Expanded(
              child: ListView.builder(
                itemCount: _results!.length,
                itemBuilder: (context, index) {
                  final info = _results![index];
                  return _buildPythonCard(info);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPythonCard(PythonInfo info) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code, color: Colors.blue),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Python ${info.version}',
                  style: const TextStyle(
                    fontSize: AppFontSize.xxl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Path: ${info.executablePath}',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _buildChip(
                  'pip ${info.pipVersion}',
                  info.hasPip,
                ),
                const SizedBox(width: AppSpacing.sm),
                _buildChip(
                  'venv module',
                  info.hasVenv,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool available) {
    return Chip(
      avatar: Icon(
        available ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: available ? Colors.green : Colors.red,
      ),
      label: Text(label),
      backgroundColor: available
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
    );
  }
}
