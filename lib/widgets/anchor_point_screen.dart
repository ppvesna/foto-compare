import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// Full-screen widget for manual anchor point placement.
/// Returns List<Offset> in image pixel coordinates (not normalized).
///
/// [predictedPoints] — normalized (0..1) positions from saved LayoutProfile.
/// When provided, shows predicted markers; user can tap-to-confirm or drag-to-adjust.
class AnchorPointScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;
  final List<Offset>? initialPoints;   // image-pixel coords
  final List<Offset>? predictedPoints; // normalized 0..1 (for AUTO MODE)
  final int minPoints;
  final int maxPoints;

  const AnchorPointScreen({
    super.key,
    required this.imageBytes,
    required this.title,
    this.initialPoints,
    this.predictedPoints,
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
  Offset? _magnifierWidgetPos;

  // Зум/панорамирование вида (для точной постановки точки)
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  double _scaleStartZoom = 1.0;
  Offset _scaleStartPan = Offset.zero;
  Offset? _scaleFocalPoint;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 6.0;

  bool get _autoMode => widget.predictedPoints != null && _points.isEmpty;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    setState(() {
      _uiImage = image;
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      if (widget.initialPoints != null) {
        _points.addAll(widget.initialPoints!);
      } else if (widget.predictedPoints != null) {
        // Pre-populate with predicted positions (denormalized to pixel coords)
        for (final n in widget.predictedPoints!) {
          _points.add(Offset(n.dx * image.width, n.dy * image.height));
        }
      }
    });
  }

  // ── Базовый масштаб "вписать изображение в экран" ────
  double _fitScale(Size widgetSize) {
    if (_imageSize == Size.zero) return 1.0;
    final sx = widgetSize.width / _imageSize.width;
    final sy = widgetSize.height / _imageSize.height;
    return sx < sy ? sx : sy;
  }

  Offset _fitOffset(Size widgetSize) {
    final s = _fitScale(widgetSize);
    return Offset(
      (widgetSize.width - _imageSize.width * s) / 2,
      (widgetSize.height - _imageSize.height * s) / 2,
    );
  }

  // ── Итоговый масштаб/смещение с учётом зума и панорамирования ──
  double _viewScale(Size widgetSize) => _fitScale(widgetSize) * _zoom;

  Offset _viewOffset(Size widgetSize) {
    final fitOff = _fitOffset(widgetSize);
    final center = Offset(widgetSize.width / 2, widgetSize.height / 2);
    return (fitOff - center) * _zoom + center + _pan;
  }

  Offset _toImageCoords(Offset widgetPos, Size widgetSize) {
    final s = _viewScale(widgetSize);
    final o = _viewOffset(widgetSize);
    return Offset((widgetPos.dx - o.dx) / s, (widgetPos.dy - o.dy) / s);
  }

  Offset _toWidgetCoords(Offset imagePos, Size widgetSize) {
    final s = _viewScale(widgetSize);
    final o = _viewOffset(widgetSize);
    return Offset(imagePos.dx * s + o.dx, imagePos.dy * s + o.dy);
  }

  Offset _clampPan(Offset pan, double zoom, Size widgetSize) {
    final maxX = widgetSize.width * (zoom - 1) / 2 + 60;
    final maxY = widgetSize.height * (zoom - 1) / 2 + 60;
    return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
  }

  // ── Зум вокруг точки фокуса (кнопки, колесо мыши, пинч) ──
  void _zoomAt(Offset focal, double factor, Size widgetSize) {
    final newZoom = (_zoom * factor).clamp(_minZoom, _maxZoom);
    if (newZoom == _zoom) return;
    final center = Offset(widgetSize.width / 2, widgetSize.height / 2);
    setState(() {
      _pan = _clampPan(
        _pan + (focal - center - _pan) * (1 - newZoom / _zoom),
        newZoom, widgetSize,
      );
      _zoom = newZoom;
    });
  }

  void _resetView() => setState(() { _zoom = 1.0; _pan = Offset.zero; });

  void _onTapDown(TapDownDetails d, Size widgetSize) {
    if (_imageSize == Size.zero) return;
    final imgPt = _toImageCoords(d.localPosition, widgetSize);
    if (imgPt.dx < 0 || imgPt.dy < 0 ||
        imgPt.dx > _imageSize.width || imgPt.dy > _imageSize.height) return;

    // Tap near existing point → remove
    for (int i = 0; i < _points.length; i++) {
      final wp = _toWidgetCoords(_points[i], widgetSize);
      if ((wp - d.localPosition).distance < 28) {
        setState(() => _points.removeAt(i));
        return;
      }
    }

    if (_points.length >= widget.maxPoints) return;
    setState(() => _points.add(imgPt));
  }

  // ── Жест: один палец/мышь — перетащить точку ИЛИ панорамировать вид;
  //    два пальца — зум (pinch) ──
  void _onScaleStart(ScaleStartDetails d, Size widgetSize) {
    _scaleStartZoom = _zoom;
    _scaleStartPan = _pan;
    _scaleFocalPoint = d.localFocalPoint;
    _draggingIdx = null;
    for (int i = 0; i < _points.length; i++) {
      final wp = _toWidgetCoords(_points[i], widgetSize);
      if ((wp - d.localFocalPoint).distance < 32) {
        _draggingIdx = i;
        setState(() => _magnifierWidgetPos = d.localFocalPoint);
        return;
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size widgetSize) {
    if (_draggingIdx != null) {
      final imgPt = _toImageCoords(d.localFocalPoint, widgetSize);
      setState(() {
        _points[_draggingIdx!] = Offset(
          imgPt.dx.clamp(0, _imageSize.width),
          imgPt.dy.clamp(0, _imageSize.height),
        );
        _magnifierWidgetPos = d.localFocalPoint;
      });
      return;
    }

    final newZoom = (_scaleStartZoom * d.scale).clamp(_minZoom, _maxZoom);
    final center = Offset(widgetSize.width / 2, widgetSize.height / 2);
    final panFromZoom = (d.localFocalPoint - center - _scaleStartPan) *
        (1 - newZoom / _scaleStartZoom);
    final panFromDrag = d.localFocalPoint - _scaleFocalPoint!;
    setState(() {
      _pan = _clampPan(_scaleStartPan + panFromDrag + panFromZoom, newZoom, widgetSize);
      _zoom = newZoom;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    _draggingIdx = null;
    setState(() => _magnifierWidgetPos = null);
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _points.length >= widget.minPoints;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 13)),
        actions: [
          if (_points.isNotEmpty)
            TextButton(
              onPressed: () { setState(() => _points.clear()); },
              child: const Text('Сброс', style: TextStyle(color: Colors.orange)),
            ),
          TextButton(
            onPressed: canConfirm
                ? () => Navigator.of(context).pop(_points.toList())
                : null,
            child: Text(
              'Готово (${_points.length}/${widget.minPoints})',
              style: TextStyle(
                color: canConfirm ? Colors.green : Colors.grey,
                fontWeight: FontWeight.bold,
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
                Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      final factor = event.scrollDelta.dy > 0 ? 0.9 : 1.1;
                      _zoomAt(event.localPosition, factor, widgetSize);
                    }
                  },
                  child: GestureDetector(
                    onTapDown: (d) => _onTapDown(d, widgetSize),
                    onScaleStart: (d) => _onScaleStart(d, widgetSize),
                    onScaleUpdate: (d) => _onScaleUpdate(d, widgetSize),
                    onScaleEnd: _onScaleEnd,
                    child: CustomPaint(
                      size: widgetSize,
                      painter: _AnchorPainter(
                        image: _uiImage!,
                        imageSize: _imageSize,
                        points: _points,
                        scale: _viewScale(widgetSize),
                        offset: _viewOffset(widgetSize),
                        draggingIdx: _draggingIdx,
                        isPredicted: widget.predictedPoints != null,
                      ),
                    ),
                  ),
                ),

                // Magnifier
                if (_magnifierWidgetPos != null && _draggingIdx != null)
                  _buildMagnifier(widgetSize),

                // Zoom controls
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(children: [
                    _zoomBtn('＋', () => _zoomAt(
                        Offset(widgetSize.width / 2, widgetSize.height / 2),
                        1.25, widgetSize)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${(_zoom * 100).round()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                    const SizedBox(height: 4),
                    _zoomBtn('－', () => _zoomAt(
                        Offset(widgetSize.width / 2, widgetSize.height / 2),
                        0.8, widgetSize)),
                    const SizedBox(height: 4),
                    _zoomBtn('⟲', _resetView),
                  ]),
                ),

                // AUTO MODE hint
                if (widget.predictedPoints != null && _points.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Авто-режим: точки предсказаны — перетащите для уточнения',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),

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
                        (widget.predictedPoints != null
                            ? 'Перетащите точки для уточнения · Нажмите точку чтобы удалить\n'
                            : 'Нажмите чтобы добавить · Перетащите чтобы уточнить · Нажмите точку чтобы удалить\n') +
                        'Колесо мыши / щипок — зум · Потяните пустое место — сдвиг вида',
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

  Widget _zoomBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMagnifier(Size widgetSize) {
    const magSize = 100.0;
    const magScale = 3.0;

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
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
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
  final double scale;
  final Offset offset;
  final int? draggingIdx;
  final bool isPredicted;

  _AnchorPainter({
    required this.image,
    required this.imageSize,
    required this.points,
    required this.scale,
    required this.offset,
    required this.draggingIdx,
    this.isPredicted = false,
  });

  Offset _toWidget(Offset imgPt) => Offset(imgPt.dx * scale + offset.dx, imgPt.dy * scale + offset.dy);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(
      offset.dx, offset.dy,
      imageSize.width * scale, imageSize.height * scale,
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    paintImage(canvas: canvas, rect: dst, image: image, fit: BoxFit.fill);
    canvas.restore();

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

    for (int i = 0; i < points.length; i++) {
      final wp = _toWidget(points[i]);
      final isDragging = draggingIdx == i;
      final color = isPredicted ? Colors.cyan : (i == 0 ? Colors.red : Colors.yellow);

      // Outer search ring for predicted points
      if (isPredicted) {
        canvas.drawCircle(wp, 22,
            Paint()
              ..color = Colors.cyan.withOpacity(0.25)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(wp, 22,
            Paint()
              ..color = Colors.cyan.withOpacity(0.6)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
      }

      canvas.drawCircle(wp, isDragging ? 14 : 10,
          Paint()..color = Colors.black.withOpacity(0.5));
      canvas.drawCircle(wp, isDragging ? 12 : 8,
          Paint()..color = color);
      canvas.drawCircle(wp, isDragging ? 12 : 8,
          Paint()
            ..color = Colors.white
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke);

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
  final Offset center;
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
    final src = Rect.fromCenter(center: center, width: half * 2, height: half * 2)
        .intersect(Rect.fromLTWH(0, 0, imageSize.width, imageSize.height));
    final dst = Rect.fromLTWH(0, 0, viewSize, viewSize);
    canvas.drawImageRect(image, src, dst, Paint());

    final p = Paint()..color = Colors.red..strokeWidth = 1;
    canvas.drawLine(Offset(viewSize / 2, 0), Offset(viewSize / 2, viewSize), p);
    canvas.drawLine(Offset(0, viewSize / 2), Offset(viewSize, viewSize / 2), p);
  }

  @override
  bool shouldRepaint(_MagnifierPainter old) => true;
}
