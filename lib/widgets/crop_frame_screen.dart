import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../config/app_theme.dart';

class CropSelection {
  final int x;
  final int y;
  final int width;
  final int height;

  const CropSelection({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Экран выбора области на изображении.
/// Показывает фото, поверх него — перемещаемую/масштабируемую рамку.
/// Возвращает только границу обработки; пиксели применяются после закрытия.
class CropFrameScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;

  const CropFrameScreen({
    super.key,
    required this.imageBytes,
    this.title = 'Выберите область',
  });

  static Future<CropSelection?> show(BuildContext context, Uint8List bytes,
      {String title = 'Выберите область'}) {
    return Navigator.push<CropSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => CropFrameScreen(imageBytes: bytes, title: title),
      ),
    );
  }

  static Future<Uint8List> apply(
    Uint8List bytes,
    CropSelection selection,
  ) {
    return compute(
      _performPixelCrop,
      _PixelCropTask(bytes: bytes, selection: selection),
    );
  }

  @override
  State<CropFrameScreen> createState() => _CropFrameScreenState();
}

class _CropFrameScreenState extends State<CropFrameScreen> {
  // Размер изображения в пикселях
  ui.Size _imgSize = ui.Size.zero;

  // Рамка в координатах виджета (0..1 относительно области отображения).
  // Инициализируется по реальным границам изображения внутри BoxFit.contain.
  Rect _frame = Rect.zero;
  bool _frameInitialized = false;

  // Размер виджета-просмотра
  Size _viewSize = Size.zero;

  // Для drag: что тащим
  _DragTarget? _dragTarget;

  static const double _handleSize = 24.0;
  static const double _handleEdgeInset = 14.0;
  static const double _minFrameSide = 0.05;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    ui.Size size;
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      size = ui.Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
    } catch (_) {
      final decoded = await compute(_decodeCropSize, widget.imageBytes);
      size = ui.Size(decoded.width.toDouble(), decoded.height.toDouble());
    }
    if (mounted) {
      setState(() {
        _imgSize = size;
        _loading = false;
      });
    }
  }

  // Рамка в пикселях виджета
  Rect get _frameRect => Rect.fromLTWH(
        _frame.left * _viewSize.width,
        _frame.top * _viewSize.height,
        _frame.width * _viewSize.width,
        _frame.height * _viewSize.height,
      );

  Rect _imageRect(Size viewSize) {
    if (_imgSize.width <= 0 || _imgSize.height <= 0) {
      return Offset.zero & viewSize;
    }
    final imgAspect = _imgSize.width / _imgSize.height;
    final viewAspect = viewSize.width / viewSize.height;
    double imgX, imgY, imgW, imgH;
    if (imgAspect > viewAspect) {
      imgW = viewSize.width;
      imgH = viewSize.width / imgAspect;
      imgX = 0;
      imgY = (viewSize.height - imgH) / 2;
    } else {
      imgH = viewSize.height;
      imgW = viewSize.height * imgAspect;
      imgY = 0;
      imgX = (viewSize.width - imgW) / 2;
    }
    return Rect.fromLTWH(imgX, imgY, imgW, imgH);
  }

  Rect _normalizedImageRect(Size viewSize) {
    final r = _imageRect(viewSize);
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return Rect.fromLTRB(
      r.left / viewSize.width,
      r.top / viewSize.height,
      r.right / viewSize.width,
      r.bottom / viewSize.height,
    );
  }

  void _ensureFrameInitialized(Size viewSize) {
    if (_frameInitialized || viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }
    _frame = _normalizedImageRect(viewSize);
    _frameInitialized = true;
  }

  _DragTarget _hitTest(Offset pos) {
    final r = _frameRect;
    const h = _handleSize;

    Offset handle(Offset p) => Offset(
          p.dx.clamp(_handleEdgeInset, _viewSize.width - _handleEdgeInset),
          p.dy.clamp(_handleEdgeInset, _viewSize.height - _handleEdgeInset),
        );

    // Углы
    if ((pos - handle(r.topLeft)).distance < h) return _DragTarget.topLeft;
    if ((pos - handle(r.topRight)).distance < h) return _DragTarget.topRight;
    if ((pos - handle(r.bottomLeft)).distance < h) {
      return _DragTarget.bottomLeft;
    }
    if ((pos - handle(r.bottomRight)).distance < h) {
      return _DragTarget.bottomRight;
    }

    // Стороны
    final midTop = Offset(r.center.dx, r.top);
    final midBot = Offset(r.center.dx, r.bottom);
    final midLeft = Offset(r.left, r.center.dy);
    final midRight = Offset(r.right, r.center.dy);
    if ((pos - handle(midTop)).distance < h) return _DragTarget.top;
    if ((pos - handle(midBot)).distance < h) return _DragTarget.bottom;
    if ((pos - handle(midLeft)).distance < h) return _DragTarget.left;
    if ((pos - handle(midRight)).distance < h) return _DragTarget.right;

    // Внутри — двигаем всю рамку
    if (r.contains(pos)) return _DragTarget.move;

    return _DragTarget.none;
  }

  void _onPanStart(DragStartDetails d) {
    _dragTarget = _hitTest(d.localPosition);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragTarget == null || _dragTarget == _DragTarget.none) return;
    final dx = d.delta.dx / _viewSize.width;
    final dy = d.delta.dy / _viewSize.height;

    setState(() {
      double l = _frame.left,
          t = _frame.top,
          r = _frame.right,
          b = _frame.bottom;
      final bounds = _normalizedImageRect(_viewSize);
      final minW = _minFrameSide.clamp(0.0, bounds.width);
      final minH = _minFrameSide.clamp(0.0, bounds.height);

      switch (_dragTarget!) {
        case _DragTarget.move:
          final nl = (l + dx).clamp(bounds.left, bounds.right - _frame.width);
          final nt = (t + dy).clamp(bounds.top, bounds.bottom - _frame.height);
          _frame = Rect.fromLTWH(nl, nt, _frame.width, _frame.height);
          return;
        case _DragTarget.topLeft:
          l = (l + dx).clamp(bounds.left, r - minW);
          t = (t + dy).clamp(bounds.top, b - minH);
        case _DragTarget.topRight:
          r = (r + dx).clamp(l + minW, bounds.right);
          t = (t + dy).clamp(bounds.top, b - minH);
        case _DragTarget.bottomLeft:
          l = (l + dx).clamp(bounds.left, r - minW);
          b = (b + dy).clamp(t + minH, bounds.bottom);
        case _DragTarget.bottomRight:
          r = (r + dx).clamp(l + minW, bounds.right);
          b = (b + dy).clamp(t + minH, bounds.bottom);
        case _DragTarget.top:
          t = (t + dy).clamp(bounds.top, b - minH);
        case _DragTarget.bottom:
          b = (b + dy).clamp(t + minH, bounds.bottom);
        case _DragTarget.left:
          l = (l + dx).clamp(bounds.left, r - minW);
        case _DragTarget.right:
          r = (r + dx).clamp(l + minW, bounds.right);
        case _DragTarget.none:
          return;
      }
      _frame = Rect.fromLTRB(l, t, r, b);
    });
  }

  Future<void> _onConfirm() async {
    final selection = _selectionFromTask(
      _CropTask(
        imgWidth: _imgSize.width,
        imgHeight: _imgSize.height,
        viewWidth: _viewSize.width,
        viewHeight: _viewSize.height,
        frameLeft: _frame.left,
        frameTop: _frame.top,
        frameWidth: _frame.width,
        frameHeight: _frame.height,
      ),
    );
    if (mounted) Navigator.pop(context, selection);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppTheme.blueDark,
        foregroundColor: Colors.white,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _loading ? null : _onConfirm,
            child: const Text('Готово',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (_, constraints) {
              _viewSize = constraints.biggest;
              _ensureFrameInitialized(_viewSize);
              return GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                child: Stack(children: [
                  // Изображение
                  Positioned.fill(
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.contain,
                      cacheWidth: 1600,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  // Рамка
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CropPainter(_frameRect),
                    ),
                  ),
                ]),
              );
            }),
    );
  }
}

enum _DragTarget {
  none,
  move,
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight
}

class _CropTask {
  final double imgWidth, imgHeight;
  final double viewWidth, viewHeight;
  final double frameLeft, frameTop, frameWidth, frameHeight;

  const _CropTask({
    required this.imgWidth,
    required this.imgHeight,
    required this.viewWidth,
    required this.viewHeight,
    required this.frameLeft,
    required this.frameTop,
    required this.frameWidth,
    required this.frameHeight,
  });
}

class _PixelCropTask {
  final Uint8List bytes;
  final CropSelection selection;

  const _PixelCropTask({required this.bytes, required this.selection});
}

({int width, int height}) _decodeCropSize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  return (width: decoded?.width ?? 0, height: decoded?.height ?? 0);
}

CropSelection _selectionFromTask(_CropTask task) {
  final imgAspect = task.imgWidth / task.imgHeight;
  final viewAspect = task.viewWidth / task.viewHeight;
  double imgX, imgY, imgW, imgH;
  if (imgAspect > viewAspect) {
    imgW = task.viewWidth;
    imgH = task.viewWidth / imgAspect;
    imgX = 0;
    imgY = (task.viewHeight - imgH) / 2;
  } else {
    imgH = task.viewHeight;
    imgW = task.viewHeight * imgAspect;
    imgY = 0;
    imgX = (task.viewWidth - imgW) / 2;
  }

  final fr = Rect.fromLTWH(
    task.frameLeft * task.viewWidth,
    task.frameTop * task.viewHeight,
    task.frameWidth * task.viewWidth,
    task.frameHeight * task.viewHeight,
  );
  final imgRect = Rect.fromLTWH(imgX, imgY, imgW, imgH);
  final clipped = fr.intersect(imgRect);

  final scaleX = task.imgWidth / imgW;
  final scaleY = task.imgHeight / imgH;
  final imageWidth = task.imgWidth.round();
  final imageHeight = task.imgHeight.round();
  final cx = ((clipped.left - imgX) * scaleX).round().clamp(0, imageWidth - 1);
  final cy = ((clipped.top - imgY) * scaleY).round().clamp(0, imageHeight - 1);
  final cw = (clipped.width * scaleX).round().clamp(1, imageWidth - cx);
  final ch = (clipped.height * scaleY).round().clamp(1, imageHeight - cy);
  return CropSelection(x: cx, y: cy, width: cw, height: ch);
}

Uint8List _performPixelCrop(_PixelCropTask task) {
  final decoded = img.decodeImage(task.bytes);
  if (decoded == null) return task.bytes;
  final crop = task.selection;

  final cropped = img.copyCrop(
    decoded,
    x: crop.x,
    y: crop.y,
    width: crop.width,
    height: crop.height,
  );
  // level: 1 — быстрое сжатие вместо дефолтного (6), на больших фото
  // экономит большую часть времени кодирования PNG в чистом Dart.
  return Uint8List.fromList(img.encodePng(cropped, level: 1));
}

class _CropPainter extends CustomPainter {
  final Rect frame;
  const _CropPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    // Затемнение за рамкой
    final dimPaint = Paint()..color = const Color(0x99000000);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(full)
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Рамка
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(frame, borderPaint);

    // Сетка (3×3)
    final gridPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.5;
    for (int i = 1; i < 3; i++) {
      final x = frame.left + frame.width * i / 3;
      final y = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), gridPaint);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), gridPaint);
    }

    // Угловые маркеры
    _drawHandle(canvas, _handleCenter(frame.topLeft, size));
    _drawHandle(canvas, _handleCenter(frame.topRight, size));
    _drawHandle(canvas, _handleCenter(frame.bottomLeft, size));
    _drawHandle(canvas, _handleCenter(frame.bottomRight, size));
    // Средние маркеры
    _drawHandle(
        canvas, _handleCenter(Offset(frame.center.dx, frame.top), size));
    _drawHandle(
        canvas, _handleCenter(Offset(frame.center.dx, frame.bottom), size));
    _drawHandle(
        canvas, _handleCenter(Offset(frame.left, frame.center.dy), size));
    _drawHandle(
        canvas, _handleCenter(Offset(frame.right, frame.center.dy), size));
  }

  Offset _handleCenter(Offset point, Size size) {
    const inset = _CropFrameScreenState._handleEdgeInset;
    return Offset(
      point.dx.clamp(inset, size.width - inset),
      point.dy.clamp(inset, size.height - inset),
    );
  }

  void _drawHandle(Canvas canvas, Offset center) {
    canvas.drawCircle(
        center,
        8,
        Paint()
          ..color = AppTheme.blue
          ..style = PaintingStyle.fill);
    canvas.drawCircle(
        center,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.frame != frame;
}
