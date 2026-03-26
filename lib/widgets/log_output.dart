import 'package:flutter/material.dart';

class LogOutput extends StatefulWidget {
  final List<String> lines;
  final double height;

  const LogOutput({
    super.key,
    required this.lines,
    this.height = 250,
  });

  @override
  State<LogOutput> createState() => _LogOutputState();
}

class _LogOutputState extends State<LogOutput> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant LogOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length > oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: widget.lines.isEmpty
          ? const Center(
              child: Text(
                'No output yet...',
                style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                return Text(
                  line,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: _getLineColor(line),
                  ),
                );
              },
            ),
    );
  }

  Color _getLineColor(String line) {
    if (line.startsWith('[+]')) return Colors.greenAccent;
    if (line.startsWith('[-]') || line.startsWith('[ERROR]')) {
      return Colors.redAccent;
    }
    if (line.startsWith('[=]') || line.startsWith('[WARN]')) {
      return Colors.orangeAccent;
    }
    return Colors.grey.shade300;
  }
}
