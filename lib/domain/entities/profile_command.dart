// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// A value that a profile command template can substitute at send time.
///
/// Deliberately a *small, documented* set instead of a general-purpose
/// scripting language: a device profile may only inject the values the app
/// actually knows. Anything else must be a literal byte.
enum ProfileValue {
  brightness('brightness'),
  red('red'),
  green('green'),
  blue('blue'),
  checksum('checksum');

  const ProfileValue(this.id);

  final String id;

  /// Resolves a token name (including the documented short aliases) to a value.
  static ProfileValue? fromToken(String name) {
    switch (name.toLowerCase()) {
      case 'brightness':
      case 'bright':
        return ProfileValue.brightness;
      case 'red':
      case 'r':
        return ProfileValue.red;
      case 'green':
      case 'g':
        return ProfileValue.green;
      case 'blue':
      case 'b':
        return ProfileValue.blue;
      case 'checksum':
      case 'xor':
        return ProfileValue.checksum;
      default:
        return null;
    }
  }

  static ProfileValue? fromId(String id) {
    for (final v in ProfileValue.values) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// Byte width and endianness of a numeric placeholder or notification field.
enum NumericWidth {
  u8('u8', 1),
  u16le('u16le', 2),
  u16be('u16be', 2);

  const NumericWidth(this.id, this.byteLength);

  final String id;
  final int byteLength;

  /// Resolves [id], falling back to [NumericWidth.u8] for unknown values.
  static NumericWidth fromId(String? id) {
    for (final w in NumericWidth.values) {
      if (w.id == id) return w;
    }
    return NumericWidth.u8;
  }

  /// Whether [id] names a known width.
  static bool isKnown(String id) =>
      NumericWidth.values.any((w) => w.id == id.toLowerCase());
}

/// One element of a [CommandTemplate].
sealed class CommandToken {
  const CommandToken();
}

/// A fixed byte, written verbatim.
class LiteralByte extends CommandToken {
  final int value;

  const LiteralByte(this.value);

  @override
  bool operator ==(Object other) =>
      other is LiteralByte && other.value == value;

  @override
  int get hashCode => Object.hash(LiteralByte, value);

  @override
  String toString() => value.toRadixString(16).padLeft(2, '0').toUpperCase();
}

/// A dynamic byte (or byte pair) sourced from the command being sent.
class CommandPlaceholder extends CommandToken {
  final ProfileValue value;
  final NumericWidth width;

  const CommandPlaceholder(this.value, [this.width = NumericWidth.u8]);

  @override
  bool operator ==(Object other) =>
      other is CommandPlaceholder &&
      other.value == value &&
      other.width == width;

  @override
  int get hashCode => Object.hash(CommandPlaceholder, value, width);

  @override
  String toString() {
    final base = '{${value.id}}';
    if (value == ProfileValue.checksum || width == NumericWidth.u8) return base;
    return '{${value.id}:${width.id}}';
  }
}

/// The outcome of parsing a template: either a [template] or an [error].
class TemplateParseResult {
  final CommandTemplate? template;
  final String? error;

  const TemplateParseResult._(this.template, this.error);

  const TemplateParseResult.ok(CommandTemplate template)
    : this._(template, null);

  const TemplateParseResult.fail(String error) : this._(null, error);

  bool get isOk => template != null;
}

/// A small, validated command encoding.
///
/// Text syntax (whitespace separated, case-insensitive):
///
/// - `0A` — a literal byte (exactly two hex digits)
/// - `{brightness}`, `{red}`, `{green}`, `{blue}` — a dynamic byte
/// - `{brightness:u16le}`, `{red:u16be}` — a 16-bit value with an explicit
///   byte order
/// - `{checksum}` — the XOR of every preceding byte; must be the final token
///
/// Examples:
///
/// - `A0 {brightness} {checksum}`
/// - `7E FF 02 {red} {green} {blue} EF`
/// - `01 {brightness:u16le}`
class CommandTemplate {
  final List<CommandToken> tokens;

  const CommandTemplate(this.tokens);

  /// Total number of bytes this template produces.
  int get byteLength => tokens.fold<int>(
    0,
    (sum, t) =>
        sum +
        switch (t) {
          LiteralByte() => 1,
          CommandPlaceholder(:final width) => width.byteLength,
        },
  );

  /// The distinct dynamic values this template requires.
  Set<ProfileValue> get placeholders => {
    for (final t in tokens)
      if (t is CommandPlaceholder) t.value,
  };

  /// Encodes the template into bytes.
  ///
  /// Missing values throw a [StateError]; numeric values outside the width's
  /// range are clamped rather than wrapped. A `checksum` placeholder is the
  /// XOR of every byte written before it.
  Uint8List encode(Map<ProfileValue, int> values) {
    final out = <int>[];
    for (final token in tokens) {
      switch (token) {
        case LiteralByte(:final value):
          out.add(value & 0xFF);
        case CommandPlaceholder(:final value, :final width):
          if (value == ProfileValue.checksum) {
            var xor = 0;
            for (final b in out) {
              xor ^= b;
            }
            out.add(xor & 0xFF);
          } else {
            final v = values[value];
            if (v == null) {
              throw StateError('Missing value for placeholder ${value.id}');
            }
            _writeNumber(out, v, width);
          }
      }
    }
    return Uint8List.fromList(out);
  }

  /// Renders the template back to its canonical text form.
  String toText() => tokens.map((t) => t.toString()).join(' ');

  static void _writeNumber(List<int> out, int value, NumericWidth width) {
    final clamped = value.clamp(0, width == NumericWidth.u8 ? 0xFF : 0xFFFF);
    switch (width) {
      case NumericWidth.u8:
        out.add(clamped & 0xFF);
      case NumericWidth.u16le:
        out
          ..add(clamped & 0xFF)
          ..add((clamped >> 8) & 0xFF);
      case NumericWidth.u16be:
        out
          ..add((clamped >> 8) & 0xFF)
          ..add(clamped & 0xFF);
    }
  }

  /// The placeholders that require a supplied value (everything but checksum).
  Set<ProfileValue> get requiredValues => {
    for (final t in tokens)
      if (t is CommandPlaceholder && t.value != ProfileValue.checksum) t.value,
  };

  /// Parses and validates a template.
  ///
  /// [allowed] restricts which placeholders are meaningful for this command
  /// (for example, a colour template allows `red`/`green`/`blue` but not
  /// `brightness`), so a mapping that could never be executed is rejected up
  /// front instead of failing silently on the device.
  static TemplateParseResult parse(
    String source, {
    Set<ProfileValue> allowed = const {
      ProfileValue.brightness,
      ProfileValue.red,
      ProfileValue.green,
      ProfileValue.blue,
      ProfileValue.checksum,
    },
  }) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return const TemplateParseResult.fail('Command template is empty.');
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final tokens = <CommandToken>[];

    for (final part in parts) {
      if (part.startsWith('{')) {
        if (!part.endsWith('}')) {
          return TemplateParseResult.fail(
            'Unterminated placeholder "$part" (expected a closing "}").',
          );
        }
        final inner = part.substring(1, part.length - 1).trim();
        if (inner.isEmpty) {
          return const TemplateParseResult.fail('Empty placeholder "{}".');
        }
        final segments = inner.split(':');
        if (segments.length > 2) {
          return TemplateParseResult.fail(
            'Placeholder "$part" has too many ":" separators.',
          );
        }
        final value = ProfileValue.fromToken(segments[0].trim());
        if (value == null) {
          return TemplateParseResult.fail(
            'Unknown placeholder "{$inner}". Supported values: '
            'brightness, red, green, blue, checksum.',
          );
        }
        if (!allowed.contains(value)) {
          return TemplateParseResult.fail(
            'Placeholder "{${segments[0].trim()}}" is not valid for this command.',
          );
        }
        var width = NumericWidth.u8;
        if (segments.length == 2 && segments[1].trim().isNotEmpty) {
          final raw = segments[1].trim();
          if (!NumericWidth.isKnown(raw)) {
            return TemplateParseResult.fail(
              'Unknown width "$raw" (use u8, u16le or u16be).',
            );
          }
          width = NumericWidth.fromId(raw);
        }
        if (value == ProfileValue.checksum && width != NumericWidth.u8) {
          return const TemplateParseResult.fail(
            'A checksum is a single byte; remove the width suffix.',
          );
        }
        tokens.add(CommandPlaceholder(value, width));
      } else {
        if (!RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(part)) {
          return TemplateParseResult.fail(
            '"$part" is not a valid byte or placeholder. Use two hex digits '
            '(for example "0A") or "{brightness}".',
          );
        }
        tokens.add(LiteralByte(int.parse(part, radix: 16)));
      }
    }

    if (tokens.length > 20) {
      return const TemplateParseResult.fail(
        'A command may be at most 20 bytes long.',
      );
    }

    final checksums = tokens
        .whereType<CommandPlaceholder>()
        .where((t) => t.value == ProfileValue.checksum)
        .toList();
    if (checksums.length > 1) {
      return const TemplateParseResult.fail(
        'A command may contain at most one checksum.',
      );
    }
    if (checksums.isNotEmpty && tokens.last != checksums.single) {
      return const TemplateParseResult.fail(
        'A checksum must be the last byte of the command.',
      );
    }

    return TemplateParseResult.ok(CommandTemplate(tokens));
  }

  @override
  bool operator ==(Object other) =>
      other is CommandTemplate && listEquals(other.tokens, tokens);

  @override
  int get hashCode => Object.hashAll(tokens);

  @override
  String toString() => toText();
}
