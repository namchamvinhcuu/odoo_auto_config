import 'package:flutter/material.dart';

/// Shared ANSI escape code parser for terminal-style log output.
class AnsiParser {
  AnsiParser._();

  static final _regex = RegExp(r'\x1B\[[0-9;]*m');

  static const _colors = <int, Color>{
    30: Color(0xFF000000), // black
    31: Color(0xFFCD3131), // red
    32: Color(0xFF0DBC79), // green
    33: Color(0xFFE5E510), // yellow
    34: Color(0xFF2472C8), // blue
    35: Color(0xFFBC3FBC), // magenta
    36: Color(0xFF11A8CD), // cyan
    37: Color(0xFFE5E5E5), // white
    90: Color(0xFF666666), // bright black (gray)
    91: Color(0xFFF14C4C), // bright red
    92: Color(0xFF23D18B), // bright green
    93: Color(0xFFF5F543), // bright yellow
    94: Color(0xFF3B8EEA), // bright blue
    95: Color(0xFFD670D6), // bright magenta
    96: Color(0xFF29B8DB), // bright cyan
    97: Color(0xFFFFFFFF), // bright white
  };

  /// Parse a single line containing ANSI escape codes into colored [TextSpan]s.
  static List<TextSpan> parse(String line, {Color? defaultColor}) {
    final defColor = defaultColor ?? Colors.grey.shade300;
    final spans = <TextSpan>[];
    var currentColor = defColor;
    var lastEnd = 0;

    for (final match in _regex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: line.substring(lastEnd, match.start),
          style: TextStyle(color: currentColor),
        ));
      }
      final code = match.group(0)!;
      final params = code.substring(2, code.length - 1).split(';');
      for (final p in params) {
        final n = int.tryParse(p) ?? 0;
        if (n == 0) {
          currentColor = defColor;
        } else if (_colors.containsKey(n)) {
          currentColor = _colors[n]!;
        }
      }
      lastEnd = match.end;
    }
    if (lastEnd < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastEnd),
        style: TextStyle(color: currentColor),
      ));
    }
    return spans.isEmpty
        ? [TextSpan(text: line, style: TextStyle(color: defColor))]
        : spans;
  }
}
