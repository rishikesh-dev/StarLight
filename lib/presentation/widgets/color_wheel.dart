// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A circular HSV color wheel used for choosing a light color.
///
/// Interaction contract:
/// * Dragging anywhere inside the wheel updates a local preview colour
///   immediately (no device traffic).
/// * On release, or on tap, the final colour is committed via [onChanged].
/// * Hue is encoded 0..360 and saturation 0..1, matching the `color` command
///   parameters used by [CommandRouter].
class ColorWheel extends StatefulWidget {
  const ColorWheel({
    super.key,
    required this.onChanged,
    this.initialHue = 0,
    this.initialSaturation = 1,
    this.size = 232,
  });

  /// Called once per completed gesture with hue (0..360) and saturation (0..1).
  final ValueChanged<({double hue, double saturation})> onChanged;

  final double initialHue;
  final double initialSaturation;
  final double size;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late double _hue = widget.initialHue;
  late double _saturation = widget.initialSaturation;
  Offset? _dragPosition;

  @override
  void didUpdateWidget(covariant ColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialHue != widget.initialHue) {
      _hue = widget.initialHue;
    }
    if (oldWidget.initialSaturation != widget.initialSaturation) {
      _saturation = widget.initialSaturation;
    }
  }

  double get _radius => widget.size / 2;

  void _handleTapUp(TapUpDetails details) {
    _commit(details.localPosition);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() => _dragPosition = details.localPosition);
    _apply(details.localPosition);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _dragPosition = null);
  }

  /// Converts a local position into hue/saturation and updates local state.
  ({double hue, double saturation}) _apply(Offset local) {
    final center = Offset(_radius, _radius);
    final delta = local - center;
    final distance = delta.distance;
    final normalized = (distance / _radius).clamp(0.0, 1.0);
    final hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
    setState(() {
      _hue = hue;
      _saturation = normalized;
      _dragPosition = local;
    });
    return (hue: hue, saturation: normalized);
  }

  void _commit(Offset local) {
    final result = _apply(local);
    widget.onChanged(result);
  }

  Color get _displayColor =>
      HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor();

  Offset get _markerPosition {
    final position = _dragPosition;
    if (position != null) {
      final delta = position - Offset(_radius, _radius);
      final clampedDistance = delta.distance.clamp(0.0, _radius);
      if (clampedDistance == 0) {
        return Offset(_radius, _radius);
      }
      return Offset(_radius, _radius) +
          Offset.fromDirection(delta.direction, clampedDistance);
    }
    final angle = _hue * math.pi / 180;
    return Offset(
      _radius + math.cos(angle) * _radius * _saturation,
      _radius + math.sin(angle) * _radius * _saturation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final brightness = Theme.of(context).brightness;
    return Semantics(
      label: 'Color wheel',
      slider: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTapUp,
        onPanUpdate: _handleDragUpdate,
        onPanEnd: _handleDragEnd,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _WheelPainter(brightness),
              ),
              // Selection marker.
              Positioned(
                left: _markerPosition.dx - 11,
                top: _markerPosition.dy - 11,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _displayColor,
                    border: Border.all(color: tokens.onSurface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.background,
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.brightness);

  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const steps = 720;
    final sweep = 2 * math.pi / steps;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < steps; i++) {
      final startAngle = i * sweep - math.pi / 2;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = HSVColor.fromAHSV(1, (i * 360 / steps) % 360, 1, 1).toColor();
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(rect, startAngle, sweep, false)
        ..close();
      canvas.drawPath(path, paint);
    }

    // Desaturate towards the centre with a radial gradient so the middle
    // blends into the surrounding surface instead of a hard white core.
    final centerColor = brightness == Brightness.dark
        ? const Color(0xFF16141C)
        : Colors.white;
    final overlay = Paint()
      ..shader = RadialGradient(
        colors: [
          centerColor.withValues(alpha: 0.92),
          centerColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, overlay);

    // Soft inner edge so the wheel reads as a deliberate shape.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (brightness == Brightness.dark ? Colors.white : Colors.black)
          .withValues(alpha: 0.12);
    canvas.drawCircle(center, radius - 0.5, ring);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}
