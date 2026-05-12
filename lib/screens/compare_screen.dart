import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';
import '../services/compare_service.dart';
import '../services/reference_storage.dart';
import '../services/opencv_service.dart';
import '../services/ai_compare_service.dart';
import '../services/barcode_service.dart';
import '../services/ocr_service.dart';
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
  bool   _comparing  = false;
  bool   _aiLoading  = false;
  CompareResult? _result;
  AiAnalysis?    _aiResult;
  List<BarcodeResult> _refBarcodes = [];
  List<BarcodeResult> _cmpBarcodes = [];
  OcrResult? _refOcr;
  OcrResult? _cmpOcr;
  TextDiff?  _textDiff;

  Uint8List? _refAligned;
  Uint8List? _cmpAligned;
  Uint8List? _refOriginal; // оригинал эталона до перспективы
  Uint8List? _cmpOriginal; // оригинал фото до перспективы
  Uint8List? _ref2Img;     // второй снимок эталона для объединения
  AiAnalysis? _refAiResult;
  bool _refAiLoading = false;

  // Ручное наложение на вкладке Эталон (ref1 + ref2)
  final _overlayCtrl = TransformationController();
  double _overlayOpacity = 0.5;
  Size _overlayViewerSize = Size.zero;

  // Раздел 1 вкладки Сравнение: cmp1 + cmp2 → merge
  Uint8List? _cmp2Img;
  final _cmp2Ctrl = TransformationController();
  double _cmp2Opacity = 0.5;
  Size _cmp2ViewerSize = Size.zero;

  // Раздел 2 вкладки Сравнение: ref + cmp → compare
  final _cmpOverlayCtrl = TransformationController();
  double _cmpOverlayOpacity = 0.5;
  Size _cmpOverlayViewerSize = Size.zero;

  // Отступ рамки (10% с каждой стороны = 80% центральная зона)
  static const double _framePad = 0.10;

  bool   _stacking   = false; // идёт усреднение серии

  final _history = [
    {'file': 'photo_001.jpg', 'sim': 87.4, 'date': '16.04.2026'},
    {'file': 'photo_002.jpg', 'sim': 71.2, 'date': '15.04.2026'},
    {'file': 'photo_003.jpg', 'sim': 45.8, 'date': '14.04.2026'},
    {'file': 'photo_004.jpg', 'sim': 93.1, 'date': '13.04.2026'},
  ];

  String? _savedRefLabel;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadSavedReference();
  }

  Future<void> _loadSavedReference() async {
    final bytes = await ReferenceStorage.load();
    final label = await ReferenceStorage.loadLabel();
    if (bytes != null && mounted) {
      setState(() { _refImg = bytes; _savedRefLabel = label; });
    }
  }

  Future<void> _saveReference() async {
    if (_refImg == null) return;
    final now = DateTime.now();
    final label =
        '${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')}.${now.year}';
    await ReferenceStorage.save(_refImg!, label: label);
    if (mounted) {
      setState(() => _savedRefLabel = label);
      xpDlg(context, 'Эталон сохранён', 'Будет загружаться автоматически при следующем запуске.');
    }
  }

  Future<void> _clearReference() async {
    final ok = await xpConfirm(context, 'Сбросить эталон',
        'Удалить сохранённый эталон с устройства?');
    if (!ok) return;
    await ReferenceStorage.clear();
    if (mounted) setState(() { _refImg = null; _savedRefLabel = null; _refAligned = null; });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _overlayCtrl.dispose();
    _cmp2Ctrl.dispose();
    _cmpOverlayCtrl.dispose();
    super.dispose();
  }

  // ── Захват выровненных областей (матричный метод) ─
  Future<Uint8List?> _extractRegion(
      Uint8List imageBytes, Matrix4 transform, Size viewerSize) async {
    if (viewerSize == Size.zero) return null;
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final imgW = decoded.width.toDouble();
    final imgH = decoded.height.toDouble();
    final vw = viewerSize.width;
    final vh = viewerSize.height;

    // BoxFit.contain масштаб и смещение
    final scale = min(vw / imgW, vh / imgH);
    final leftOff = (vw - imgW * scale) / 2;
    final topOff  = (vh - imgH * scale) / 2;

    // Углы рамки в координатах вьювера
    final frameTL = Offset(vw * _framePad, vh * _framePad);
    final frameBR = Offset(vw * (1 - _framePad), vh * (1 - _framePad));

    // Инверсный трансформ: вьювер → дочерний виджет (Image)
    Matrix4 inv;
    try { inv = Matrix4.inverted(transform); }
    catch (_) { inv = Matrix4.identity(); }

    final tl = MatrixUtils.transformPoint(inv, frameTL);
    final br = MatrixUtils.transformPoint(inv, frameBR);

    // Координаты виджета → пиксели изображения
    int px1 = ((tl.dx - leftOff) / scale).round().clamp(0, decoded.width);
    int py1 = ((tl.dy - topOff)  / scale).round().clamp(0, decoded.height);
    int px2 = ((br.dx - leftOff) / scale).round().clamp(0, decoded.width);
    int py2 = ((br.dy - topOff)  / scale).round().clamp(0, decoded.height);

    if (px2 <= px1 || py2 <= py1) return null;

    final cropped = img.copyCrop(decoded,
        x: px1, y: py1, width: px2 - px1, height: py2 - py1);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  // ── Второй снимок сравнения: выбор ───────────────
  Future<void> _pickCmp2(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) setState(() { _cmp2Img = bytes; _cmp2Ctrl.value = Matrix4.identity(); });
  }

  // ── Объединение двух снимков сравнения ────────────
  Future<void> _mergeCmpImages() async {
    if (_cmpImg == null || _cmp2Img == null) return;
    setState(() => _stacking = true);
    try {
      final aligned = await OpenCvService.alignImages(_cmpImg!, _cmp2Img!);
      final merged  = await compute(_averageImages, [_cmpImg!, aligned]);
      if (mounted) setState(() { _cmpImg = merged; _cmpAligned = null; _cmp2Img = null; _cmp2Ctrl.value = Matrix4.identity(); });
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка', e.toString());
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  // ── Совместить фото с эталоном и сравнить ────────
  Future<void> _applyCmpAndCompare() async {
    if (_refImg == null || _cmpImg == null) return;
    if (_cmpOverlayViewerSize != Size.zero) {
      final ref = await _extractRegion(
          _refImg!, Matrix4.identity(), _cmpOverlayViewerSize);
      final cmp = await _extractRegion(
          _cmpImg!, _cmpOverlayCtrl.value, _cmpOverlayViewerSize);
      if (mounted) {
        setState(() {
          _refAligned = ref ?? _refImg;
          _cmpAligned = cmp ?? _cmpImg;
        });
      }
    }
    _runCompare();
  }

  // ── Второй эталон: выбор ─────────────────────────
  Future<void> _pickRef2(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) {
      setState(() {
        _ref2Img = bytes;
        _overlayCtrl.value = Matrix4.identity();
      });
    }
  }

  // ── Объединение двух эталонов через OpenCV ────────
  Future<void> _mergeRefImages() async {
    if (_refImg == null || _ref2Img == null) return;
    setState(() => _stacking = true);
    try {
      final aligned = await OpenCvService.alignImages(_refImg!, _ref2Img!);
      final merged  = await compute(_averageImages, [_refImg!, aligned]);
      if (!mounted) return;
      final now = DateTime.now();
      final label =
          '${now.day.toString().padLeft(2,'0')}.${now.month.toString().padLeft(2,'0')}.${now.year}';
      await ReferenceStorage.save(merged, label: label);
      setState(() {
        _refImg        = merged;
        _refAligned    = null;
        _ref2Img       = null;
        _savedRefLabel = label;
        _overlayCtrl.value = Matrix4.identity();
      });
      xpDlg(context, 'Готово', 'Два снимка объединены и сохранены как эталон.');
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка', e.toString());
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  // ── AI анализ качества эталона ───────────────────
  Future<void> _analyzeReferenceWithAi() async {
    if (_refImg == null) return;
    setState(() { _refAiLoading = true; _refAiResult = null; });
    try {
      // Отправляем эталон дважды — Claude оценивает его качество как образца
      final result = await AiCompareService.analyzeReference(_refImg!);
      if (mounted) setState(() => _refAiResult = result);
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка AI', e.toString());
    } finally {
      if (mounted) setState(() => _refAiLoading = false);
    }
  }

  // ── AI анализ через Claude Vision ─────────────────
  Future<void> _runAiAnalysis() async {
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    if (ref == null || cmp == null) return;
    setState(() => _aiLoading = true);
    try {
      final analysis = await AiCompareService.analyze(ref, cmp);
      if (mounted) setState(() => _aiResult = analysis);
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка AI', e.toString());
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  // ── Коррекция перспективы через OpenCV ───────────
  Future<void> _fixPerspective() async {
    if (_refImg == null && _cmpImg == null) {
      xpDlg(context, 'Ошибка', 'Загрузите изображения');
      return;
    }
    // Сохраняем оригиналы для сброса
    final origRef = _refImg;
    final origCmp = _cmpImg;

    // Обрабатываем оба параллельно
    final futures = <Future<Uint8List>>[];
    if (_refImg != null) futures.add(OpenCvService.perspectiveCorrect(_refImg!));
    if (_cmpImg != null) futures.add(OpenCvService.perspectiveCorrect(_cmpImg!));
    final results = await Future.wait(futures);

    if (!mounted) return;
    setState(() {
      _refOriginal = origRef;
      _cmpOriginal = origCmp;
      int i = 0;
      if (_refImg != null) { _refImg = results[i++]; _refAligned = null; }
      if (_cmpImg != null) { _cmpImg = results[i++]; _cmpAligned = null; }
    });
  }

  // ── Сравнение ─────────────────────────────────────
  Future<void> _runCompare() async {
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    if (ref == null || cmp == null) {
      xpDlg(context, 'Ошибка', 'Загрузите оба изображения');
      return;
    }
    setState(() {
      _comparing = true;
      _aiResult = null;
      _refBarcodes = [];
      _cmpBarcodes = [];
      _refOcr = null;
      _cmpOcr = null;
      _textDiff = null;
      _result = null;
    });
    try {
      // Фаза 1: сравнение пикселей — быстро, показываем результат сразу
      final compareResult = await CompareService.compare(ref, cmp);
      if (!mounted) return;
      setState(() { _result = compareResult; _comparing = false; });
      _tabs.animateTo(2);

      // OpenCV SSIM — точнее MAE, обновляем результат если доступен
      OpenCvService.ssim(ref, cmp).then((ssim) {
        if (ssim != null && ssim > 0 && mounted && _result != null) {
          final r = _result!;
          setState(() => _result = CompareResult(
            similarity: r.similarity,
            ssim: ssim, // OpenCV уже возвращает 0–100
            diffPixels: r.diffPixels,
            totalPixels: r.totalPixels,
            refSize: r.refSize,
            cmpSize: r.cmpSize,
            diffImage: r.diffImage,
          ));
        }
      }).catchError((_) {});

      // Фаза 2: штрихкоды + OCR — фоном, обновляем результат когда готово
      Future<OcrResult> ocrSafe(Uint8List b) => OcrService.recognize(b)
          .timeout(const Duration(seconds: 15),
              onTimeout: () => OcrResult('', [], error: 'Таймаут OCR'))
          .catchError((Object e) => OcrResult('', [], error: e.toString()));

      final extras = await Future.wait([
        BarcodeService.scanImage(ref)
            .catchError((Object _) => <BarcodeResult>[]),
        BarcodeService.scanImage(cmp)
            .catchError((Object _) => <BarcodeResult>[]),
        ocrSafe(ref),
        ocrSafe(cmp),
      ]);
      if (!mounted) return;
      final ro = extras[2] as OcrResult;
      final co = extras[3] as OcrResult;
      setState(() {
        _refBarcodes = extras[0] as List<BarcodeResult>;
        _cmpBarcodes = extras[1] as List<BarcodeResult>;
        _refOcr      = ro;
        _cmpOcr      = co;
        _textDiff    = (!ro.isEmpty || !co.isEmpty)
            ? OcrService.compareTexts(ro.fullText, co.fullText)
            : null;
      });
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка сравнения', e.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
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
              title: const Text('Серия снимков'),
              subtitle: const Text('Усреднение для чистоты изображения',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
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
      // Шаг 1: выравниваем через OpenCV ORB (основной поток)
      final aligned = <Uint8List>[shots[0]];
      for (int i = 1; i < shots.length; i++) {
        final a = await OpenCvService.alignImages(shots[0], shots[i]);
        aligned.add(a);
      }
      // Шаг 2: усредняем пиксели в isolate
      final result = await compute(_averageImages, aligned);
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
              label: 'Перспектива',
              icon: '📐',
              onTap: _fixPerspective),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'AI Анализ',
              icon: '🤖',
              onTap: _runAiAnalysis),
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
        // ── Эталонное изображение ────────────────────
        XpGroup(
            label: 'Эталонное изображение',
            child: Column(children: [
              GestureDetector(
                onTap: () => _pickImage(true),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.black,
                  child: _stacking
                      ? const Center(child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 8),
                            Text('Объединение снимков...',
                                style: TextStyle(fontSize: 11, color: Colors.white70)),
                          ]))
                      : _refImg != null
                      ? Image.memory(_refImg!, fit: BoxFit.contain)
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🖼️', style: TextStyle(fontSize: 40)),
                            SizedBox(height: 8),
                            Text('Нажмите для выбора',
                                style: TextStyle(fontSize: 11, color: Colors.white54)),
                            Text('JPEG, PNG, TIFF, RAW',
                                style: TextStyle(fontSize: 10, color: Colors.white38)),
                          ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: XpBtn(label: '📂 Файл',    onPressed: () => _pickImage(true))),
                const SizedBox(width: 4),
                Expanded(child: XpBtn(label: '🖼️ Галерея', onPressed: () => _pickImage(true))),
                const SizedBox(width: 4),
                Expanded(child: XpBtn(label: '📷 Камера',  onPressed: () => _pickImage(true))),
              ]),
            ])),

        if (_savedRefLabel != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.simHigh.withOpacity(0.08),
              border: Border.all(color: AppTheme.simHigh.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Text('💾', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(child: Text('Сохранён: $_savedRefLabel',
                  style: const TextStyle(fontSize: 11, color: AppTheme.simHigh))),
              XpBtn(label: '🗑 Сбросить', danger: true, onPressed: _clearReference),
            ]),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: XpBtn(
              label: '💾 Сохранить эталон',
              primary: true,
              onPressed: _refImg != null ? _saveReference : null)),
        ]),

        // ── Наложить и совместить ────────────────────
        if (_refImg != null) ...[
          const SizedBox(height: 8),
          XpGroup(
              label: 'Наложить и совместить',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Если второй снимок не загружен — кнопки выбора
                if (_ref2Img == null) ...[
                  const Text(
                      'Загрузите второй снимок эталона для объединения.\n'
                      'OpenCV выровняет и усреднит оба снимка.',
                      style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: XpBtn(
                        label: '🖼️ Галерея',
                        onPressed: () => _pickRef2(ImageSource.gallery))),
                    const SizedBox(width: 4),
                    Expanded(child: XpBtn(
                        label: '📷 Камера',
                        onPressed: () => _pickRef2(ImageSource.camera))),
                  ]),
                ] else ...[
                  // Overlay: эталон 1 (фон) + эталон 2 (двигается)
                  ClipRect(
                    child: Container(
                      height: 240,
                      color: Colors.black,
                      child: LayoutBuilder(builder: (_, c) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _overlayViewerSize = Size(c.maxWidth, c.maxHeight);
                        });
                        return Stack(fit: StackFit.expand, children: [
                          Image.memory(_refImg!, fit: BoxFit.contain),
                          Opacity(
                            opacity: _overlayOpacity,
                            child: InteractiveViewer(
                              transformationController: _overlayCtrl,
                              boundaryMargin: const EdgeInsets.all(double.infinity),
                              minScale: 0.1,
                              maxScale: 6.0,
                              child: Image.memory(_ref2Img!, fit: BoxFit.contain),
                            ),
                          ),
                          const Positioned(left: 8, top: 8,
                              child: _ImgLabel('Эталон 1')),
                          const Positioned(right: 8, top: 8,
                              child: _ImgLabel('Эталон 2 ↕↔')),
                        ]);
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const SizedBox(width: 90,
                        child: Text('Прозрачность:', style: TextStyle(fontSize: 11))),
                    Expanded(child: Slider(
                      value: _overlayOpacity,
                      onChanged: (v) => setState(() => _overlayOpacity = v),
                      activeColor: AppTheme.blue,
                    )),
                    Text('${(_overlayOpacity * 100).round()}%',
                        style: const TextStyle(fontSize: 10)),
                  ]),
                  Row(children: [
                    XpBtn(
                        label: '🗑 Убрать',
                        danger: true,
                        onPressed: () => setState(() {
                          _ref2Img = null;
                          _overlayCtrl.value = Matrix4.identity();
                        })),
                    const Spacer(),
                    XpBtn(
                        label: '🔀 OpenCV объединить',
                        primary: true,
                        onPressed: _stacking ? null : _mergeRefImages),
                  ]),
                ],

                // AI анализ эталона
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 6),
                if (_refAiLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('AI анализирует эталон...', style: TextStyle(fontSize: 11)),
                    ]),
                  ))
                else if (_refAiResult != null) ...[
                  _aiVerdictBadge(_refAiResult!),
                  const SizedBox(height: 6),
                  if (_refAiResult!.recommendations.isNotEmpty)
                    ..._refAiResult!.recommendations.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('• ', style: TextStyle(fontSize: 11)),
                        Expanded(child: Text(r, style: const TextStyle(fontSize: 11, height: 1.4))),
                      ]),
                    )),
                  const SizedBox(height: 6),
                  XpBtn(label: '🔄 Повторить AI анализ', onPressed: _analyzeReferenceWithAi),
                ] else
                  XpBtn(
                      label: '🤖 AI анализ качества эталона',
                      onPressed: _refImg != null ? _analyzeReferenceWithAi : null),
              ])),
        ],

        const SizedBox(height: 12),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          XpBtn(label: 'Далее ›', primary: true, onPressed: () => _tabs.animateTo(1)),
        ]),
      ]),
    );
  }

  // ── Таб: Сравнение ────────────────────────────────
  Widget _tabCmp() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [

        // ── Раздел 1: фото1 + фото2 → объединить ────
        XpGroup(
            label: 'Сравниваемое изображение',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Фото1 — основное
              GestureDetector(
                onTap: () => _pickImage(false),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.black,
                  child: _stacking
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 8),
                          Text('Объединение снимков...', style: TextStyle(fontSize: 11, color: Colors.white70)),
                        ]))
                      : _cmpImg != null
                          ? Image.memory(_cmpImg!, fit: BoxFit.contain)
                          : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('📷', style: TextStyle(fontSize: 40)),
                              SizedBox(height: 8),
                              Text('Нажмите для выбора', style: TextStyle(fontSize: 11, color: Colors.white54)),
                              Text('JPEG, PNG, TIFF, RAW', style: TextStyle(fontSize: 10, color: Colors.white38)),
                            ]),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: XpBtn(label: '📂 Файл',    onPressed: () => _pickImage(false))),
                const SizedBox(width: 4),
                Expanded(child: XpBtn(label: '🖼️ Галерея', onPressed: () => _pickImage(false))),
                const SizedBox(width: 4),
                Expanded(child: XpBtn(label: '📷 Камера',  onPressed: () => _pickImage(false))),
              ]),

              // Фото2 — для объединения
              if (_cmpImg != null) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 6),
                if (_cmp2Img == null) ...[
                  const Text('Загрузите второй снимок для объединения:',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: XpBtn(label: '🖼️ Галерея', onPressed: () => _pickCmp2(ImageSource.gallery))),
                    const SizedBox(width: 4),
                    Expanded(child: XpBtn(label: '📷 Камера',  onPressed: () => _pickCmp2(ImageSource.camera))),
                  ]),
                ] else ...[
                  // Overlay: фото1 (фон) + фото2 (двигается)
                  ClipRect(
                    child: Container(
                      height: 240,
                      color: Colors.black,
                      child: LayoutBuilder(builder: (_, c) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _cmp2ViewerSize = Size(c.maxWidth, c.maxHeight);
                        });
                        return Stack(fit: StackFit.expand, children: [
                          Image.memory(_cmpImg!, fit: BoxFit.contain),
                          Opacity(
                            opacity: _cmp2Opacity,
                            child: InteractiveViewer(
                              transformationController: _cmp2Ctrl,
                              boundaryMargin: const EdgeInsets.all(double.infinity),
                              minScale: 0.1, maxScale: 6.0,
                              child: Image.memory(_cmp2Img!, fit: BoxFit.contain),
                            ),
                          ),
                          const Positioned(left: 8, top: 8, child: _ImgLabel('Фото 1')),
                          const Positioned(right: 8, top: 8, child: _ImgLabel('Фото 2 ↕↔')),
                        ]);
                      }),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const SizedBox(width: 90, child: Text('Прозрачность:', style: TextStyle(fontSize: 11))),
                    Expanded(child: Slider(
                      value: _cmp2Opacity,
                      onChanged: (v) => setState(() => _cmp2Opacity = v),
                      activeColor: AppTheme.blue,
                    )),
                    Text('${(_cmp2Opacity * 100).round()}%', style: const TextStyle(fontSize: 10)),
                  ]),
                  Row(children: [
                    XpBtn(label: '🗑 Убрать', danger: true,
                        onPressed: () => setState(() { _cmp2Img = null; _cmp2Ctrl.value = Matrix4.identity(); })),
                    const Spacer(),
                    XpBtn(label: '🔀 OpenCV объединить', primary: true,
                        onPressed: _stacking ? null : _mergeCmpImages),
                  ]),
                ],
              ],
            ])),

        // ── Раздел 2: эталон + фото → сравнить ──────
        if (_refImg != null && _cmpImg != null) ...[
          const SizedBox(height: 8),
          XpGroup(
              label: 'Совместить с эталоном',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Перетащите фото поверх эталона. Совместите — нажмите Сравнить.',
                    style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
                const SizedBox(height: 8),
                ClipRect(
                  child: Container(
                    height: 240,
                    color: Colors.black,
                    child: LayoutBuilder(builder: (_, c) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _cmpOverlayViewerSize = Size(c.maxWidth, c.maxHeight);
                      });
                      return Stack(fit: StackFit.expand, children: [
                        Image.memory(_refImg!, fit: BoxFit.contain),
                        Opacity(
                          opacity: _cmpOverlayOpacity,
                          child: InteractiveViewer(
                            transformationController: _cmpOverlayCtrl,
                            boundaryMargin: const EdgeInsets.all(double.infinity),
                            minScale: 0.1, maxScale: 6.0,
                            child: Image.memory(_cmpImg!, fit: BoxFit.contain),
                          ),
                        ),
                        const Positioned(left: 8, top: 8, child: _ImgLabel('Эталон')),
                        const Positioned(right: 8, top: 8, child: _ImgLabel('Фото ↕↔')),
                      ]);
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const SizedBox(width: 90, child: Text('Прозрачность:', style: TextStyle(fontSize: 11))),
                  Expanded(child: Slider(
                    value: _cmpOverlayOpacity,
                    onChanged: (v) => setState(() => _cmpOverlayOpacity = v),
                    activeColor: AppTheme.blue,
                  )),
                  Text('${(_cmpOverlayOpacity * 100).round()}%', style: const TextStyle(fontSize: 10)),
                ]),
                Row(children: [
                  XpBtn(label: '📐 Перспектива', onPressed: _fixPerspective),
                  if (_refOriginal != null || _cmpOriginal != null) ...[
                    const SizedBox(width: 4),
                    XpBtn(label: '↩ Сброс', onPressed: () => setState(() {
                      if (_refOriginal != null) { _refImg = _refOriginal; _refOriginal = null; _refAligned = null; }
                      if (_cmpOriginal != null) { _cmpImg = _cmpOriginal; _cmpOriginal = null; _cmpAligned = null; }
                    })),
                  ],
                  const Spacer(),
                  XpBtn(label: '⟳', onPressed: () => setState(() => _cmpOverlayCtrl.value = Matrix4.identity())),
                ]),
              ])),
        ],

        const SizedBox(height: 12),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          XpBtn(label: '‹ Эталон', onPressed: () => _tabs.animateTo(0)),
          Row(children: [
            if (_result != null) ...[
              SimBadge(value: _result!.score),
              const SizedBox(width: 8),
            ],
            _comparing
                ? const SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : XpBtn(
                    label: 'Сравнить ›',
                    primary: true,
                    onPressed: _refImg != null && _cmpImg != null ? _applyCmpAndCompare : null),
          ]),
        ]),
      ]),
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
        Center(child: SimBadge(value: r.score, fontSize: 26)),
        if (r.ssim != null)
          Center(child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('SSIM: ${r.ssim!.toStringAsFixed(1)}%  ·  MAE: ${r.similarity.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          )),
        const SizedBox(height: 6),
        Center(
            child: Text(
          r.score >= 80
              ? 'Высокая схожесть'
              : r.score >= 70
                  ? 'Средняя схожесть'
                  : 'Низкая схожесть',
          style: TextStyle(
              color: AppTheme.simColor(r.score),
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
        if (r.diffImage != null)
          XpGroup(
              label: 'Карта различий',
              child: Column(children: [
                Container(
                  height: 200,
                  color: Colors.black,
                  child: Stack(fit: StackFit.expand, children: [
                    if (_refAligned != null || _refImg != null)
                      Image.memory(
                          _refAligned ?? _refImg!, fit: BoxFit.contain),
                    Image.memory(r.diffImage!, fit: BoxFit.contain),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _legendItem(const Color(0xFF1ED21E), 'Небольшие (4–20%)'),
                  const SizedBox(width: 8),
                  _legendItem(const Color(0xFFFFAA00), 'Средние (20–45%)'),
                  const SizedBox(width: 8),
                  _legendItem(const Color(0xFFF01414), 'Сильные (>45%)'),
                ]),
              ])),
        if (_refBarcodes.isNotEmpty || _cmpBarcodes.isNotEmpty)
          XpGroup(
              label: 'Штрихкоды / QR',
              child: Column(children: [
                if (_refBarcodes.isNotEmpty) ...[
                  const Text('Эталон:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ..._refBarcodes.map(_barcodeTile),
                  const SizedBox(height: 6),
                ],
                if (_cmpBarcodes.isNotEmpty) ...[
                  const Text('Фото:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ..._cmpBarcodes.map(_barcodeTile),
                ],
                if (_refBarcodes.isNotEmpty && _cmpBarcodes.isNotEmpty)
                  _barcodeMatchSummary(),
              ])),
        if (_refBarcodes.isEmpty && _cmpBarcodes.isEmpty && _result != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.qr_code, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              const Text('Штрихкоды не обнаружены',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        if (_refOcr != null || _cmpOcr != null)
          XpGroup(label: 'Текст (OCR)', child: _ocrSection()),
        XpGroup(
            label: 'AI Анализ',
            child: Column(children: [
              if (_aiResult == null && !_aiLoading) ...[
                const Text(
                    'Claude Vision анализирует оба изображения и находит конкретные проблемы печати.',
                    style: TextStyle(fontSize: 11, height: 1.6, color: Colors.grey)),
                const SizedBox(height: 8),
                SizedBox(
                    width: double.infinity,
                    child: XpBtn(
                        label: '🤖 Запустить AI анализ',
                        primary: true,
                        onPressed: _runAiAnalysis)),
              ],
              if (_aiLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Claude анализирует...', style: TextStyle(fontSize: 12)),
                  ]),
                ),
              if (_aiResult != null) ...[
                _aiVerdictBadge(_aiResult!),
                const SizedBox(height: 8),
                if (_aiResult!.hasIssues) ...[
                  ..._aiResult!.issues.map(_aiIssueTile),
                  const SizedBox(height: 8),
                ],
                if (_aiResult!.recommendations.isNotEmpty) ...[
                  const Text('Рекомендации:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ..._aiResult!.recommendations.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('• ', style: TextStyle(fontSize: 11)),
                          Expanded(child: Text(r, style: const TextStyle(fontSize: 11, height: 1.5))),
                        ]),
                      )),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                    width: double.infinity,
                    child: XpBtn(
                        label: '🔄 Повторить анализ',
                        onPressed: _runAiAnalysis)),
              ],
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
                        _aiResult = null;
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

  Widget _barcodeTile(BarcodeResult b) {
    final verdictColor = Color(b.verdictColor);
    final hasDims = b.widthPx > 0 && b.heightPx > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: verdictColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Формат — крупно
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: verdictColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(b.displayFormat,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            const Spacer(),
            if (hasDims)
              Text('${b.widthPx}×${b.heightPx} px',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          // Значение — крупно
          Text(b.value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Масштаб
          Row(children: [
            Icon(Icons.straighten, size: 16, color: verdictColor),
            const SizedBox(width: 6),
            Expanded(child: Text(
              b.scalePct > 0
                  ? 'Масштаб ${b.scalePct.toStringAsFixed(0)}%'
                      '  (норма ${b.minPct.toInt()}–${b.maxPct.toInt()}%)'
                  : 'Масштаб не определён',
              style: TextStyle(fontSize: 12, color: verdictColor,
                  fontWeight: FontWeight.bold),
            )),
          ]),
          const SizedBox(height: 4),
          Text(b.scaleVerdict,
              style: TextStyle(fontSize: 12, color: verdictColor)),
        ]),
      ),
    );
  }

  Widget _ocrSection() {
    final diff = _textDiff;
    final refText = _refOcr?.fullText.trim() ?? '';
    final cmpText = _cmpOcr?.fullText.trim() ?? '';
    final refErr  = _refOcr?.error;
    final cmpErr  = _cmpOcr?.error;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Ошибка OCR
      if (refErr != null || cmpErr != null)
        Container(
          padding: const EdgeInsets.all(8),
          color: AppTheme.simLow.withOpacity(0.08),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.error_outline, size: 14, color: AppTheme.simLow),
              SizedBox(width: 6),
              Text('Ошибка OCR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.simLow)),
            ]),
            if (refErr != null) ...[
              const SizedBox(height: 4),
              Text('Эталон: $refErr', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ],
            if (cmpErr != null) ...[
              const SizedBox(height: 4),
              Text('Фото: $cmpErr', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            ],
            const SizedBox(height: 6),
            const Text(
              'Добавьте в AndroidManifest.xml внутри <application>:\n'
              '<meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="ocr"/>',
              style: TextStyle(fontSize: 9, color: Colors.black45, fontFamily: 'monospace'),
            ),
          ]),
        ),
      // Нет текста (OCR сработал но ничего не нашёл)
      if (refErr == null && cmpErr == null && refText.isEmpty && cmpText.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.text_fields, size: 14, color: Colors.grey),
            SizedBox(width: 6),
            Text('Текст на изображениях не обнаружен',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
      // Совпадение
      if (diff != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: diff.allOk
              ? AppTheme.simHigh.withOpacity(0.08)
              : diff.similarity >= 80
                  ? AppTheme.simMid.withOpacity(0.08)
                  : AppTheme.simLow.withOpacity(0.08),
          child: Row(children: [
            Icon(
              diff.allOk ? Icons.check_circle : Icons.warning,
              size: 16,
              color: diff.allOk
                  ? AppTheme.simHigh
                  : diff.similarity >= 80 ? AppTheme.simMid : AppTheme.simLow,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              diff.allOk
                  ? 'Текст совпадает полностью'
                  : 'Совпадение текста: ${diff.similarity.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: diff.allOk
                    ? AppTheme.simHigh
                    : diff.similarity >= 80 ? AppTheme.simMid : AppTheme.simLow,
              ),
            )),
          ]),
        ),
        const SizedBox(height: 6),
        // Отсутствующие слова
        if (diff.missing.isNotEmpty)
          _ocrDiffChips('🔴 Нет на фото', diff.missing, AppTheme.simLow),
        // Лишние слова
        if (diff.extra.isNotEmpty)
          _ocrDiffChips('🟡 Лишнее на фото', diff.extra, AppTheme.simMid),
        const SizedBox(height: 4),
      ],
      // Распознанный текст
      if (refText.isNotEmpty)
        _ocrTextBlock('Текст эталона', refText),
      if (cmpText.isNotEmpty)
        _ocrTextBlock('Текст фото', cmpText),
    ]);
  }

  Widget _ocrDiffChips(String label, List<String> words, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: words.take(30).map((w) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(w, style: TextStyle(fontSize: 10, color: color)),
          )).toList(),
        ),
        if (words.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('...и ещё ${words.length - 30}',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ),
      ]),
    );
  }

  Widget _ocrTextBlock(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text.length > 500 ? '${text.substring(0, 500)}…' : text,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
        ),
      ]),
    );
  }

  Widget _barcodeMatchSummary() {
    final refVals = {for (final b in _refBarcodes) b.value: b};
    final cmpVals = {for (final b in _cmpBarcodes) b.value: b};

    final issues = <_BarcodeIssue>[];

    // Коды есть в эталоне но нет в фото — ошибка
    for (final v in refVals.keys) {
      if (!cmpVals.containsKey(v)) {
        issues.add(_BarcodeIssue.error(
            'Код отсутствует на фото',
            'Значение: $v (${refVals[v]!.displayFormat})'));
      }
    }

    // Коды есть в фото но нет в эталоне — предупреждение
    for (final v in cmpVals.keys) {
      if (!refVals.containsKey(v)) {
        issues.add(_BarcodeIssue.warning(
            'Лишний код на фото',
            'Значение: $v (${cmpVals[v]!.displayFormat})'));
      }
    }

    // Масштаб вне нормы — предупреждение
    for (final b in [..._refBarcodes, ..._cmpBarcodes]) {
      if (b.scalePct > 0 && b.scalePct < b.minPct) {
        issues.add(_BarcodeIssue.warning(
            'Масштаб ниже минимума',
            '${b.displayFormat}: ${b.scalePct.toStringAsFixed(0)}% '
            '(мин. ${b.minPct.toInt()}%) — камера может не считать'));
      }
      if (b.scalePct > 0 && b.scalePct > b.maxPct) {
        issues.add(_BarcodeIssue.warning(
            'Масштаб выше максимума',
            '${b.displayFormat}: ${b.scalePct.toStringAsFixed(0)}% '
            '(макс. ${b.maxPct.toInt()}%)'));
      }
    }

    final hasErrors   = issues.any((i) => i.isError);
    final hasWarnings = issues.any((i) => !i.isError);
    final allOk = issues.isEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 6),
      // Общий статус
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: allOk
            ? AppTheme.simHigh.withOpacity(0.08)
            : hasErrors
                ? AppTheme.simLow.withOpacity(0.08)
                : AppTheme.simMid.withOpacity(0.08),
        child: Row(children: [
          Icon(
            allOk ? Icons.check_circle : hasErrors ? Icons.error : Icons.warning,
            size: 16,
            color: allOk ? AppTheme.simHigh : hasErrors ? AppTheme.simLow : AppTheme.simMid,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(
            allOk
                ? '✅ Все коды совпадают, масштаб в норме'
                : hasErrors
                    ? '🔴 Обнаружены ошибки в кодах'
                    : '🟡 Предупреждения',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: allOk ? AppTheme.simHigh : hasErrors ? AppTheme.simLow : AppTheme.simMid,
            ),
          )),
        ]),
      ),
      // Список проблем
      ...issues.map((issue) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(
            color: issue.isError ? AppTheme.simLow : AppTheme.simMid,
            width: 3,
          )),
          color: (issue.isError ? AppTheme.simLow : AppTheme.simMid).withOpacity(0.05),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              issue.isError ? '🔴 ОШИБКА' : '🟡 ПРЕДУПРЕЖДЕНИЕ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: issue.isError ? AppTheme.simLow : AppTheme.simMid,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(issue.title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 2),
          Text(issue.detail, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ]),
      )),
      if (!allOk && !hasErrors && hasWarnings)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Коды совпадают, но есть предупреждения по масштабу.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ),
    ]);
  }

  Widget _aiVerdictBadge(AiAnalysis ai) {
    final colors = {
      'отлично': AppTheme.simHigh,
      'хорошо': AppTheme.simHigh,
      'удовлетворительно': AppTheme.simMid,
      'плохо': AppTheme.simLow,
    };
    final color = colors[ai.verdict] ?? AppTheme.simMid;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(ai.verdict.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          const Spacer(),
          Text('${ai.score.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ]),
        const SizedBox(height: 4),
        Text(ai.summary, style: const TextStyle(fontSize: 11, height: 1.5)),
      ]),
    );
  }

  Widget _aiIssueTile(PrintIssue issue) {
    final color = Color(issue.severityColor);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 3)),
        color: color.withOpacity(0.05),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(issue.type, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          Text('• ${issue.severity}', style: TextStyle(fontSize: 10, color: color)),
          const SizedBox(width: 6),
          Expanded(child: Text(issue.location,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 3),
        Text(issue.description, style: const TextStyle(fontSize: 11, height: 1.4)),
      ]),
    );
  }

  Widget _legendItem(Color color, String label) => Row(children: [
        Container(
          width: 12, height: 12,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
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

// Простое усреднение пикселей (изображения уже выровнены через OpenCV)
Uint8List _averageImages(List<Uint8List> images) {
  final decoded = <img.Image>[];
  for (final b in images) {
    final d = img.decodeImage(b);
    if (d != null) decoded.add(d);
  }
  if (decoded.isEmpty) return images.first;
  if (decoded.length == 1) return images.first;

  int w = decoded[0].width;
  int h = decoded[0].height;
  if (w > 1024) { h = (h * 1024 / w).round(); w = 1024; }
  if (h > 1024) { w = (w * 1024 / h).round(); h = 1024; }

  final frames = decoded.map((d) => img.copyResize(d, width: w, height: h)).toList();
  final out = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int r = 0, g = 0, b = 0;
      for (final f in frames) {
        final p = f.getPixel(x, y);
        r += p.r.toInt(); g += p.g.toInt(); b += p.b.toInt();
      }
      final n = frames.length;
      out.setPixelRgb(x, y, r ~/ n, g ~/ n, b ~/ n);
    }
  }
  return Uint8List.fromList(img.encodePng(out));
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

class _BarcodeIssue {
  final bool isError;
  final String title;
  final String detail;
  const _BarcodeIssue.error(this.title, this.detail) : isError = true;
  const _BarcodeIssue.warning(this.title, this.detail) : isError = false;
}
