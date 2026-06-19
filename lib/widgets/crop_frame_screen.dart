import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../config/app_theme.dart';

/// Экран выбора области на изображении.
/// Показывает фото, поверх него — перемещаемую/масштабируемую рамку.
/// Возвращает обрезанные байты (PNG) при нажатии "Готово".
class CropFrameScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String title;

  const CropFrameScreen({
    super.key,
    required this.imageBytes,
    this.title = 'Выберите область',
  });

  /// Открывает экран и возвращает обрезанные байты или null если отменено.
  static Future<Uint8List?> show(BuildContext context, Uint8List bytes,
      {String title = 'Выберите область'}) {
    return Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => CropFrameScreen(imageBytes: bytes, title: title),
      ),
    );
  }

  @override
  State<CropFrameScreen> createState() => _CropFrameScreenState();
}

class _CropFrameScreenState extends State<CropFrameScreen> {
  // Размер изображения в пикселях
  ui.Size _imgSize = ui.Size.zero;

  // Рамка в координатах виджета (0..1 относительно области отображения)
  Rect _frame = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);

  // Размер виджета-просмотра
  Size _viewSize = Size.zero;

  // Для drag: что тащим
  _DragTarget? _dragTarget;

  static const double _handleSize = 24.0;
  static const double _minFrameSide = 0.05;

  bool _loading = true;

  // Декодированное изображение, переиспользуется при обрезке —
  // чтобы не декодировать одни и те же байты дважды (это и так медленно
  // для больших фото в чистом Dart).
  img.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    // Use img.decodeImage so EXIF rotation is applied and _imgSize matches
    // the visual dimensions shown by Image.memory
    final decoded = await compute((bytes) => img.decodeImage(bytes), widget.imageBytes);
    if (decoded != null && mounted) {
      setState(() {
        _decoded = decoded;
        _imgSize = ui.Size(decoded.width.toDouble(), decoded.height.toDouble());
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

  _DragTarget _hitTest(Offset pos) {
    final r = _frameRect;
    final h = _handleSize;

    // Углы
    if ((pos - r.topLeft).distance < h) return _DragTarget.topLeft;
    if ((pos - r.topRight).distance < h) return _DragTarget.topRight;
    if ((pos - r.bottomLeft).distance < h) return _DragTarget.bottomLeft;
    if ((pos - r.bottomRight).distance < h) return _DragTarget.bottomRight;

    // Стороны
    final midTop = Offset(r.center.dx, r.top);
    final midBot = Offset(r.center.dx, r.bottom);
    final midLeft = Offset(r.left, r.center.dy);
    final midRight = Offset(r.right, r.center.dy);
    if ((pos - midTop).distance < h) return _DragTarget.top;
    if ((pos - midBot).distance < h) return _DragTarget.bottom;
    if ((pos - midLeft).distance < h) return _DragTarget.left;
    if ((pos - midRight).distance < h) return _DragTarget.right;

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
      double l = _frame.left, t = _frame.top,
             r = _frame.right, b = _frame.bottom;

      switch (_dragTarget!) {
        case _DragTarget.move:
          final nl = (l + dx).clamp(0.0, 1.0 - _frame.width);
          final nt = (t + dy).clamp(0.0, 1.0 - _frame.height);
          _frame = Rect.fromLTWH(nl, nt, _frame.width, _frame.height);
          return;
        case _DragTarget.topLeft:
          l = (l + dx).clamp(0.0, r - _minFrameSide);
          t = (t + dy).clamp(0.0, b - _minFrameSide);
        case _DragTarget.topRight:
          r = (r + dx).clamp(l + _minFrameSide, 1.0);
          t = (t + dy).clamp(0.0, b - _minFrameSide);
        case _DragTarget.bottomLeft:
          l = (l + dx).clamp(0.0, r - _minFrameSide);
          b = (b + dy).clamp(t + _minFrameSide, 1.0);
        case _DragTarget.bottomRight:
          r = (r + dx).clamp(l + _minFrameSide, 1.0);
          b = (b + dy).clamp(t + _minFrameSide, 1.0);
        case _DragTarget.top:
          t = (t + dy).clamp(0.0, b - _minFrameSide);
        case _DragTarget.bottom:
          b = (b + dy).clamp(t + _minFrameSide, 1.0);
        case _DragTarget.left:
          l = (l + dx).clamp(0.0, r - _minFrameSide);
        case _DragTarget.right:
          r = (r + dx).clamp(l + _minFrameSide, 1.0);
        case _DragTarget.none:
          return;
      }
      _frame = Rect.fromLTRB(l, t, r, b);
    });
  }

  Future<void> _onConfirm() async {
    setState(() => _loading = true);
    final bytes = await compute(_performCrop, _CropTask(
      decoded: _decoded!,
      imgWidth: _imgSize.width,
      imgHeight: _imgSize.height,
      viewWidth: _viewSize.width,
      viewHeight: _viewSize.height,
      frameLeft: _frame.left,
      frameTop: _frame.top,
      frameWidth: _frame.width,
      frameHeight: _frame.height,
    ));
    if (mounted) Navigator.pop(context, bytes);
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
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (_, constraints) {
              _viewSize = constraints.biggest;
              return GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                child: Stack(children: [
                  // Изображение
                  Positioned.fill(
                    child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
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

enum _DragTarget { none, move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }

class _CropTask {
  final img.Image decoded;
  final double imgWidth, imgHeight;
  final double viewWidth, viewHeight;
  final double frameLeft, frameTop, frameWidth, frameHeight;

  const _CropTask({
    required this.decoded,
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

Uint8List _performCrop(_CropTask task) {
  final decoded = task.decoded;

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
  final cx = ((clipped.left - imgX) * scaleX).round().clamp(0, decoded.width);
  final cy = ((clipped.top - imgY) * scaleY).round().clamp(0, decoded.height);
  final cw = (clipped.width * scaleX).round().clamp(1, decoded.width - cx);
  final ch = (clipped.height * scaleY).round().clamp(1, decoded.height - cy);

  final cropped = img.copyCrop(decoded, x: cx, y: cy, width: cw, height: ch);
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
    _drawHandle(canvas, frame.topLeft);
    _drawHandle(canvas, frame.topRight);
    _drawHandle(canvas, frame.bottomLeft);
    _drawHandle(canvas, frame.bottomRight);
    // Средние маркеры
    _drawHandle(canvas, Offset(frame.center.dx, frame.top));
    _drawHandle(canvas, Offset(frame.center.dx, frame.bottom));
    _drawHandle(canvas, Offset(frame.left,  frame.center.dy));
    _drawHandle(canvas, Offset(frame.right, frame.center.dy));
  }

  void _drawHandle(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 8,
        Paint()..color = AppTheme.blue..style = PaintingStyle.fill);
    canvas.drawCircle(center, 8,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.frame != frame;
}
