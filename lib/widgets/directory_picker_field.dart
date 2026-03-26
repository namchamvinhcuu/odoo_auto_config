import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class DirectoryPickerField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const DirectoryPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<DirectoryPickerField> createState() => _DirectoryPickerFieldState();
}

class _DirectoryPickerFieldState extends State<DirectoryPickerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant DirectoryPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () async {
            final path = await FilePicker.platform.getDirectoryPath(
              dialogTitle: widget.label,
            );
            if (path != null) {
              _controller.text = path;
              widget.onChanged(path);
            }
          },
          icon: const Icon(Icons.folder_open),
          tooltip: 'Browse...',
        ),
      ],
    );
  }
}
