import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Full-screen widget for manual anchor point placement.
/// Returns List<Offset> in image pixel coordinates (not normalized).
/// Usage: await Navigator.push(..., AnchorPointScreen(imageBytes, existingAnchors))
class AnchorPointScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;
  final List<Offset>? initialPoints; // image-pixel coords, optional
  final int minPoints;
  final int maxPoints;

  const AnchorPointScreen({
    super.key,
    required this.imageBytes,
    required this.title,
    this.initialPoints,
    this.minPoints = 4,
    this.maxPoints = 8,
  });

  @override
  State<AnchorPointScreen> createState() => _AnchorPointScreenState();
}

class _AnchorPointScreenState extends State<AnchorPointScreen> {
  ui.Image? _uiImage;
  Size _imageSize = Size.zero;
  final List<Offset> _points = []; // image-pixel coords
  int? _draggingIdx;

  // Magnifier
  Offset? _magnifierPos; // widget coords

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    setState(() {
      _uiImage = img;
      _imageSize = Size(img.width.toDouble(), img.height.toDouble());
      if (widget.initialPoints != null) {
        _points.addAll(widget.initialPoints!);
      }
    });
  }

  // Convert widget tap position to image pixel coords
  Offset _toImageCoords(Offset widgetPos, Size widgetSize) {
    final scale = _fitScale(widgetSize);
    final imgRendered = Size(_imageSize.width * scale, _imageSize.height * scale);
    final offset = Offset(
      (widgetSize.width - imgRendered.width) / 2,
      (widgetSize.height - imgRendered.height) / 2,
    );
    return Offset(
      (widgetPos.dx - offset.dx) / scale,
      (widgetPos.dy - offset.dy) / scale,
    );
  }

  Offset _toWidgetCoords(Offset imagePos, Size widgetSize) {
    final scale = _fitScale(widgetSize);
    final imgRendered = Size(_imageSize.width * scale, _imageSize.height * scale);
    final offset = Offset(
      (widgetSize.width - imgRendered.width) / 2,
      (widgetSize.height - imgRendered.height) / 2,
    );
    return Offset(
      imagePos.dx * scale + offset.dx,
      imagePos.dy * scale + offset.dy,
    );
  }

  double _fitScale(Size widgetSize) {
    if (_imageSize == Size.zero) return 1.0;
    final sx = widgetSize.width / _imageSize.width;
    final sy = widgetSize.height / _imageSize.height;
    return sx < sy ? sx : sy;
  }

  void _onTapDown(TapDownDetails d, Size widgetSize) {
    if (_imageSize == Size.zero) return;
    final imgPt = _toImageCoords(d.localPosition, widgetSize);
    if (imgPt.dx < 0 || imgPt.dy < 0 ||
        imgPt.dx > _imageSize.width || imgPt.dy > _imageSize.height) return;

    // Check if near existing point (within 24px widget coords)
    final wPt = d.localPosition;
    for (int i = 0; i < _points.length; i++) {
      final wp = _toWidgetCoords(_points[i], widgetSize);
      if ((wp - wPt).distance < 24) {
        // tap on existing: remove it
        setState(() => _points.removeAt(i));
        return;
      }
    }

    if (_points.length >= widget.maxPoints) return;
    setState(() => _points.add(imgPt));
  }

  void _onPanStart(DragStartDetails d, Size widgetSize) {
    final wPt = d.localPosition;
    for (int i = 0; i < _points.length; i++) {
      final wp = _toWidgetCoords(_points[i], widgetSize);
      if ((wp - wPt).distance < 28) {
        _draggingIdx = i;
        setState(() => _magnifierPos = wPt);
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d, Size widgetSize) {
    if (_draggingIdx == null) return;
    final imgPt = _toImageCoords(d.localPosition, widgetSize);
    setState(() {
      _points[_draggingIdx!] = Offset(
        imgPt.dx.clamp(0, _imageSize.width),
        imgPt.dy.clamp(0, _imageSize.height),
      );
      _magnifierPos = d.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    _draggingIdx = null;
    setState(() => _magnifierPos = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
        actions: [
          if (_points.isNotEmpty)
            TextButton(
              onPressed: () { setState(() => _points.clear()); },
              child: const Text('Сброс', style: TextStyle(color: Colors.orange)),
            ),
          TextButton(
            onPressed: _points.length >= widget.minPoints
                ? () => Navigator.of(context).pop(_points.toList())
                : null,
            child: Text(
              'Готово (${_points.length}/${widget.minPoints})',
              style: TextStyle(
                color: _points.length >= widget.minPoints ? Colors.green : Colors.grey,
              ),
            ),
          ),
        ],
      ),
      body: _uiImage == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (ctx, constraints) {
              final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(children: [
                // Image + overlay
                GestureDetector(
                  onTapDown: (d) => _onTapDown(d, widgetSize),
                  onPanStart: (d) => _onPanStart(d, widgetSize),
                  onPanUpdate: (d) => _onPanUpdate(d, widgetSize),
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    size: widgetSize,
                    painter: _AnchorPainter(
                      image: _uiImage!,
                      imageSize: _imageSize,
                      points: _points,
                      widgetSize: widgetSize,
                      draggingIdx: _draggingIdx,
                    ),
                  ),
                ),

                // Magnifier
                if (_magnifierPos != null && _draggingIdx != null)
                  _buildMagnifier(widgetSize),

                // Instruction
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Нажмите чтобы добавить точку · Перетащите чтобы уточнить · Нажмите точку чтобы удалить',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ]);
            }),
    );
  }

  Widget _buildMagnifier(Size widgetSize) {
    const magSize = 100.0;
    const magScale = 3.0;

    // Position magnifier above the finger
    final idx = _draggingIdx!;
    final imgPt = _points[idx];
    final wPt = _toWidgetCoords(imgPt, widgetSize);

    double left = wPt.dx - magSize / 2;
    double top = wPt.dy - magSize - 60;
    if (top < 80) top = wPt.dy + 60;
    left = left.clamp(0, widgetSize.width - magSize);

    return Positioned(
      left: left,
      top: top,
      width: magSize,
      height: magSize,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
        child: ClipOval(
          child: CustomPaint(
            painter: _MagnifierPainter(
              image: _uiImage!,
              imageSize: _imageSize,
              center: imgPt,
              scale: magScale,
              viewSize: magSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchorPainter extends CustomPainter {
  final ui.Image image;
  final Size imageSize;
  final List<Offset> points;
  final Size widgetSize;
  final int? draggingIdx;

  _AnchorPainter({
    required this.image,
    required this.imageSize,
    required this.points,
    required this.widgetSize,
    required this.draggingIdx,
  });

  double get _scale {
    final sx = widgetSize.width / imageSize.width;
    final sy = widgetSize.height / imageSize.height;
    return sx < sy ? sx : sy;
  }

  Offset get _imgOffset {
    final s = _scale;
    return Offset(
      (widgetSize.width - imageSize.width * s) / 2,
      (widgetSize.height - imageSize.height * s) / 2,
    );
  }

  Offset _toWidget(Offset imgPt) {
    final s = _scale;
    final o = _imgOffset;
    return Offset(imgPt.dx * s + o.dx, imgPt.dy * s + o.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(
      _imgOffset.dx, _imgOffset.dy,
      imageSize.width * _scale, imageSize.height * _scale,
    );
    paintImage(canvas: canvas, rect: dst, image: image, fit: BoxFit.fill);

    // Lines between points
    if (points.length >= 2) {
      final linePaint = Paint()
        ..color = Colors.yellow.withOpacity(0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < points.length - 1; i++) {
        canvas.drawLine(_toWidget(points[i]), _toWidget(points[i + 1]), linePaint);
      }
      if (points.length >= 3) {
        canvas.drawLine(_toWidget(points.last), _toWidget(points.first), linePaint);
      }
    }

    // Points
    for (int i = 0; i < points.length; i++) {
      final wp = _toWidget(points[i]);
      final isDragging = draggingIdx == i;

      canvas.drawCircle(wp, isDragging ? 14 : 10,
          Paint()..color = Colors.black.withOpacity(0.5));
      canvas.drawCircle(wp, isDragging ? 12 : 8,
          Paint()..color = (i == 0 ? Colors.red : Colors.yellow));
      canvas.drawCircle(wp, isDragging ? 12 : 8,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);

      // Number label
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.black,
            fontSize: isDragging ? 11 : 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, wp - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_AnchorPainter old) => true;
}

class _MagnifierPainter extends CustomPainter {
  final ui.Image image;
  final Size imageSize;
  final Offset center; // image pixel coords
  final double scale;
  final double viewSize;

  _MagnifierPainter({
    required this.image,
    required this.imageSize,
    required this.center,
    required this.scale,
    required this.viewSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final half = viewSize / 2 / scale;
    final src = Rect.fromCenter(
      center: center,
      width: half * 2,
      height: half * 2,
    );
    final dst = Rect.fromLTWH(0, 0, viewSize, viewSize);
    canvas.drawImageRect(image, src.intersect(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height)), dst, Paint());

    // Crosshair
    final p = Paint()..color = Colors.red..strokeWidth = 1;
    canvas.drawLine(Offset(viewSize / 2, 0), Offset(viewSize / 2, viewSize), p);
    canvas.drawLine(Offset(0, viewSize / 2), Offset(viewSize, viewSize / 2), p);
  }

  @override
  bool shouldRepaint(_MagnifierPainter old) => true;
}
