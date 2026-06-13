import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Результат точной подстройки наложения.
class OverlayAlignResult {
  final Matrix4 transform;
  final double opacity;
  const OverlayAlignResult(this.transform, this.opacity);
}

/// Полноэкранная страница точного совмещения двух изображений по масштабу/сдвигу.
/// [base] — неподвижное изображение (эталон), [overlay] — двигаемое (образец/фото).
/// Кнопки дают точный зум и сдвиг с фиксированным шагом — удобнее мыши в браузере.
class OverlayAlignScreen extends StatefulWidget {
  final Uint8List base;
  final Uint8List overlay;
  final Matrix4 initialTransform;
  final double initialOpacity;
  final String title;

  const OverlayAlignScreen({
    super.key,
    required this.base,
    required this.overlay,
    required this.initialTransform,
    required this.initialOpacity,
    this.title = 'Точное совмещение',
  });

  static Future<OverlayAlignResult?> show(
    BuildContext context, {
    required Uint8List base,
    required Uint8List overlay,
    required Matrix4 initialTransform,
    required double initialOpacity,
    String title = 'Точное совмещение',
  }) {
    return Navigator.of(context).push<OverlayAlignResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OverlayAlignScreen(
          base: base,
          overlay: overlay,
          initialTransform: initialTransform,
          initialOpacity: initialOpacity,
          title: title,
        ),
      ),
    );
  }

  @override
  State<OverlayAlignScreen> createState() => _OverlayAlignScreenState();
}

class _OverlayAlignScreenState extends State<OverlayAlignScreen> {
  late final TransformationController _ctrl;
  late double _opacity;
  Size _viewportSize = Size.zero;

  static const double _zoomStep = 1.02;   // ±2% за нажатие
  static const double _panStep = 2.0;     // px за нажатие

  @override
  void initState() {
    super.initState();
    _ctrl = TransformationController(widget.initialTransform.clone());
    _opacity = widget.initialOpacity;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final c = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final m = Matrix4.identity()
      ..translate(c.dx, c.dy)
      ..scale(factor)
      ..translate(-c.dx, -c.dy);
    setState(() => _ctrl.value = m * _ctrl.value);
  }

  void _panBy(double dx, double dy) {
    final m = Matrix4.identity()..translate(dx, dy);
    setState(() => _ctrl.value = m * _ctrl.value);
  }

  void _reset() => setState(() => _ctrl.value = Matrix4.identity());

  void _done() {
    Navigator.of(context).pop(OverlayAlignResult(_ctrl.value.clone(), _opacity));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: _done,
            child: const Text('Готово',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: LayoutBuilder(builder: (_, c) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_viewportSize != Size(c.maxWidth, c.maxHeight)) {
                _viewportSize = Size(c.maxWidth, c.maxHeight);
              }
            });
            return ClipRect(
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(widget.base, fit: BoxFit.contain),
                Opacity(
                  opacity: _opacity,
                  child: InteractiveViewer(
                    transformationController: _ctrl,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.1,
                    maxScale: 6.0,
                    onInteractionUpdate: (_) => setState(() {}),
                    child: Image.memory(widget.overlay, fit: BoxFit.contain),
                  ),
                ),
                const Positioned(left: 8, top: 8, child: _Label('Эталон')),
                const Positioned(right: 8, top: 8, child: _Label('Образец ↕↔')),
              ]),
            );
          }),
        ),
        Container(
          color: AppTheme.silver,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 90,
                  child: Text('Прозрачность:', style: TextStyle(fontSize: 11))),
              Expanded(child: Slider(
                value: _opacity,
                onChanged: (v) => setState(() => _opacity = v),
                activeColor: AppTheme.blue,
              )),
              SizedBox(width: 36, child: Text('${(_opacity * 100).round()}%',
                  style: const TextStyle(fontSize: 10))),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _ctrlBtn('🔍－', () => _zoomBy(1 / _zoomStep), 'Уменьшить'),
              const SizedBox(width: 8),
              _ctrlBtn('🔍＋', () => _zoomBy(_zoomStep), 'Увеличить'),
              const SizedBox(width: 16),
              _ctrlBtn('↺', _reset, 'Сбросить'),
            ]),
            const SizedBox(height: 8),
            // Крестовина точного сдвига
            Column(children: [
              _ctrlBtn('↑', () => _panBy(0, _panStep), null),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ctrlBtn('←', () => _panBy(_panStep, 0), null),
                const SizedBox(width: 36),
                _ctrlBtn('→', () => _panBy(-_panStep, 0), null),
              ]),
              _ctrlBtn('↓', () => _panBy(0, -_panStep), null),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _ctrlBtn(String label, VoidCallback onTap, String? tooltip) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.silverDark),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10)),
    );
  }
}
