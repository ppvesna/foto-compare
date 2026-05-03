import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';
import '../services/compare_service.dart';
import '../config/app_config.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Uint8List? _refImg;
  Uint8List? _cmpImg;
  final _picker = ImagePicker();
  double _sliderPos = 0.5;
  double _opacity   = 0.5;
  String _mode      = 's'; // s=slider, d=side, o=overlay
  bool   _comparing = false;
  CompareResult? _result;

  // Параметры обработки
  bool _autoScale  = true;
  bool _normBright = true;
  bool _autoRotate = false;

  // Выравнивание — независимые контроллеры для каждого фото
  final _refCtrl = TransformationController();
  final _cmpCtrl = TransformationController();
  final _refKey  = GlobalKey();
  final _cmpKey  = GlobalKey();
  Uint8List? _refAligned;
  Uint8List? _cmpAligned;

  // Отступ рамки (10% с каждой стороны = 80% центральная зона)
  static const double _framePad = 0.10;

  bool   _stacking   = false; // идёт усреднение серии

  // Режим просмотра: true = выравнивание, false = сравнение
  bool   _alignMode  = true;
  double _rotation   = 0;
  double _zoom       = 1.0;
  final  _previewCtrl = TransformationController();

  final _history = [
    {'file': 'photo_001.jpg', 'sim': 87.4, 'date': '16.04.2026'},
    {'file': 'photo_002.jpg', 'sim': 71.2, 'date': '15.04.2026'},
    {'file': 'photo_003.jpg', 'sim': 45.8, 'date': '14.04.2026'},
    {'file': 'photo_004.jpg', 'sim': 93.1, 'date': '13.04.2026'},
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _refCtrl.dispose();
    _cmpCtrl.dispose();
    _previewCtrl.dispose();
    super.dispose();
  }

  // ── Захват выровненных областей ───────────────────
  Future<Uint8List?> _captureView(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) return null;

      // Кропаем по рамке
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      final w = decoded.width;
      final h = decoded.height;
      final cropped = img.copyCrop(decoded,
        x: (w * _framePad).toInt(),
        y: (h * _framePad).toInt(),
        width: (w * (1 - 2 * _framePad)).toInt(),
        height: (h * (1 - 2 * _framePad)).toInt(),
      );
      return Uint8List.fromList(img.encodePng(cropped));
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureAligned({bool silent = false}) async {
    if (_refImg == null || _cmpImg == null) {
      if (!silent) xpDlg(context, 'Ошибка', 'Загрузите оба изображения');
      return;
    }
    final ref = await _captureView(_refKey);
    final cmp = await _captureView(_cmpKey);
    if (!mounted) return;
    setState(() {
      _refAligned = ref ?? _refImg;
      _cmpAligned = cmp ?? _cmpImg;
    });
    if (!silent) {
      xpDlg(context, 'Готово', 'Область захвачена.');
    }
  }

  // ── Сравнение ─────────────────────────────────────
  Future<void> _runCompare() async {
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    if (ref == null || cmp == null) {
      xpDlg(context, 'Ошибка', 'Загрузите оба изображения');
      return;
    }
    setState(() => _comparing = true);
    try {
      final result = await CompareService.compare(ref, cmp);
      setState(() => _result = result);
      _tabs.animateTo(2);
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка сравнения', e.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  // ── Зум ──────────────────────────────────────────
  void _zoomView(double factor) {
    if (_alignMode) {
      _refCtrl.value = _refCtrl.value.clone()..scale(factor, factor);
      _cmpCtrl.value = _cmpCtrl.value.clone()..scale(factor, factor);
    } else {
      setState(() => _zoom = (_zoom * factor).clamp(0.2, 8.0));
    }
  }

  // ── Выбор фото ───────────────────────────────────
  Future<void> _pickImage(bool isRef) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Container(
        color: AppTheme.silver,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Text('📂', style: TextStyle(fontSize: 20)),
              title: const Text('Открыть файл'),
              onTap: () => Navigator.pop(context, 'file')),
          ListTile(
              leading: const Text('🖼️', style: TextStyle(fontSize: 20)),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(
              leading: const Text('📷', style: TextStyle(fontSize: 20)),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(context, 'camera')),
          ListTile(
              leading: const Text('📸', style: TextStyle(fontSize: 20)),
              title: const Text('Серия снимков (улучшение качества)'),
              subtitle: const Text('2–8 фото → усреднение → 1 чёткий снимок',
                  style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.pop(context, 'stack')),
        ]),
      ),
    );
    if (result == null) return;

    if (result == 'stack') {
      await _pickMultipleAndStack(isRef);
      return;
    }

    final source =
        result == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final x = await _picker.pickImage(source: source, imageQuality: 92);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    setState(() {
      if (isRef) { _refImg = bytes; _refAligned = null; }
      else        { _cmpImg = bytes; _cmpAligned = null; }
    });
  }

  // ── Серийная съёмка + усреднение ─────────────────
  Future<void> _pickMultipleAndStack(bool isRef) async {
    final shots = <Uint8List>[];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.silver,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('📸  Серия снимков',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${shots.length} шт.',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ]),
            const SizedBox(height: 8),
            const Text(
                'Сделайте 2–8 снимков одного объекта.\nПри усреднении шум исчезает, детали становятся чётче.',
                style: TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 10),

            // Превью собранных снимков
            if (shots.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: shots.length,
                  itemBuilder: (_, i) => Stack(children: [
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.blue),
                        image: DecorationImage(
                          image: MemoryImage(shots[i]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2, right: 8,
                      child: GestureDetector(
                        onTap: () => setSheet(() => shots.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          color: Colors.black54,
                          child: const Text('✕',
                              style: TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 10),

            // Кнопки добавления
            Row(children: [
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  final x = await _picker.pickImage(
                      source: ImageSource.camera, imageQuality: 95);
                  if (x != null) {
                    final b = await x.readAsBytes();
                    setSheet(() => shots.add(b));
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003388),
                    foregroundColor: Colors.white),
                child: const Text('📷 Камера'),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  final x = await _picker.pickImage(
                      source: ImageSource.gallery, imageQuality: 95);
                  if (x != null) {
                    final b = await x.readAsBytes();
                    setSheet(() => shots.add(b));
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF555555),
                    foregroundColor: Colors.white),
                child: const Text('🖼️ Галерея'),
              )),
            ]),
            const SizedBox(height: 8),

            // Объединить
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: shots.length >= 2
                    ? () => Navigator.pop(ctx)
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF226622),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300),
                child: Text(shots.length >= 2
                    ? '✅ Объединить ${shots.length} снимка'
                    : 'Нужно минимум 2 снимка'),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );

    if (shots.length < 2) return;

    setState(() => _stacking = true);
    try {
      final result = await compute(_stackImages, shots);
      if (mounted) {
        setState(() {
          if (isRef) { _refImg = result; _refAligned = null; }
          else        { _cmpImg = result; _cmpAligned = null; }
        });
      }
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  // ── Build ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '🖼️', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
              label: 'Новое',
              icon: '🆕',
              shortcut: 'Ctrl+N',
              onTap: () => setState(() {
                    _refImg = null;
                    _cmpImg = null;
                    _refAligned = null;
                    _cmpAligned = null;
                    _tabs.animateTo(0);
                  })),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'Сохранить',
              icon: '💾',
              shortcut: 'Ctrl+S',
              onTap: () =>
                  xpDlg(context, 'Сохранено', 'Результат сохранён в историю')),
          XpMenuItem(
              label: 'Экспорт...',
              icon: '📤',
              shortcut: 'Ctrl+E',
              onTap: () =>
                  xpDlg(context, 'Экспорт', 'Форматы: PNG, PDF, CSV')),
        ]),
        XpMenu(label: 'Вид', items: [
          XpMenuItem(
              label: 'Загрузка эталона',
              icon: '🖼️',
              onTap: () => _tabs.animateTo(0)),
          XpMenuItem(
              label: 'Сравнение',
              icon: '🔍',
              onTap: () => _tabs.animateTo(1)),
          XpMenuItem(
              label: 'Результат',
              icon: '📊',
              onTap: () => _tabs.animateTo(2)),
          XpMenuItem(
              label: 'История',
              icon: '📋',
              onTap: () => _tabs.animateTo(3)),
        ]),
        XpMenu(label: 'Инструменты', items: [
          XpMenuItem(
              label: 'Увеличить',
              icon: '🔍',
              shortcut: 'Ctrl++',
              onTap: () => _zoomView(1.25)),
          XpMenuItem(
              label: 'Уменьшить',
              icon: '🔎',
              shortcut: 'Ctrl+-',
              onTap: () => _zoomView(0.8)),
          XpMenuItem(
              label: 'Повернуть',
              icon: '↺',
              shortcut: 'Ctrl+R',
              onTap: () =>
                  setState(() => _rotation = (_rotation + 90) % 360)),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'Захватить область',
              icon: '📐',
              shortcut: 'Ctrl+T',
              onTap: _captureAligned),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'AI Анализ (Pro)', icon: '🤖', disabled: true),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(
              label: 'Горячие клавиши',
              icon: '⌨️',
              onTap: () => xpDlg(context, 'Горячие клавиши',
                  'Ctrl+N — Новое\nCtrl+S — Сохранить\nCtrl+E — Экспорт\nCtrl+R — Повернуть\nCtrl+T — Захватить\nCtrl++/- — Зум')),
        ]),
      ]),

      // Табы
      Container(
        color: AppTheme.silver,
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
        child: Row(children: [
          _xpTab('🖼️ Эталон', 0),
          _xpTab('🔍 Сравн.', 1),
          _xpTab('📊 Результат', 2),
          _xpTab('📋 История', 3),
        ]),
      ),
      Container(height: 2, color: AppTheme.blue),

      Expanded(
        child: TabBarView(
          controller: _tabs,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _tabRef(),
            _tabCmp(),
            _tabResult(),
            _tabHistory(),
          ],
        ),
      ),
    ]);
  }

  Widget _xpTab(String label, int idx) {
    return Expanded(
      child: AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) {
          final active = _tabs.index == idx;
          return SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: () => _tabs.animateTo(idx),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    active ? Colors.white : const Color(0xFFB8B4A8),
                foregroundColor:
                    active ? Colors.black : Colors.black54,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(3),
                  ),
                ),
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
          );
        },
      ),
    );
  }

  // ── Таб: Эталон ───────────────────────────────────
  Widget _tabRef() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        XpGroup(
            label: 'Эталонное изображение',
            child: Column(children: [
              GestureDetector(
                onTap: () => _pickImage(true),
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: _refImg != null
                            ? AppTheme.blue
                            : AppTheme.border,
                        width: 2),
                    color: Colors.white,
                  ),
                  child: _stacking && isRef
                      ? const Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('Усреднение снимков...',
                                style: TextStyle(fontSize: 11)),
                          ]))
                      : _refImg != null
                      ? Image.memory(_refImg!, fit: BoxFit.cover)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🖼️',
                                style: TextStyle(fontSize: 40)),
                            SizedBox(height: 8),
                            Text('Нажмите для выбора',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey)),
                            Text('JPEG, PNG, TIFF, RAW',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey)),
                          ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: XpBtn(
                        label: '📂 Файл',
                        onPressed: () => _pickImage(true))),
                const SizedBox(width: 4),
                Expanded(
                    child: XpBtn(
                        label: '🖼️ Галерея',
                        onPressed: () => _pickImage(true))),
                const SizedBox(width: 4),
                Expanded(
                    child: XpBtn(
                        label: '📷 Камера',
                        onPressed: () => _pickImage(true))),
              ]),
            ])),
        XpGroup(
            label: 'Параметры',
            child: Column(children: [
              _check('Автомасштабирование', _autoScale,
                  (v) => setState(() => _autoScale = v)),
              _check('Нормализация яркости', _normBright,
                  (v) => setState(() => _normBright = v)),
              _check('Автоповорот по EXIF', _autoRotate,
                  (v) => setState(() => _autoRotate = v)),
            ])),
        const SizedBox(height: 12),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          XpBtn(
              label: 'Далее ›',
              primary: true,
              onPressed: () => _tabs.animateTo(1)),
        ]),
      ]),
    );
  }

  // ── Таб: Сравнение ────────────────────────────────
  Widget _tabCmp() {
    return Column(children: [
      // Переключатель режима
      Container(
        color: AppTheme.silver,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Row(children: [
          _toggleBtn(
              '📐 Выравнивание',
              _alignMode,
              () => setState(() => _alignMode = true)),
          const SizedBox(width: 4),
          _toggleBtn(
              '👁 Просмотр',
              !_alignMode,
              () async {
                // Захватываем рамку перед показом сравнения
                await _captureAligned(silent: true);
                if (mounted) setState(() => _alignMode = false);
              }),
          const SizedBox(width: 8),
          if (_refAligned != null)
            const Text('✅ захвачено',
                style: TextStyle(
                    fontSize: 9, color: AppTheme.simHigh)),
        ]),
      ),

      // Основная область
      Expanded(
          child: _alignMode ? _alignmentView() : _comparisonView()),

      // Панель управления
      Container(
        color: AppTheme.silver,
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(children: [
          if (_alignMode) ...[
            Row(children: [
              _toolBtn('⟳ Эталон',
                  () => _refCtrl.value = Matrix4.identity()),
              const SizedBox(width: 4),
              _toolBtn('⟳ Фото',
                  () => _cmpCtrl.value = Matrix4.identity()),
              const Spacer(),
              XpBtn(
                  label: '📐 Захватить область',
                  onPressed: _captureAligned),
            ]),
          ] else ...[
            Row(children: [
              _toolBtn('−', () => _zoomView(0.8)),
              const SizedBox(width: 4),
              _toolBtn('+', () => _zoomView(1.25)),
              const SizedBox(width: 4),
              _toolBtn('↺',
                  () => setState(() => _rotation = (_rotation + 90) % 360)),
              const SizedBox(width: 4),
              _toolBtn('⟳', () {
                setState(() { _rotation = 0; _zoom = 1.0; });
              }),
              const Spacer(),
              const Text('Режим:',
                  style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              _modeBtn('s', '🔄 Слайдер'),
              const SizedBox(width: 4),
              _modeBtn('d', '◀▶'),
              const SizedBox(width: 4),
              _modeBtn('o', '🔲'),
            ]),
            if (_mode == 'o') ...[
              const SizedBox(height: 4),
              Row(children: [
                const Text('Прозрачность:',
                    style: TextStyle(fontSize: 10)),
                Expanded(
                    child: Slider(
                  value: _opacity,
                  onChanged: (v) =>
                      setState(() => _opacity = v),
                  activeColor: AppTheme.blue,
                  inactiveColor: AppTheme.silverDark,
                )),
              ]),
            ],
            if (_mode == 's') ...[
              const SizedBox(height: 4),
              Row(children: [
                const Text('◀',
                    style: TextStyle(fontSize: 10)),
                Expanded(
                    child: Slider(
                  value: _sliderPos,
                  onChanged: (v) =>
                      setState(() => _sliderPos = v),
                  activeColor: AppTheme.blue,
                  inactiveColor: AppTheme.silverDark,
                )),
                const Text('▶',
                    style: TextStyle(fontSize: 10)),
              ]),
            ],
          ],
          const Divider(height: 10),
          Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                XpBtn(
                    label: '‹ Эталон',
                    onPressed: () => _tabs.animateTo(0)),
                Row(children: [
                  if (_result != null) ...[
                    SimBadge(value: _result!.similarity),
                    const SizedBox(width: 8),
                  ],
                  _comparing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : XpBtn(
                          label: 'Сравнить ›',
                          primary: true,
                          onPressed: _runCompare),
                ]),
              ]),
        ]),
      ),
    ]);
  }

  // ── Вид: Выравнивание (два независимых вьювера) ───
  Widget _alignmentView() {
    return Row(children: [
      Expanded(
          child: Column(children: [
        _viewerHeader('Эталон', AppTheme.simHigh,
            _refAligned != null ? '✅' : 'масштабируй'),
        Expanded(
            child: _photoViewer(
                _refImg, _refCtrl, _refKey,
                onEmpty: () => _pickImage(true))),
      ])),
      Container(width: 1, color: AppTheme.silverDark),
      Expanded(
          child: Column(children: [
        _viewerHeader('Сравниваемое', AppTheme.blue,
            _cmpAligned != null ? '✅' : 'масштабируй'),
        Expanded(
            child: _photoViewer(
                _cmpImg, _cmpCtrl, _cmpKey,
                onEmpty: () => _pickImage(false))),
      ])),
    ]);
  }

  // ── Вид: Просмотр сравнения ───────────────────────
  Widget _comparisonView() {
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    final transform = Matrix4.identity()
      ..scale(_zoom)
      ..rotateZ(_rotation * pi / 180);
    return Container(
      color: Colors.black,
      child: LayoutBuilder(builder: (_, c) {
        return _buildModeView(ref, cmp, transform, c.maxWidth, c.maxHeight);
      }),
    );
  }

  Widget _buildModeView(Uint8List? ref, Uint8List? cmp,
      Matrix4 transform, double w, double h) {
    if (_mode == 'd') {
      return Transform(
        transform: transform,
        alignment: Alignment.center,
        child: Row(children: [
          Expanded(child: ref != null
              ? Image.memory(ref, fit: BoxFit.cover)
              : const Center(child: Text('Эталон',
                  style: TextStyle(color: Colors.white54)))),
          Container(width: 2, color: Colors.white24),
          Expanded(child: cmp != null
              ? Image.memory(cmp, fit: BoxFit.cover)
              : const Center(child: Text('Фото',
                  style: TextStyle(color: Colors.white54)))),
        ]),
      );
    }

    if (_mode == 'o') {
      return Transform(
        transform: transform,
        alignment: Alignment.center,
        child: Stack(fit: StackFit.expand, children: [
          if (ref != null) Image.memory(ref, fit: BoxFit.contain),
          Opacity(
              opacity: _opacity,
              child: cmp != null
                  ? Image.memory(cmp, fit: BoxFit.contain)
                  : const SizedBox()),
        ]),
      );
    }

    // Слайдер (default)
    final divX = (_sliderPos * w).clamp(0.0, w);
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() =>
            _sliderPos = (d.localPosition.dx / w).clamp(0.0, 1.0));
      },
      child: Transform(
        transform: transform,
        alignment: Alignment.center,
        child: Stack(fit: StackFit.expand, children: [
          if (ref != null) Image.memory(ref, fit: BoxFit.contain),
          if (cmp != null)
            ClipRect(
              clipper: _RightClipper(divX),
              child: Image.memory(cmp, fit: BoxFit.contain),
            ),
          Positioned(
              left: divX - 1, top: 0, bottom: 0,
              child: Container(width: 2, color: Colors.white)),
          Positioned(
            left: (divX - 14).clamp(0.0, w - 28),
            top: h / 2 - 14,
            child: Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)]),
              child: const Icon(Icons.compare_arrows,
                  size: 16, color: Colors.black87),
            ),
          ),
          const Positioned(left: 8, top: 8, child: _ImgLabel('Эталон')),
          const Positioned(right: 8, top: 8, child: _ImgLabel('Фото')),
        ]),
      ),
    );
  }

  // ── Таб: Результат ────────────────────────────────
  Widget _tabResult() {
    if (_result == null) {
      return Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Text('📊', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
                'Загрузите оба фото и нажмите\n«Сравнить ›» на вкладке Сравнение',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            XpBtn(
                label: '‹ К сравнению',
                onPressed: () => _tabs.animateTo(1)),
          ]));
    }

    final r = _result!;
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        const SizedBox(height: 10),
        const Center(
            child: Text('РЕЗУЛЬТАТ СРАВНЕНИЯ',
                style: TextStyle(fontSize: 10, color: Colors.grey))),
        const SizedBox(height: 6),
        Center(child: SimBadge(value: r.similarity, fontSize: 26)),
        const SizedBox(height: 6),
        Center(
            child: Text(
          r.similarity >= 80
              ? 'Высокая схожесть'
              : r.similarity >= 70
                  ? 'Средняя схожесть'
                  : 'Низкая схожесть',
          style: TextStyle(
              color: AppTheme.simColor(r.similarity),
              fontWeight: FontWeight.bold),
        )),
        const SizedBox(height: 12),
        XpGroup(
            label: 'Детали',
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth()
              },
              children: [
                _tableRow('Эталон:', r.refSize),
                _tableRow('Фото:', r.cmpSize),
                _tableRow('Итераций:',
                    '${AppConfig.comparisonIter}'),
                _tableRow('Отличий:',
                    '${r.diffPixels} px (${r.diffPercent.toStringAsFixed(1)}%)'),
                _tableRow('Дата:', dateStr),
              ],
            )),
        XpGroup(
            label: 'AI Анализ',
            child: Column(children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: const Text(
                    '🤖 AI анализ доступен в Pro версии.',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.6,
                        color: Colors.grey)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: XpBtn(
                    label: '🤖 AI Анализ (Pro)',
                    onPressed: () => xpDlg(context, 'AI Анализ',
                        'Требуется Pro план'),
                  )),
            ])),
        const SizedBox(height: 12),
        const Divider(),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              XpBtn(
                  label: '‹ Назад',
                  onPressed: () => _tabs.animateTo(1)),
              Row(children: [
                XpBtn(
                    label: '📤',
                    onPressed: () => xpDlg(
                        context, 'Экспорт', 'PNG / PDF / CSV')),
                const SizedBox(width: 4),
                XpBtn(
                    label: '🆕 Новое',
                    primary: true,
                    onPressed: () {
                      setState(() {
                        _refImg = null;
                        _cmpImg = null;
                        _result = null;
                        _refAligned = null;
                        _cmpAligned = null;
                      });
                      _tabs.animateTo(0);
                    }),
              ]),
            ]),
      ]),
    );
  }

  // ── Таб: История ─────────────────────────────────
  Widget _tabHistory() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: XpInput(placeholder: '🔍 Поиск...')),
          const SizedBox(width: 6),
          XpBtn(label: 'Фильтр ▼', onPressed: () {}),
        ]),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration:
            BoxDecoration(border: Border.all(color: AppTheme.border)),
        child: Column(children: [
          Container(
            color: AppTheme.silver,
            child: Row(children: [
              _histCell('Файл', flex: 3, bold: true),
              _histCell('Схожесть', flex: 2, bold: true),
              _histCell('Дата', flex: 2, bold: true),
            ]),
          ),
          ...(_history.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            final sim = item['sim'] as double;
            return GestureDetector(
              onTap: () => _tabs.animateTo(2),
              child: Container(
                color: i.isEven
                    ? Colors.white
                    : const Color(0xFFF5F3EE),
                child: Row(children: [
                  _histCell(item['file'] as String, flex: 3),
                  Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: SimBadge(value: sim, fontSize: 10),
                      )),
                  _histCell(item['date'] as String, flex: 2),
                ]),
              ),
            );
          })),
        ]),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          XpBtn(
              label: '🗑️ Удалить',
              onPressed: () =>
                  xpDlg(context, 'Удалить', 'Удалить выбранное?')),
          const SizedBox(width: 4),
          XpBtn(
              label: '📤 Экспорт',
              onPressed: () =>
                  xpDlg(context, 'Экспорт', 'Экспорт в CSV')),
          const Spacer(),
          XpBtn(
              label: '+ Новое',
              primary: true,
              onPressed: () => _tabs.animateTo(0)),
        ]),
      ),
      const Spacer(),
      XpStatusBar(
          left: 'Записей: ${_history.length}', right: 'Выбрано: 0'),
    ]);
  }

  // ── Helpers ───────────────────────────────────────
  Widget _viewerHeader(String title, Color color, String hint) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: color.withOpacity(0.1),
      child: Row(children: [
        Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(width: 6),
        Text(hint,
            style: const TextStyle(
                fontSize: 9, color: Colors.grey)),
      ]),
    );
  }

  Widget _photoViewer(Uint8List? img, TransformationController ctrl,
      GlobalKey key, {VoidCallback? onEmpty}) {
    if (img == null) {
      return GestureDetector(
        onTap: onEmpty,
        child: Container(
          color: Colors.black87,
          child: Center(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📷',
                  style: TextStyle(fontSize: 32)),
              const SizedBox(height: 6),
              if (onEmpty != null)
                const Text('Нажмите для выбора',
                    style: TextStyle(
                        color: Colors.white54, fontSize: 10)),
            ],
          )),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: key,
          child: Container(
            color: Colors.black,
            child: InteractiveViewer(
              transformationController: ctrl,
              minScale: 0.2,
              maxScale: 8.0,
              child: Image.memory(img, fit: BoxFit.contain),
            ),
          ),
        ),
        // Рамка захвата — IgnorePointer чтобы жесты проходили к фото
        IgnorePointer(
          child: CustomPaint(painter: _FrameOverlayPainter(_framePad)),
        ),
      ],
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            active ? const Color(0xFF003388) : const Color(0xFFE0DDD4),
        foregroundColor: active ? Colors.white : Colors.black87,
        elevation: active ? 2 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      child: Text(label),
    );
  }

  Widget _modeBtn(String mode, String label) {
    final active = _mode == mode;
    return ElevatedButton(
      onPressed: () => setState(() => _mode = mode),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            active ? const Color(0xFF003388) : const Color(0xFFE0DDD4),
        foregroundColor: active ? Colors.white : Colors.black87,
        elevation: active ? 2 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      child: Text(label),
    );
  }

  Widget _toolBtn(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE0DDD4),
        foregroundColor: Colors.black87,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Text(label),
    );
  }

  Widget _check(String label, bool val, ValueChanged<bool> onChange) {
    return Row(children: [
      Checkbox(
          value: val,
          onChanged: (v) => onChange(v ?? val),
          activeColor: AppTheme.blue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }

  TableRow _tableRow(String key, String val) => TableRow(children: [
        Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 3, horizontal: 4),
            child: Text(key,
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey))),
        Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 3, horizontal: 4),
            child: Text(val,
                style: const TextStyle(fontSize: 11))),
      ]);

  Widget _histCell(String text, {int flex = 1, bool bold = false}) =>
      Expanded(
          flex: flex,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
                border: Border(
                    right: BorderSide(color: AppTheme.border))),
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: bold
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ));
}

class _RightClipper extends CustomClipper<Rect> {
  final double x;
  _RightClipper(this.x);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(x, 0, s.width, s.height);
  @override
  bool shouldReclip(_RightClipper o) => o.x != x;
}

// ── Усреднение серии снимков (запускается в isolate) ─
Uint8List _stackImages(List<Uint8List> images) {
  final decoded = <img.Image>[];
  for (final b in images) {
    final d = img.decodeImage(b);
    if (d != null) decoded.add(d);
  }
  if (decoded.isEmpty) return images.first;
  if (decoded.length == 1) return images.first;

  // Resize всех к размеру первого (max 1024px)
  int w = decoded[0].width;
  int h = decoded[0].height;
  if (w > 1024) { h = (h * 1024 / w).round(); w = 1024; }
  if (h > 1024) { w = (w * 1024 / h).round(); h = 1024; }

  final frames = decoded
      .map((d) => img.copyResize(d, width: w, height: h))
      .toList();

  final out = img.Image(width: w, height: h);
  final n = frames.length;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int r = 0, g = 0, b = 0;
      for (final f in frames) {
        final p = f.getPixel(x, y);
        r += p.r.toInt();
        g += p.g.toInt();
        b += p.b.toInt();
      }
      out.setPixelRgb(x, y, r ~/ n, g ~/ n, b ~/ n);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

// Рамка захвата — тёмный оверлей снаружи + белая рамка внутри
class _FrameOverlayPainter extends CustomPainter {
  final double pad;
  const _FrameOverlayPainter(this.pad);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final frame = Rect.fromLTRB(w * pad, h * pad, w * (1 - pad), h * (1 - pad));

    // Затемнение за рамкой
    final outside = Path()
      ..addRect(Rect.fromLTWH(0, 0, w, h))
      ..addRect(frame)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withOpacity(0.50));

    // Белая рамка
    canvas.drawRect(frame,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Угловые маркеры
    const cl = 14.0;
    final cp = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    void corner(Offset a, Offset b, Offset c) {
      canvas.drawLine(a, b, cp);
      canvas.drawLine(b, c, cp);
    }
    corner(Offset(frame.left, frame.top + cl), frame.topLeft,
        Offset(frame.left + cl, frame.top));
    corner(Offset(frame.right - cl, frame.top), frame.topRight,
        Offset(frame.right, frame.top + cl));
    corner(Offset(frame.left, frame.bottom - cl), frame.bottomLeft,
        Offset(frame.left + cl, frame.bottom));
    corner(Offset(frame.right - cl, frame.bottom), frame.bottomRight,
        Offset(frame.right, frame.bottom - cl));
  }

  @override
  bool shouldRepaint(_FrameOverlayPainter old) => old.pad != pad;
}

class _ImgLabel extends StatelessWidget {
  final String text;
  const _ImgLabel(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        color: Colors.black54,
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      );
}
