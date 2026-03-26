import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class DirectoryPickerField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: value),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            readOnly: true,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () async {
            final path = await FilePicker.platform.getDirectoryPath(
              dialogTitle: label,
            );
            if (path != null) {
              onChanged(path);
            }
          },
          icon: const Icon(Icons.folder_open),
          tooltip: 'Browse...',
        ),
      ],
    );
  }
}
