import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';
import '../services/compare_service.dart';
import '../services/reference_storage.dart';
import '../services/opencv_service.dart';
import '../services/ai_compare_service.dart';
import '../services/barcode_service.dart';
import '../services/ocr_service.dart';
import '../config/app_config.dart';
import '../widgets/crop_frame_screen.dart';
import '../widgets/anchor_point_screen.dart';
import '../models/layout_profile.dart';
import '../services/layout_profile_storage.dart';
import '../database/local_database.dart';

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
  Uint8List? _ref2Img;     // второй снимок эталона для выбора
  double? _ref1Sharpness;  // резкость эталона 1
  double? _ref2Sharpness;  // резкость эталона 2
  AiAnalysis? _refAiResult;
  bool _refAiLoading = false;

  // Ручное наложение на вкладке Эталон (ref1 + ref2)
  final _overlayCtrl = TransformationController();
  double _overlayOpacity = 0.5;
  Size _overlayViewerSize = Size.zero;

  // Вкладка Образец: cmp1 + cmp2 → merge
  Uint8List? _cmp2Img;
  double? _cmp1Sharpness;
  double? _cmp2Sharpness;
  final _cmp2Ctrl = TransformationController();
  double _cmp2Opacity = 0.5;

  // Вкладка Совмещение: два окна предпросмотра с якорными точками
  final _refAlignCtrl = TransformationController();
  final _cmpAlignCtrl = TransformationController();
  List<Offset>? _refAnchorPts; // подтверждённые точки на эталоне
  List<Offset>? _cmpAnchorPts; // подтверждённые точки на образце
  Size? _refImgSize;
  Size? _cmpImgSize;
  // Пошаговая калибровка: 0=нет, 1=ставим на эталоне, 2=ставим на образце, 3=расчёт
  int _calStep = 0;
  List<Offset> _tempRefPts = [];
  List<Offset> _tempCmpPts = [];
  static const int _minAnchorPts = 4;
  static const int _maxAnchorPts = 8;

  // Отступ рамки (10% с каждой стороны = 80% центральная зона)
  static const double _framePad = 0.10;

  bool   _stacking      = false;
  bool   _showDiffL3    = false;
  double _resultOpacity = 0.5;

  final _history = [
    {'file': 'photo_001.jpg', 'sim': 87.4, 'date': '16.04.2026'},
    {'file': 'photo_002.jpg', 'sim': 71.2, 'date': '15.04.2026'},
    {'file': 'photo_003.jpg', 'sim': 45.8, 'date': '14.04.2026'},
    {'file': 'photo_004.jpg', 'sim': 93.1, 'date': '13.04.2026'},
  ];

  String? _savedRefLabel;

  // ── Калибровка / Layout Profile ──────────────────
  LayoutProfile? _layoutProfile;
  bool _calibrating = false;
  List<LayoutProfile> _savedProfiles = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadSavedReference();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final profiles = await LayoutProfileStorage.loadAll();
    if (mounted) setState(() => _savedProfiles = profiles);
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
    if (mounted) setState(() {
      _refImg = null; _refImgSize = null;
      _savedRefLabel = null; _refAligned = null;
      _layoutProfile = null; _cmpAligned = null;
      _refAnchorPts = null; _cmpAnchorPts = null;
    });
  }

  // ── Калибровка: пошаговая расстановка точек прямо на панелях ───────────
  void _startCalibration() {
    setState(() {
      _calStep = 1;
      _tempRefPts = [];
      _tempCmpPts = [];
    });
  }

  void _cancelCalibration() {
    setState(() { _calStep = 0; _tempRefPts = []; _tempCmpPts = []; });
  }

  void _addPanelPoint(Offset imgCoord) {
    setState(() {
      if (_calStep == 1 && _tempRefPts.length < _maxAnchorPts) {
        _tempRefPts = [..._tempRefPts, imgCoord];
      } else if (_calStep == 2 && _tempCmpPts.length < _maxAnchorPts) {
        _tempCmpPts = [..._tempCmpPts, imgCoord];
      }
    });
  }

  void _undoLastPoint() {
    setState(() {
      if (_calStep == 1 && _tempRefPts.isNotEmpty) {
        _tempRefPts = _tempRefPts.sublist(0, _tempRefPts.length - 1);
      } else if (_calStep == 2 && _tempCmpPts.isNotEmpty) {
        _tempCmpPts = _tempCmpPts.sublist(0, _tempCmpPts.length - 1);
      }
    });
  }

  // Шаг 1 → 2 (переключаем на образец)
  void _advanceToStep2() {
    if (_tempRefPts.length < _minAnchorPts) return;
    setState(() { _calStep = 2; _tempCmpPts = []; });
  }

  // Шаг 2 → расчёт
  Future<void> _runAlignmentFromPoints() async {
    if (_tempCmpPts.length != _tempRefPts.length) return;
    final refPts = List<Offset>.from(_tempRefPts);
    final cmpPts = List<Offset>.from(_tempCmpPts);
    setState(() { _calStep = 3; _calibrating = true; });
    try {
      final alignResult = await OpenCvService.alignByAnchors(
        _refImg!, _cmpImg!, refPts, cmpPts,
      );
      if (!mounted) return;
      if (alignResult == null) {
        xpDlg(context, 'Ошибка', 'Не удалось рассчитать совмещение. Попробуйте расставить точки точнее.');
        setState(() { _calStep = 1; _tempRefPts = []; _tempCmpPts = []; });
        return;
      }

      final ok = await _showAlignmentValidation(alignResult);
      if (!ok || !mounted) { setState(() { _calStep = 0; _tempRefPts = []; _tempCmpPts = []; }); return; }

      final name = await _promptProfileName();
      if (name == null || !mounted) { setState(() { _calStep = 0; _tempRefPts = []; _tempCmpPts = []; }); return; }

      final refDecoded = await compute(_decodeSize, _refImg!);
      final refW = refDecoded.width.toDouble();
      final refH = refDecoded.height.toDouble();
      final refAnchors = refPts.asMap().entries.map((e) => AnchorPoint(
        id: _anchorId(e.key, refPts.length),
        x: e.value.dx / refW,
        y: e.value.dy / refH,
        type: 'corner', confidence: 1.0,
      )).toList();

      final profile = LayoutProfile(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        refAnchors: refAnchors,
        homography: alignResult.homography,
        cropRegion: CropRegion.defaultCrop,
        widthMm: AppConfig.printWidthMm,
        heightMm: AppConfig.printHeightMm,
        refImageWidth: refDecoded.width,
        refImageHeight: refDecoded.height,
        alignment: AlignmentInfo(
          reprojectionError: alignResult.reprojError,
          eccScore: alignResult.eccScore,
          confidence: alignResult.confidence,
        ),
        createdAt: DateTime.now(),
      );
      await LayoutProfileStorage.save(profile);
      await _loadProfiles();

      setState(() {
        _layoutProfile = profile;
        _cmpAligned = alignResult.alignedBytes;
        _refAnchorPts = refPts;
        _cmpAnchorPts = cmpPts;
        _calStep = 0;
        _tempRefPts = [];
        _tempCmpPts = [];
      });

      xpDlg(context, 'Профиль сохранён',
          '"$name"\n${alignResult.qualityLabel}  ·  ошибка ${alignResult.reprojError.toStringAsFixed(1)} пкс');
    } finally {
      if (mounted) setState(() { _calibrating = false; if (_calStep == 3) _calStep = 0; });
    }
  }

  // AUTO MODE — применяем сохранённый профиль, предсказываем позиции якорей
  Future<void> _applyProfile(LayoutProfile profile) async {
    if (_cmpImg == null) {
      xpDlg(context, 'Нет образца', 'Загрузите образец.');
      return;
    }
    if (_refImg == null) {
      xpDlg(context, 'Нет эталона', 'Загрузите эталон.');
      return;
    }
    setState(() => _calibrating = true);
    try {
      // Decode sample image size for denormalization of predicted points
      final cmpDecoded = await compute(_decodeSize, _cmpImg!);
      final cmpW = cmpDecoded.width.toDouble();
      final cmpH = cmpDecoded.height.toDouble();

      // Предсказываем позиции на новом образце из нормализованных координат профиля
      // (простое прямое применение — нормализованные позиции те же)
      final predicted = profile.refAnchors
          .map((a) => Offset(a.x, a.y)) // остаётся нормализованным для AnchorPointScreen
          .toList();

      // Пользователь быстро корректирует предсказанные точки
      final srcPtsRaw = await Navigator.push<List<Offset>>(
        context,
        MaterialPageRoute(
          builder: (_) => AnchorPointScreen(
            imageBytes: _cmpImg!,
            title: '${profile.name} — уточните точки',
            predictedPoints: predicted,
            minPoints: profile.refAnchors.length,
            maxPoints: profile.refAnchors.length,
          ),
        ),
      );
      if (srcPtsRaw == null || !mounted) return;

      // Ref точки в пикселях из нормализованных
      final refW = profile.refImageWidth > 0 ? profile.refImageWidth.toDouble() : cmpW;
      final refH = profile.refImageHeight > 0 ? profile.refImageHeight.toDouble() : cmpH;
      final refPtsRaw = profile.refAnchors
          .map((a) => Offset(a.x * refW, a.y * refH))
          .toList();

      setState(() => _calibrating = true);
      final alignResult = await OpenCvService.alignByAnchors(
        _refImg!, _cmpImg!, refPtsRaw, srcPtsRaw,
      );
      if (!mounted) return;
      if (alignResult == null) return;

      // Показываем результат валидации
      await _showAlignmentValidation(alignResult, confirmOnly: true);
      if (!mounted) return;

      setState(() {
        _layoutProfile = profile;
        _cmpAligned = alignResult.alignedBytes;
        _refAnchorPts = refPtsRaw;
        _cmpAnchorPts = srcPtsRaw;
      });
    } finally {
      if (mounted) setState(() => _calibrating = false);
    }
  }

  // Validation dialog — возвращает true если пользователь принял результат
  Future<bool> _showAlignmentValidation(
    AlignByAnchorsResult r, {bool confirmOnly = false}
  ) async {
    final color = r.quality == 'excellent'
        ? Colors.green
        : r.quality == 'good'
            ? Colors.lightGreen
            : r.quality == 'warning'
                ? Colors.orange
                : Colors.red;

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              Icon(Icons.tune, color: color, size: 20),
              const SizedBox(width: 8),
              Text('Выравнивание: ${r.qualityLabel}',
                  style: TextStyle(fontSize: 15, color: color)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _validationRow('Ошибка репроекции',
                  '${r.reprojError.toStringAsFixed(2)} пкс',
                  r.reprojError < 3.0 ? Colors.green : Colors.orange),
              _validationRow('ECC Score',
                  '${(r.eccScore * 100).toStringAsFixed(1)}%',
                  r.eccScore > 0.9 ? Colors.green : Colors.orange),
              _validationRow('Уверенность',
                  '${(r.confidence * 100).toStringAsFixed(0)}%',
                  r.confidence > 0.85 ? Colors.green : Colors.orange),
            ]),
            actions: confirmOnly
                ? [TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK'))]
                : [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Сохранить профиль'),
                    ),
                  ],
          ),
        ) ??
        false;
  }

  Widget _validationRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ]),
      );

  static ({int width, int height}) _decodeSize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    return (width: decoded?.width ?? 0, height: decoded?.height ?? 0);
  }

  static String _anchorId(int index, int total) {
    const names4 = ['top_left', 'top_right', 'bottom_right', 'bottom_left'];
    if (total == 4 && index < 4) return names4[index];
    return 'pt_$index';
  }

  Future<String?> _promptProfileName() async {
    final ctrl = TextEditingController(
        text: 'Профиль ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название профиля'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(
                ctx, ctrl.text.trim().isEmpty ? 'Профиль' : ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _overlayCtrl.dispose();
    _cmp2Ctrl.dispose();
    _refAlignCtrl.dispose();
    _cmpAlignCtrl.dispose();
    super.dispose();
  }



  // ── Второй эталон: выбор ─────────────────────────
  Future<void> _pickRef2([ImageSource? source]) async {
    final src = source ?? await _pickSource();
    if (src == null) return;
    final x = await _picker.pickImage(source: src, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() { _ref2Img = bytes; _ref1Sharpness = null; _ref2Sharpness = null; });
    // Считаем резкость обоих снимков параллельно
    final results = await Future.wait([
      compute(_laplacianSharpness, _refImg!),
      compute(_laplacianSharpness, bytes),
    ]);
    if (mounted) setState(() { _ref1Sharpness = results[0]; _ref2Sharpness = results[1]; });
  }

  // ── Выбрать снимок: слить оба → коррекция перспективы → сохранить ──
  // ref = выбранный (лучший), src = второй; если src == null — только коррекция
  void _openFullScreen(Uint8List bytes) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _FullScreenViewer(bytes: bytes),
    ));
  }

  Future<void> _selectRef(Uint8List ref, [Uint8List? src]) async {
    setState(() { _stacking = true; });
    try {
      final fused = src != null
          ? await OpenCvService.fuseImages(ref, src)
          : ref;
      if (!mounted) return;
      final sz = await compute(_decodeSize, fused);
      if (!mounted) return;
      setState(() {
        _refImg = fused;
        _refImgSize = Size(sz.width.toDouble(), sz.height.toDouble());
        _refAligned = null;
        _layoutProfile = null;
        _refAnchorPts = null;
        _ref2Img = null;
        _ref1Sharpness = null;
        _ref2Sharpness = null;
      });
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  // ── Второй образец: выбор ────────────────────────
  Future<void> _pickCmp2([ImageSource? source]) async {
    final src = source ?? await _pickSource();
    if (src == null) return;
    final x = await _picker.pickImage(source: src, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() { _cmp2Img = bytes; _cmp2Ctrl.value = Matrix4.identity();
                  _cmp1Sharpness = null; _cmp2Sharpness = null; });
    final results = await Future.wait([
      compute(_laplacianSharpness, _cmpImg!),
      compute(_laplacianSharpness, bytes),
    ]);
    if (mounted) setState(() { _cmp1Sharpness = results[0]; _cmp2Sharpness = results[1]; });
  }

  Future<void> _selectCmp(Uint8List ref, [Uint8List? src]) async {
    setState(() => _stacking = true);
    try {
      final fused = src != null ? await OpenCvService.fuseImages(ref, src) : ref;
      if (!mounted) return;
      final sz = await compute(_decodeSize, fused);
      if (!mounted) return;
      setState(() {
        _cmpImg = fused;
        _cmpImgSize = Size(sz.width.toDouble(), sz.height.toDouble());
        _cmpAligned = null; _layoutProfile = null;
        _cmpAnchorPts = null;
        _cmp2Img = null; _cmp2Ctrl.value = Matrix4.identity();
        _cmp1Sharpness = null; _cmp2Sharpness = null;
      });
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  Future<ImageSource?> _pickSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.silver,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Text('🖼️', style: TextStyle(fontSize: 20)),
          title: const Text('Галерея'),
          onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ListTile(
          leading: const Text('📷', style: TextStyle(fontSize: 20)),
          title: const Text('Камера'),
          onTap: () => Navigator.pop(context, ImageSource.camera)),
      ]),
    );
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
      _tabs.animateTo(3);

      // Lab-пирамида — точнее MAE, обновляем результат если OpenCV доступен
      OpenCvService.compareImages(ref, cmp).then((lab) {
        if (lab != null && mounted && _result != null) {
          final r = _result!;
          setState(() => _result = CompareResult(
            similarity:    r.similarity,
            labScore:      lab.score,
            labLevel0:     lab.level0,
            labLevel1:     lab.level1,
            labLevel2:     lab.level2,
            labLevel3:     lab.level3,
            shiftDL:       lab.shiftDL,
            shiftDA:       lab.shiftDA,
            shiftDB:       lab.shiftDB,
            refCanonical:  lab.refCanonical,
            diffPixels:    r.diffPixels,
            totalPixels:   r.totalPixels,
            refSize:       r.refSize,
            cmpSize:       r.cmpSize,
            diffL3:        lab.diffL3,
          ));
        }
      }).catchError((_) {});

      // Фаза 2: штрихкоды + OCR — фоном, обновляем результат когда готово
      Future<OcrResult> ocrSafe(Uint8List b) async {
        try {
          return await OcrService.recognize(b)
              .timeout(const Duration(seconds: 15),
                  onTimeout: () => OcrResult('', [], error: 'Таймаут OCR'));
        } catch (e) {
          return OcrResult('', [], error: e.toString());
        }
      }

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

      await _saveCheckResult();
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка сравнения', e.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  // ── % совпадения штрихкодов эталон/образец ───────
  double? _barcodeMatchPct() {
    if (_refBarcodes.isEmpty && _cmpBarcodes.isEmpty) return null;
    if (_refBarcodes.isEmpty || _cmpBarcodes.isEmpty) return 0.0;
    final refVals = _refBarcodes.map((b) => b.value).toSet();
    final cmpVals = _cmpBarcodes.map((b) => b.value).toSet();
    return refVals.intersection(cmpVals).length / refVals.length * 100;
  }

  // ── Сохранить текстовые маркеры результата (без изображений) ──
  Future<void> _saveCheckResult() async {
    if (kIsWeb) return; // sqflite недоступен в браузере
    final r = _result;
    if (r == null) return;
    final score = r.score;
    final status = score >= 90 ? 'pass' : (score >= 70 ? 'warning' : 'fail');

    final details = <String, dynamic>{
      'similarity':  r.similarity,
      'labScore':    r.labScore,
      'labLevel0':   r.labLevel0,
      'labLevel1':   r.labLevel1,
      'labLevel2':   r.labLevel2,
      'labLevel3':   r.labLevel3,
      'refSize':     r.refSize,
      'cmpSize':     r.cmpSize,
      'diffPercent': r.diffPercent,
      if (_textDiff != null) 'textSimilarity': _textDiff!.similarity,
      if (_textDiff != null) 'textMissing':    _textDiff!.missing,
      if (_textDiff != null) 'textExtra':      _textDiff!.extra,
      if (_barcodeMatchPct() != null) 'barcodeMatch': _barcodeMatchPct(),
    };

    await LocalDatabase().saveCheckResult({
      'id':                   const Uuid().v4(),
      'layout_id':            null,
      'layout_profile_id':    null,
      'device_id':            null,
      'operator_id':          Supabase.instance.client.auth.currentUser?.id,
      'score':                score,
      'status':               status,
      'alignment_confidence': _layoutProfile?.alignment?.confidence,
      'reproj_error':         _layoutProfile?.alignment?.reprojectionError,
      'ecc_score':            _layoutProfile?.alignment?.eccScore,
      'color_deviation':      null,
      'shift_dl':             r.shiftDL,
      'shift_da':             r.shiftDA,
      'shift_db':             r.shiftDB,
      'heatmap_url':          null,
      'details':              jsonEncode(details),
      'created_at':           DateTime.now().toIso8601String(),
    });
  }

  // ── Кроп рамкой ──────────────────────────────────
  Future<void> _cropImage(bool isRef) async {
    final src = isRef ? _refImg : _cmpImg;
    if (src == null) return;
    final result = await CropFrameScreen.show(
      context, src,
      title: isRef ? 'Рамка — Эталон' : 'Рамка — Образец',
    );
    if (result != null && mounted) {
      setState(() {
        _layoutProfile = null;
        if (isRef) { _refImg = result; _refAligned = null; }
        else        { _cmpImg = result; _cmpAligned = null; }
      });
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
        ]),
      ),
    );
    if (result == null) return;

    final source =
        result == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final x = await _picker.pickImage(source: source, imageQuality: 92);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    if (isRef) {
      // Сбрасываем второй снимок и пропускаем через _selectRef (перспектива)
      setState(() { _ref2Img = null; _ref1Sharpness = null; _ref2Sharpness = null; });
      await _selectRef(bytes);
    } else {
      final sz = await compute(_decodeSize, bytes);
      if (!mounted) return;
      setState(() {
        _cmpImg = bytes;
        _cmpImgSize = Size(sz.width.toDouble(), sz.height.toDouble());
        _cmpAligned = null;
        _layoutProfile = null;
        _cmpAnchorPts = null;
      });
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
                    _refImg = null; _refImgSize = null;
                    _cmpImg = null; _cmpImgSize = null;
                    _refAligned = null; _cmpAligned = null;
                    _layoutProfile = null;
                    _refAnchorPts = null; _cmpAnchorPts = null;
                    _result = null; _aiResult = null;
                    _refBarcodes = []; _cmpBarcodes = [];
                    _refOcr = null; _cmpOcr = null; _textDiff = null;
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
              label: 'Образец',
              icon: '📷',
              onTap: () => _tabs.animateTo(1)),
          XpMenuItem(
              label: 'Совмещение',
              icon: '🎯',
              onTap: () => _tabs.animateTo(2)),
          XpMenuItem(
              label: 'Результат',
              icon: '📊',
              onTap: () => _tabs.animateTo(3)),
          XpMenuItem(
              label: 'История',
              icon: '📋',
              onTap: () => _tabs.animateTo(4)),
        ]),
        XpMenu(label: 'Инструменты', items: [
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
          _xpTab('📷 Образец', 1),
          _xpTab('🎯 Совмещение', 2),
          _xpTab('📊 Результат', 3),
          _xpTab('📋 История', 4),
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
            _tabAlign(),
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
        // ── Эталон 1 ─────────────────────────────────
        XpGroup(
            label: 'Эталон 1',
            child: Column(children: [
              GestureDetector(
                onTap: () => _pickImage(true),
                onDoubleTap: _refImg != null ? () => _openFullScreen(_refImg!) : null,
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
          const SizedBox(width: 6),
          XpBtn(
              label: '✂ Рамка',
              onPressed: _refImg != null ? () => _cropImage(true) : null),
        ]),

        // ── Эталон 2 ─────────────────────────────────
        const SizedBox(height: 8),
        XpCollapsible(
            title: 'Эталон 2 (Склейка кадров)',
            child: XpGroup(
            label: 'Эталон 2',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_refImg == null) ...[
                const Text('Сначала загрузите Эталон 1.',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ] else if (_ref2Img == null) ...[
                  GestureDetector(
                    onTap: () => _pickRef2(),
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      color: Colors.black,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('🖼️', style: TextStyle(fontSize: 40)),
                          SizedBox(height: 8),
                          Text('Нажмите для выбора второго снимка',
                              style: TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Оверлей: эталон 1 (фон) + эталон 2 (двигается вручную)
                  ClipRect(
                    child: Container(
                      height: 260,
                      color: Colors.black,
                      child: LayoutBuilder(builder: (_, c) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _overlayViewerSize = Size(c.maxWidth, c.maxHeight);
                        });
                        return Stack(fit: StackFit.expand, children: [
                          RepaintBoundary(
                            child: Stack(fit: StackFit.expand, children: [
                              Image.memory(_refImg!, fit: BoxFit.contain),
                              Opacity(
                                opacity: _overlayOpacity,
                                child: InteractiveViewer(
                                  transformationController: _overlayCtrl,
                                  boundaryMargin:
                                      const EdgeInsets.all(double.infinity),
                                  minScale: 0.1, maxScale: 6.0,
                                  child: Image.memory(_ref2Img!,
                                      fit: BoxFit.contain),
                                ),
                              ),
                            ]),
                          ),
                          const IgnorePointer(
                            child: CustomPaint(painter: _FramePainter(0.12)),
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
                  // Резкость как справочная информация
                  if (_ref1Sharpness != null && _ref2Sharpness != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Expanded(child: Text(
                          'Резкость 1: ${_ref1Sharpness!.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: _ref1Sharpness! >= _ref2Sharpness!
                                ? AppTheme.simHigh : Colors.grey),
                        )),
                        Expanded(child: Text(
                          'Резкость 2: ${_ref2Sharpness!.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 10,
                            color: _ref2Sharpness! > _ref1Sharpness!
                                ? AppTheme.simHigh : Colors.grey),
                        )),
                      ]),
                    ),
                  Row(children: [
                    const SizedBox(width: 90,
                        child: Text('Прозрачность:',
                            style: TextStyle(fontSize: 11))),
                    Expanded(child: Slider(
                      value: _overlayOpacity,
                      onChanged: (v) =>
                          setState(() => _overlayOpacity = v),
                      activeColor: AppTheme.blue,
                    )),
                    SizedBox(width: 36, child: Text('${(_overlayOpacity * 100).round()}%',
                        style: const TextStyle(fontSize: 10))),
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
                        label: _stacking ? '⏳ Обработка...' : '🔀 Склейка кадров',
                        primary: true,
                        onPressed: _stacking
                            ? null
                            : () => _selectRef(_refImg!, _ref2Img)),
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
              ]))),

        const SizedBox(height: 12),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          XpBtn(label: 'Далее ›', primary: true, onPressed: () => _tabs.animateTo(1)),
        ]),
      ]),
    );
  }

  // ── Таб: Образец ─────────────────────────────────
  Widget _tabCmp() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [

        // ── Образец 1 ────────────────────────────────
        XpGroup(
            label: 'Образец 1',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GestureDetector(
                onTap: () => _pickImage(false),
                onDoubleTap: _cmpImg != null ? () => _openFullScreen(_cmpImg!) : null,
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

              // Образец 2 — для объединения
              if (_cmpImg != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  XpBtn(label: '✂ Рамка', onPressed: () => _cropImage(false)),
                ]),
                const SizedBox(height: 4),
                const Divider(),
                const SizedBox(height: 6),
                XpCollapsible(
                  title: 'Образец 2 (Склейка кадров)',
                  child: _cmp2Img == null
                      ? GestureDetector(
                          onTap: () => _pickCmp2(),
                          child: Container(
                            height: 120,
                            width: double.infinity,
                            color: Colors.black,
                            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('📷', style: TextStyle(fontSize: 30)),
                              SizedBox(height: 6),
                              Text('Нажмите для второго снимка', style: TextStyle(fontSize: 11, color: Colors.white54)),
                            ]),
                          ),
                        )
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          ClipRect(
                            child: Container(
                              height: 260,
                              color: Colors.black,
                              child: Stack(fit: StackFit.expand, children: [
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
                                const IgnorePointer(
                                  child: CustomPaint(painter: _FramePainter(0.12)),
                                ),
                                const Positioned(left: 8, top: 8, child: _ImgLabel('Образец 1')),
                                const Positioned(right: 8, top: 8, child: _ImgLabel('Образец 2 ↕↔')),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_cmp1Sharpness != null && _cmp2Sharpness != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(children: [
                                Expanded(child: Text(
                                  'Резкость 1: ${_cmp1Sharpness!.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 10,
                                    color: _cmp1Sharpness! >= _cmp2Sharpness!
                                        ? AppTheme.simHigh : Colors.grey),
                                )),
                                Expanded(child: Text(
                                  'Резкость 2: ${_cmp2Sharpness!.toStringAsFixed(0)}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 10,
                                    color: _cmp2Sharpness! > _cmp1Sharpness!
                                        ? AppTheme.simHigh : Colors.grey),
                                )),
                              ]),
                            ),
                          Row(children: [
                            const SizedBox(width: 90,
                                child: Text('Прозрачность:', style: TextStyle(fontSize: 11))),
                            Expanded(child: Slider(
                              value: _cmp2Opacity,
                              onChanged: (v) => setState(() => _cmp2Opacity = v),
                              activeColor: AppTheme.blue,
                            )),
                            SizedBox(width: 36, child: Text('${(_cmp2Opacity * 100).round()}%',
                                style: const TextStyle(fontSize: 10))),
                          ]),
                          Row(children: [
                            XpBtn(label: '🗑 Убрать', danger: true,
                                onPressed: () => setState(() {
                                  _cmp2Img = null; _cmp2Ctrl.value = Matrix4.identity();
                                  _cmp1Sharpness = null; _cmp2Sharpness = null;
                                })),
                            const Spacer(),
                            XpBtn(
                                label: _stacking ? '⏳ Обработка...' : '🔀 Склейка кадров',
                                primary: true,
                                onPressed: _stacking
                                    ? null
                                    : () => _selectCmp(_cmpImg!, _cmp2Img)),
                          ]),
                        ]),
                ),
              ],
            ])),

        const SizedBox(height: 12),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          XpBtn(label: '‹ Эталон', onPressed: () => _tabs.animateTo(0)),
          XpBtn(
              label: 'Далее ›',
              primary: true,
              onPressed: _refImg != null && _cmpImg != null
                  ? () => _tabs.animateTo(2)
                  : null),
        ]),
      ]),
    );
  }

  // ── Таб: Совмещение ───────────────────────────────
  Widget _tabAlign() {
    if (_refImg == null || _cmpImg == null) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🎯', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text('Сначала загрузите эталон и образец',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            XpBtn(label: '‹ Образец', onPressed: () => _tabs.animateTo(1)),
          ]));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        // ── Два окна предпросмотра ─────────────────────
        LayoutBuilder(builder: (_, constraints) {
          final wide = constraints.maxWidth > 480;
          final panels = [
            _alignPanel(
              label: 'Эталон',
              bytes: _refImg!,
              imgSize: _refImgSize,
              anchorPts: _refAnchorPts,
              ctrl: _refAlignCtrl,
              availableWidth: wide ? (constraints.maxWidth - 8) / 2 : constraints.maxWidth,
              placing: _calStep == 1,
              tempPts: _tempRefPts,
              onTap: _calStep == 1 ? _addPanelPoint : null,
            ),
            _alignPanel(
              label: 'Образец',
              bytes: _cmpAligned ?? _cmpImg!,
              imgSize: _cmpImgSize,
              anchorPts: _cmpAnchorPts,
              ctrl: _cmpAlignCtrl,
              availableWidth: wide ? (constraints.maxWidth - 8) / 2 : constraints.maxWidth,
              placing: _calStep == 2,
              tempPts: _tempCmpPts,
              onTap: _calStep == 2 ? _addPanelPoint : null,
            ),
          ];
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panels[0]),
                const SizedBox(width: 8),
                Expanded(child: panels[1]),
              ],
            );
          }
          return Column(children: [panels[0], const SizedBox(height: 8), panels[1]]);
        }),

        const SizedBox(height: 12),
        // ── Инструкция / Статус профиля ───────────────
        if (_calStep == 0 && _layoutProfile != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.tune, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              Expanded(child: Text(
                'Профиль: ${_layoutProfile!.name}  ·  ош. ${_layoutProfile!.reprojError.toStringAsFixed(1)} пкс',
                style: const TextStyle(fontSize: 11, color: Colors.green),
                overflow: TextOverflow.ellipsis,
              )),
              TextButton(
                onPressed: () => setState(() {
                  _layoutProfile = null; _cmpAligned = null;
                  _refAnchorPts = null; _cmpAnchorPts = null;
                }),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('✕', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ]),
          )
        else if (_calStep == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Нажмите «🔧 Калибровка» и расставьте точки на эталоне и образце.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                )),
              ]),
            ),
          )
        else if (_calStep == 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.10),
                border: Border.all(color: Colors.blue),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.touch_app, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Шаг 1 / 2 — ЭТАЛОН: нажмите $_minAnchorPts–$_maxAnchorPts точек  (${_tempRefPts.length} из $_minAnchorPts мин.)',
                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                )),
              ]),
            ),
          )
        else if (_calStep == 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.10),
                border: Border.all(color: Colors.teal),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(children: [
                const Icon(Icons.touch_app, size: 16, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Шаг 2 / 2 — ОБРАЗЕЦ: те же ${_tempRefPts.length} точек в том же порядке  (${_tempCmpPts.length} / ${_tempRefPts.length})',
                  style: const TextStyle(fontSize: 11, color: Colors.teal),
                )),
              ]),
            ),
          )
        else if (_calStep == 3)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Расчёт совмещения...', style: TextStyle(fontSize: 12)),
            ]),
          ),
        const Divider(),
        if (_calStep == 0)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            XpBtn(label: '‹ Образец', onPressed: () => _tabs.animateTo(1)),
            Row(children: [
              XpBtn(
                label: '🔧 Калибровка',
                primary: _layoutProfile == null,
                onPressed: _startCalibration,
              ),
              const SizedBox(width: 8),
              if (_result != null) ...[
                SimBadge(value: _result!.score),
                const SizedBox(width: 8),
              ],
              _comparing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : XpBtn(
                      label: 'Сравнить ›',
                      primary: true,
                      onPressed: _refImg != null && _cmpImg != null && _layoutProfile != null
                          ? _runCompare : null),
            ]),
          ])
        else if (_calStep == 1)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            XpBtn(label: 'Отмена', danger: true, onPressed: _cancelCalibration),
            Row(children: [
              XpBtn(
                label: '⌫ Удалить',
                onPressed: _tempRefPts.isNotEmpty ? _undoLastPoint : null,
              ),
              const SizedBox(width: 8),
              XpBtn(
                label: 'Далее ›',
                primary: true,
                onPressed: _tempRefPts.length >= _minAnchorPts ? _advanceToStep2 : null,
              ),
            ]),
          ])
        else if (_calStep == 2)
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            XpBtn(label: '← Назад', onPressed: () => setState(() { _calStep = 1; _tempCmpPts = []; })),
            Row(children: [
              XpBtn(
                label: '⌫ Удалить',
                onPressed: _tempCmpPts.isNotEmpty ? _undoLastPoint : null,
              ),
              const SizedBox(width: 8),
              XpBtn(
                label: 'Рассчитать →',
                primary: true,
                onPressed: _tempCmpPts.length == _tempRefPts.length && _tempRefPts.isNotEmpty
                    ? _runAlignmentFromPoints : null,
              ),
            ]),
          ])
        else
          const SizedBox.shrink(),
      ]),
    );
  }

  // Панель предпросмотра с зумом и якорными точками
  Widget _alignPanel({
    required String label,
    required Uint8List bytes,
    required Size? imgSize,
    required List<Offset>? anchorPts,
    required TransformationController ctrl,
    required double availableWidth,
    bool placing = false,
    List<Offset> tempPts = const [],
    void Function(Offset)? onTap,
  }) {
    // Вычисляем высоту контейнера по аспекту изображения (без чёрных полос)
    double panelHeight = 220;
    if (imgSize != null && imgSize.width > 0 && imgSize.height > 0) {
      panelHeight = (availableWidth * imgSize.height / imgSize.width).clamp(120.0, 340.0);
    }

    void zoom(double factor) {
      final m = ctrl.value.clone();
      m.scale(factor, factor);
      final s = m.getMaxScaleOnAxis();
      if (s < 0.2 || s > 8.0) return;
      ctrl.value = m;
    }

    List<Widget> buildDots(List<Offset> pts, Color color) {
      if (imgSize == null) return [];
      final ratio = min(availableWidth / imgSize.width, panelHeight / imgSize.height);
      final offX = (availableWidth - imgSize.width * ratio) / 2;
      final offY = (panelHeight - imgSize.height * ratio) / 2;
      return pts.asMap().entries.map((e) {
        final px = e.value.dx * ratio + offX;
        final py = e.value.dy * ratio + offY;
        return Positioned(
          left: px - 10, top: py - 10,
          child: _AnchorDot(index: e.key + 1, color: color),
        );
      }).toList();
    }

    final stackContent = Stack(children: [
      Image.memory(bytes, width: availableWidth, height: panelHeight, fit: BoxFit.contain),
      ...buildDots(anchorPts ?? [], Colors.red),
      ...buildDots(tempPts, Colors.amber),
      if (placing)
        Positioned.fill(child: IgnorePointer(
          child: Container(decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
          )),
        )),
    ]);

    final viewerChild = onTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              if (imgSize == null) return;
              final local = d.localPosition;
              final ratio = min(availableWidth / imgSize.width, panelHeight / imgSize.height);
              final offX = (availableWidth - imgSize.width * ratio) / 2;
              final offY = (panelHeight - imgSize.height * ratio) / 2;
              final imgX = (local.dx - offX) / ratio;
              final imgY = (local.dy - offY) / ratio;
              if (imgX >= 0 && imgY >= 0 &&
                  imgX <= imgSize.width && imgY <= imgSize.height) {
                onTap(Offset(imgX, imgY));
              }
            },
            child: stackContent,
          )
        : stackContent;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Заголовок панели
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: placing ? const Color(0xFF0055BB) : AppTheme.blue,
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      // Область изображения
      ClipRect(
        child: SizedBox(
          height: panelHeight,
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                zoom(e.scrollDelta.dy < 0 ? 1.15 : 0.87);
              }
            },
            child: InteractiveViewer(
              transformationController: ctrl,
              boundaryMargin: const EdgeInsets.all(80),
              minScale: 0.2,
              maxScale: 8.0,
              child: viewerChild,
            ),
          ),
        ),
      ),
      // Кнопки зума
      Container(
        color: AppTheme.silver,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(children: [
          _ZoomBtn(label: '−', onTap: () => zoom(0.77)),
          const SizedBox(width: 4),
          _ZoomBtn(label: '+', onTap: () => zoom(1.3)),
          const SizedBox(width: 6),
          _ZoomBtn(label: '⊡', onTap: () => ctrl.value = Matrix4.identity()),
        ]),
      ),
    ]);
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
                'Загрузите оба фото, расставьте точки (🔧 Калибровка)\n'
                'и нажмите «Сравнить ›» на вкладке Совмещение',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            XpBtn(
                label: '‹ К совмещению',
                onPressed: () => _tabs.animateTo(2)),
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
        Center(child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            r.labScore != null
                ? 'Lab: ${r.labScore!.toStringAsFixed(1)}%  ·  MAE: ${r.similarity.toStringAsFixed(1)}%'
                : 'MAE: ${r.similarity.toStringAsFixed(1)}%',
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
        // ── Наложение: эталон + образец с ползунком ──
        if (_refImg != null && _cmpImg != null)
          XpGroup(
              label: 'Наложение',
              child: Column(children: [
                Container(
                  height: 220,
                  color: Colors.black,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.memory(_refAligned ?? _refImg!, fit: BoxFit.contain),
                    Opacity(
                      opacity: _resultOpacity,
                      child: Image.memory(_cmpAligned ?? _cmpImg!, fit: BoxFit.contain),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Text('Эталон', style: TextStyle(fontSize: 10)),
                  Expanded(child: Slider(
                    value: _resultOpacity,
                    onChanged: (v) => setState(() => _resultOpacity = v),
                    activeColor: AppTheme.blue,
                  )),
                  const Text('Образец', style: TextStyle(fontSize: 10)),
                ]),
              ])),

        // ── Анализ цвета (уровень 0 — глобальный) ──
        if (r.shiftDL != null || r.shiftDA != null)
          XpGroup(
              label: 'Цветовой анализ',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_colorComment(r.shiftDL, r.shiftDA, r.shiftDB),
                    style: const TextStyle(fontSize: 12, height: 1.5)),
              ])),

        // ── Карта различий (уровень 3: 27×27 детали) ──
        if (r.diffL3 != null)
          XpGroup(
              label: 'Карта различий',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _legendItem(const Color(0xFF1EC81E), 'ΔE < 3'),
                  const SizedBox(width: 10),
                  _legendItem(const Color(0xFFE8A000), 'ΔE 3–6'),
                  const SizedBox(width: 10),
                  _legendItem(const Color(0xFFDC1414), 'ΔE > 6'),
                  const Spacer(),
                  XpBtn(
                    label: _showDiffL3 ? 'Скрыть' : '🔍 Показать',
                    onPressed: () => setState(() => _showDiffL3 = !_showDiffL3),
                  ),
                ]),
                if (_showDiffL3) ...[
                  const SizedBox(height: 8),
                  _diffOverlay(r.diffL3!, r.refCanonical),
                ],
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
                  onPressed: () => _tabs.animateTo(2)),
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
                        _layoutProfile = null;
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
              onTap: () => _tabs.animateTo(3),
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
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ]);

  // Карта ΔE поверх канонического ref — оба одного размера, наложение точное.
  Widget _diffOverlay(Uint8List diffPng, Uint8List? canonRef) => Container(
        height: 220,
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          if (canonRef != null)
            Image.memory(canonRef, fit: BoxFit.contain)
          else if (_refImg != null)
            Image.memory(_refImg!, fit: BoxFit.contain),
          Image.memory(diffPng, fit: BoxFit.contain),
        ]),
      );

  // Текстовый комментарий о цветовом сдвиге образца относительно эталона.
  // da > 0 → образец краснее; da < 0 → зеленее
  // db > 0 → образец желтее;  db < 0 → синее
  // dL > 0 → образец темнее;  dL < 0 → светлее
  String _colorComment(double? dL, double? da, double? db) {
    if (dL == null && da == null && db == null) return 'Нет данных';
    final parts = <String>[];
    final thresh = 3.0; // порог значимости в единицах OpenCV Lab
    if (dL != null && dL.abs() > 2.0) {
      parts.add(dL > 0 ? 'образец темнее на ${dL.abs().toStringAsFixed(1)} L*'
                       : 'образец светлее на ${dL.abs().toStringAsFixed(1)} L*');
    }
    if (da != null && da.abs() > thresh) {
      parts.add(da > 0 ? 'смещение в красный (+${da.toStringAsFixed(1)} a*)'
                       : 'смещение в зелёный (${da.toStringAsFixed(1)} a*)');
    }
    if (db != null && db.abs() > thresh) {
      parts.add(db > 0 ? 'смещение в жёлтый (+${db.toStringAsFixed(1)} b*)'
                       : 'смещение в синий (${db.toStringAsFixed(1)} b*)');
    }
    if (parts.isEmpty) return 'Общий тон в норме (глобальный сдвиг < порога)';
    return parts.join(' · ');
  }

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

// Резкость по дисперсии Лапласиана (выше = резче)
double _laplacianSharpness(Uint8List bytes) {
  final src = img.decodeImage(bytes);
  if (src == null) return 0;
  final small = img.copyResize(img.grayscale(src), width: 512);
  final w = small.width, h = small.height;
  double sum = 0, sumSq = 0;
  int n = 0;
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final v = small.getPixel(x, y).r.toInt() * 4 -
          small.getPixel(x - 1, y).r.toInt() -
          small.getPixel(x + 1, y).r.toInt() -
          small.getPixel(x, y - 1).r.toInt() -
          small.getPixel(x, y + 1).r.toInt();
      sum += v; sumSq += v * v; n++;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean; // дисперсия
}

// Полноэкранный просмотр с зумом
class _FullScreenViewer extends StatelessWidget {
  final Uint8List bytes;
  const _FullScreenViewer({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 12.0,
        child: Center(child: Image.memory(bytes)),
      ),
    );
  }
}

// Карточка выбора снимка с показателем резкости
class _SharpnessCard extends StatelessWidget {
  final Uint8List bytes;
  final String label;
  final double? sharpness;
  final double? other;       // резкость второго снимка для сравнения
  final VoidCallback onSelect;

  const _SharpnessCard({
    required this.bytes, required this.label,
    required this.sharpness, required this.other,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isBetter = sharpness != null && other != null && sharpness! >= other!;
    final loading  = sharpness == null;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isBetter ? AppTheme.simHigh : AppTheme.silver,
            width: isBetter ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Stack(children: [
            Image.memory(bytes, height: 140, fit: BoxFit.cover,
                width: double.infinity),
            if (isBetter)
              const Positioned(top: 6, right: 6,
                child: _ImgLabel('✓ Резче')),
          ]),
          Container(
            color: AppTheme.silver,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              if (loading)
                const Text('Анализ...', style: TextStyle(fontSize: 10, color: Colors.grey))
              else ...[
                Text('Резкость: ${sharpness!.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 10)),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onSelect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBetter ? AppTheme.simHigh : AppTheme.blue,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Выбрать', style: TextStyle(
                      fontSize: 11, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Рамка: затемняет края (cropMargin с каждой стороны), центр прозрачный
class _FramePainter extends CustomPainter {
  final double margin;
  const _FramePainter(this.margin);

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = const Color(0xAA000000);
    final ml = size.width  * margin;
    final mt = size.height * margin;
    final mr = size.width  - ml;
    final mb = size.height - mt;

    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, mt), shadow);
    canvas.drawRect(Rect.fromLTRB(0, mb, size.width, size.height), shadow);
    canvas.drawRect(Rect.fromLTRB(0, mt, ml, mb), shadow);
    canvas.drawRect(Rect.fromLTRB(mr, mt, size.width, mb), shadow);

    // Белые уголки
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final arm = size.width * 0.06;

    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * arm, y), line);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * arm), line);
    }
    corner(ml, mt,  1,  1);
    corner(mr, mt, -1,  1);
    corner(ml, mb,  1, -1);
    corner(mr, mb, -1, -1);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.margin != margin;
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

class _AnchorDot extends StatelessWidget {
  final int index;
  final Color color;
  const _AnchorDot({required this.index, this.color = Colors.red});
  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text('$index',
            style: const TextStyle(
                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
      );
}

class _ZoomBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ZoomBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      );
}

class _BarcodeIssue {
  final bool isError;
  final String title;
  final String detail;
  const _BarcodeIssue.error(this.title, this.detail) : isError = true;
  const _BarcodeIssue.warning(this.title, this.detail) : isError = false;
}

