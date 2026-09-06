import 'dart:math' as math;

import 'package:flutter/material.dart';

class AccentColorPicker extends StatefulWidget {
  const AccentColorPicker({super.key, required this.initialColor});

  final Color initialColor;

  @override
  State<AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState extends State<AccentColorPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _setSaturationValue(Offset local, Size size) {
    final saturation = (local.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - local.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(saturation).withValue(value));
  }

  void _setHue(Offset local, Size size) {
    final hue = (local.dx / size.width * 360).clamp(0.0, 360.0);
    setState(() => _hsv = _hsv.withHue(hue));
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, math.min(constraints.maxWidth, 280));
            return GestureDetector(
              onPanDown: (details) => _setSaturationValue(details.localPosition, size),
              onPanUpdate: (details) => _setSaturationValue(details.localPosition, size),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(
                  painter: _SaturationValuePainter(hue: _hsv.hue),
                  child: CustomPaint(
                    painter: _PickerHandlePainter(
                      x: _hsv.saturation * size.width,
                      y: (1 - _hsv.value) * size.height,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 28);
            return GestureDetector(
              onPanDown: (details) => _setHue(details.localPosition, size),
              onPanUpdate: (details) => _setHue(details.localPosition, size),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(
                  painter: _HuePainter(),
                  child: CustomPaint(painter: _HueHandlePainter(x: _hsv.hue / 360 * size.width)),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline))),
            const SizedBox(width: 12),
            Expanded(child: Text('#${color.value.toRadixString(16).substring(2).toUpperCase()}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600))),
            FilledButton(onPressed: () => Navigator.pop(context, color), child: const Text('Use color')),
          ],
        ),
      ],
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  _SaturationValuePainter({required this.hue});
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final base = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(Offset.zero & size, Paint()..shader = LinearGradient(colors: [Colors.white, base]).createShader(Offset.zero & size));
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) => oldDelegate.hue != hue;
}

class _PickerHandlePainter extends CustomPainter {
  _PickerHandlePainter({required this.x, required this.y});
  final double x;
  final double y;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(x, y), 9, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
    canvas.drawCircle(Offset(x, y), 11, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _PickerHandlePainter oldDelegate) => oldDelegate.x != x || oldDelegate.y != y;
}

class _HuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const colors = [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red];
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)), Paint()..shader = const LinearGradient(colors: colors).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant _HuePainter oldDelegate) => false;
}

class _HueHandlePainter extends CustomPainter {
  _HueHandlePainter({required this.x});
  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(x, size.height / 2), 10, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x, size.height / 2), 8, Paint()..color = Colors.transparent..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _HueHandlePainter oldDelegate) => oldDelegate.x != x;
}
