import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';
import '../services/compare_service.dart';
import '../services/reference_storage.dart';
import '../services/opencv_service.dart';
import '../services/ai_compare_service.dart';
import '../services/barcode_service.dart';
import '../services/anchor_refinement_service.dart';
import '../services/calibration_settings_service.dart';
import '../services/lab_fingerprint_service.dart';
import '../services/ocr_service.dart';
import '../services/check_history_service.dart';
import '../config/app_config.dart';
import '../widgets/crop_frame_screen.dart';
import '../widgets/anchor_point_screen.dart';
import '../models/layout_profile.dart';
import '../services/layout_profile_storage.dart';

enum _ResultMapMode { deltaE, geometry, overlay }

enum _InspectionTool { point, loupe }

({double l, double a, double b}) _rgbPixelToLab(img.Pixel p) {
  final r = _pivotRgbValue(p.r);
  final g = _pivotRgbValue(p.g);
  final b = _pivotRgbValue(p.b);
  final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  final y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
  final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
  final fx = _pivotXyzValue(x);
  final fy = _pivotXyzValue(y);
  final fz = _pivotXyzValue(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _pivotRgbValue(num v) {
  final c = v / 255.0;
  return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) as double;
}

double _pivotXyzValue(double v) {
  return v > 0.008856 ? pow(v, 1 / 3) as double : (7.787 * v) + 16 / 116;
}

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
  bool _comparing = false;
  String? _compareStatus;
  final List<String> _compareSteps = [];
  bool _aiLoading = false;
  CompareResult? _result;
  AiAnalysis? _aiResult;
  List<BarcodeResult> _refBarcodes = [];
  List<BarcodeResult> _cmpBarcodes = [];
  OcrResult? _refOcr;
  OcrResult? _cmpOcr;
  TextDiff? _textDiff;
  LabFingerprint? _refLabFingerprint;
  LabFingerprint? _cmpLabFingerprint;
  double? _labFingerprintMatch;

  Uint8List? _refAligned;
  Uint8List? _cmpAligned;
  Uint8List? _ref2Img; // второй снимок эталона для выбора
  double? _ref1Sharpness; // резкость эталона 1
  double? _ref2Sharpness; // резкость эталона 2
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
  final _workspaceScrollCtrl = ScrollController();

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
  bool _anchorRefining = false;
  static const int _minAnchorPts = 4;
  static const int _maxAnchorPts = 8;

  // Отступ рамки (10% с каждой стороны = 80% центральная зона)
  static const double _framePad = 0.10;

  bool _stacking = false;
  bool _imageBusy = false;
  String _imageBusyLabel = 'Обработка изображения...';
  double _diffSlider = 0.5;
  _ResultMapMode _resultMapMode = _ResultMapMode.deltaE;
  _InspectionTool _inspectionTool = _InspectionTool.point;
  final _resultCmpCtrl = TransformationController();
  _PointProbe? _pointProbe;
  _AreaLoupe? _areaLoupe;
  Offset? _loupeDragStart;
  Rect? _loupeDraftRect;
  Size? _loupeImageSize;

  String? _savedRefLabel;
  String? _activeReferenceId;
  List<SavedReferenceProfile> _savedReferences = [];
  final _jobNumberCtrl = TextEditingController();
  String _jobNumber = '';
  int _sampleNo = 1;

  static const int _uiImageCacheWidth = 1600;

  Widget _uiImage(
    Uint8List bytes, {
    BoxFit fit = BoxFit.contain,
    double? width,
    double? height,
  }) {
    return Image.memory(
      bytes,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: _uiImageCacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
  }

  Future<Size> _readImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      return size;
    } catch (_) {
      final decoded = await compute(_decodeSize, bytes);
      return Size(decoded.width.toDouble(), decoded.height.toDouble());
    }
  }

  // ── Калибровка / Layout Profile ──────────────────
  LayoutProfile? _layoutProfile;
  bool _calibrating = false;
  List<LayoutProfile> _savedProfiles = [];
  CalibrationPointSettings _calibrationSettings =
      CalibrationPointSettings.defaults;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadSavedReference();
    _loadProfiles();
    _loadCalibrationSettings();
    CalibrationSettingsService.notifier.addListener(_onCalibrationSettings);
    HardwareKeyboard.instance.addHandler(_handleCtrlKey);
  }

  Future<void> _loadCalibrationSettings() async {
    final settings = await CalibrationSettingsService.load();
    if (mounted) setState(() => _calibrationSettings = settings);
  }

  void _onCalibrationSettings() {
    if (!mounted) return;
    setState(() {
      _calibrationSettings = CalibrationSettingsService.notifier.value;
    });
  }

  Future<void> _loadProfiles() async {
    final profiles = await LayoutProfileStorage.loadAll();
    if (mounted) setState(() => _savedProfiles = profiles);
  }

  Future<void> _loadSavedReference() async {
    final refs = await ReferenceStorage.loadProfiles();
    final active = await ReferenceStorage.loadActiveProfile();
    if (!mounted) return;
    setState(() => _savedReferences = refs);
    if (active != null) {
      await _activateSavedReference(active, showMessage: false);
    }
  }

  Future<void> _refreshSavedReferences() async {
    final refs = await ReferenceStorage.loadProfiles();
    if (mounted) setState(() => _savedReferences = refs);
  }

  Future<void> _activateSavedReference(
    SavedReferenceProfile item, {
    bool showMessage = true,
  }) async {
    await ReferenceStorage.setActive(item.id);
    final size = await _readImageSize(item.bytes);
    if (!mounted) return;
    final profile = item.layoutProfile;
    final anchors = profile == null
        ? null
        : profile.refAnchors
            .map((a) => Offset(a.x * size.width, a.y * size.height))
            .toList();
    setState(() {
      _refImg = item.bytes;
      _refImgSize = size;
      _savedRefLabel = item.label;
      _activeReferenceId = item.id;
      _layoutProfile = profile;
      _refAnchorPts = anchors;
      _cmpAligned = null;
      _refAligned = null;
      _cmpAnchorPts = null;
      _result = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareStatus = null;
      _sampleNo = _nextSampleNumberFor(
        referenceId: item.id,
        referenceLabel: item.label,
      );
    });
    if (showMessage) {
      xpDlg(
        context,
        'Эталон выбран',
        profile == null
            ? '${item.label}\nТочки ещё не сохранены.'
            : '${item.label}\nТочек: ${profile.refAnchors.length}',
      );
    }
  }

  Future<void> _saveReference() async {
    if (_refImg == null) return;
    final now = DateTime.now();
    final label =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final item = await ReferenceStorage.saveProfile(
      bytes: _refImg!,
      label: label,
      layoutProfile: _layoutProfile,
    );
    await _refreshSavedReferences();
    if (mounted) {
      setState(() {
        _savedRefLabel = item.label;
        _activeReferenceId = item.id;
      });
      xpDlg(
        context,
        'Эталон сохранён',
        'Будет загружаться автоматически при следующем запуске.',
      );
    }
  }

  void _newSample() {
    setState(() {
      _sampleNo = _nextSampleNumberFor(
        referenceId: _activeReferenceId,
        referenceLabel: _savedRefLabel,
        minValue: _sampleNo + 1,
      );
      _cmpImg = null;
      _cmpImgSize = null;
      _cmpAligned = null;
      _cmpAnchorPts = null;
      _cmp2Img = null;
      _cmp1Sharpness = null;
      _cmp2Sharpness = null;
      _result = null;
      _aiResult = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareStatus = null;
      _compareSteps.clear();
      _calStep = 0;
      _tempCmpPts = [];
    });
  }

  Future<void> _clearReference() async {
    final ok = await xpConfirm(
      context,
      'Сбросить эталон',
      'Удалить сохранённый эталон с устройства?',
    );
    if (!ok) return;
    await ReferenceStorage.clear();
    if (mounted)
      setState(() {
        _savedReferences = [];
        _activeReferenceId = null;
        _refImg = null;
        _refImgSize = null;
        _savedRefLabel = null;
        _refAligned = null;
        _layoutProfile = null;
        _cmpAligned = null;
        _refAnchorPts = null;
        _cmpAnchorPts = null;
      });
  }

  // ── Калибровка: пошаговая расстановка точек прямо на панелях ───────────
  Future<void> _startCalibration() async {
    if (_refImg == null || _cmpImg == null) return;
    Size? refSize = _refImgSize;
    Size? cmpSize = _cmpImgSize;
    if (refSize == null) {
      refSize = await _readImageSize(_refImg!);
    }
    if (cmpSize == null) {
      cmpSize = await _readImageSize(_cmpImg!);
    }
    final storedRefPts = _layoutProfile == null
        ? null
        : _layoutProfile!.refAnchors
            .map((a) => Offset(a.x * refSize!.width, a.y * refSize.height))
            .toList();
    if (!mounted) return;
    setState(() {
      _calStep =
          storedRefPts == null || storedRefPts.length < _minAnchorPts ? 1 : 2;
      _tempRefPts = storedRefPts ?? [];
      _tempCmpPts = [];
      _refImgSize = refSize;
      _cmpImgSize = cmpSize;
      _cmpAligned = null;
      _cmpAnchorPts = null;
      _result = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareStatus = null;
      _compareSteps.clear();
      _refAlignCtrl.value = Matrix4.identity();
      _cmpAlignCtrl.value = Matrix4.identity();
      if (storedRefPts != null) _refAnchorPts = storedRefPts;
    });
  }

  void _cancelCalibration() {
    setState(() {
      _calStep = 0;
      _tempRefPts = [];
      _tempCmpPts = [];
    });
  }

  Future<void> _addPanelPoint(Offset imgCoord) async {
    if (_anchorRefining) return;
    final step = _calStep;
    if (step == 1 && _tempRefPts.length >= _maxAnchorPts) return;
    if (step == 2 && _tempCmpPts.length >= _maxAnchorPts) return;
    final bytes = step == 1
        ? _refImg
        : step == 2
            ? _cmpImg
            : null;
    if (bytes == null) return;

    final imageSize = step == 1 ? _refImgSize : _cmpImgSize;
    final resolvedSize = imageSize ?? await _readImageSize(bytes);
    if (!mounted || _calStep != step) return;
    final precise = _calibrationSettings.loupeEnabled
        ? await _showAnchorLoupe(
            bytes: bytes,
            imageSize: resolvedSize,
            roughPoint: imgCoord,
            pointIndex:
                step == 1 ? _tempRefPts.length + 1 : _tempCmpPts.length + 1,
            title: step == 1 ? 'Точка на эталоне' : 'Точка на образце',
            defaultZoom: _calibrationSettings.loupeZoom,
          )
        : imgCoord;
    if (precise == null || !mounted || _calStep != step) return;

    setState(() => _anchorRefining = true);
    final refined = await AnchorRefinementService.refine(
      bytes,
      precise,
      maxShift: _calibrationSettings.magnetMaxShiftPx,
    );
    if (!mounted) return;
    setState(() {
      _anchorRefining = false;
      if (_calStep != step) return;
      if (step == 1 && _tempRefPts.length < _maxAnchorPts) {
        _tempRefPts = [..._tempRefPts, refined];
      } else if (step == 2 && _tempCmpPts.length < _maxAnchorPts) {
        _tempCmpPts = [..._tempCmpPts, refined];
      }
    });
  }

  Future<Offset?> _showAnchorLoupe({
    required Uint8List bytes,
    required Size imageSize,
    required Offset roughPoint,
    required int pointIndex,
    required String title,
    required double defaultZoom,
  }) {
    return showDialog<Offset>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AnchorLoupeDialog(
        bytes: bytes,
        imageSize: imageSize,
        roughPoint: roughPoint,
        pointIndex: pointIndex,
        title: title,
        defaultZoom: defaultZoom,
      ),
    );
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

  // Шаг 1 → сохраняем эталон с точками → 2 (переключаем на образец)
  Future<void> _advanceToStep2() async {
    if (_tempRefPts.length < _minAnchorPts) return;
    final saved = await _saveReferenceAnchorsFromPoints(_tempRefPts);
    if (!saved || !mounted) return;
    setState(() {
      _calStep = 2;
      _tempCmpPts = [];
      _cmpAligned = null;
      _cmpAnchorPts = null;
      _result = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareStatus = null;
      _compareSteps.clear();
    });
  }

  Future<bool> _saveReferenceAnchorsFromPoints(List<Offset> refPts) async {
    if (_refImg == null || refPts.length < _minAnchorPts) return false;
    final refSize = _refImgSize ?? await _readImageSize(_refImg!);
    if (!mounted) return false;
    final name = _savedRefLabel ?? await _promptProfileName();
    if (name == null || !mounted) return false;
    final refW = refSize.width;
    final refH = refSize.height;
    final refAnchors = refPts
        .asMap()
        .entries
        .map(
          (e) => AnchorPoint(
            id: _anchorId(e.key, refPts.length),
            x: e.value.dx / refW,
            y: e.value.dy / refH,
            type: 'corner',
            confidence: 1.0,
          ),
        )
        .toList();
    final profile = LayoutProfile(
      id: _activeReferenceId ??
          _layoutProfile?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      refAnchors: refAnchors,
      homography: const [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
      cropRegion: CropRegion.defaultCrop,
      widthMm: AppConfig.printWidthMm,
      heightMm: AppConfig.printHeightMm,
      refImageWidth: refSize.width.round(),
      refImageHeight: refSize.height.round(),
      alignment: null,
      createdAt: _layoutProfile?.createdAt ?? DateTime.now(),
    );
    await LayoutProfileStorage.save(profile);
    await _loadProfiles();
    if (!mounted) return false;
    setState(() {
      _layoutProfile = profile;
      _savedRefLabel = name;
      _activeReferenceId = profile.id;
      _refAnchorPts = List<Offset>.from(refPts);
      _refImgSize = refSize;
    });
    return true;
  }

  // Шаг 2 → расчёт
  Future<void> _runAlignmentFromPoints({bool runCompareAfter = false}) async {
    if (_tempCmpPts.length != _tempRefPts.length) return;
    final refPts = List<Offset>.from(_tempRefPts);
    final cmpPts = List<Offset>.from(_tempCmpPts);
    var shouldRunCompare = false;
    setState(() {
      _calStep = 3;
      _calibrating = true;
    });
    try {
      final alignResult = await OpenCvService.alignByAnchors(
        _refImg!,
        _cmpImg!,
        refPts,
        cmpPts,
      );
      if (!mounted) return;
      if (alignResult == null) {
        xpDlg(
          context,
          'Ошибка',
          'Не удалось рассчитать совмещение. Попробуйте расставить точки точнее.',
        );
        setState(() {
          _calStep = 1;
          _tempRefPts = [];
          _tempCmpPts = [];
        });
        return;
      }

      final canUseAlignment = alignResult.isAcceptable;
      final ok = await _showAlignmentValidation(
        alignResult,
        canAccept: canUseAlignment,
      );
      if (!mounted) return;
      if (!canUseAlignment) {
        setState(() {
          _calStep = 2;
          _tempCmpPts = [];
        });
        return;
      }
      if (!ok || !mounted) {
        setState(() {
          _calStep = 0;
          _tempRefPts = [];
          _tempCmpPts = [];
        });
        return;
      }

      final name = _savedRefLabel ?? await _promptProfileName();
      if (name == null || !mounted) {
        setState(() {
          _calStep = 0;
          _tempRefPts = [];
          _tempCmpPts = [];
        });
        return;
      }

      final refSize = await _readImageSize(_refImg!);
      final refW = refSize.width;
      final refH = refSize.height;
      final refAnchors = refPts
          .asMap()
          .entries
          .map(
            (e) => AnchorPoint(
              id: _anchorId(e.key, refPts.length),
              x: e.value.dx / refW,
              y: e.value.dy / refH,
              type: 'corner',
              confidence: 1.0,
            ),
          )
          .toList();

      final profile = LayoutProfile(
        id: _activeReferenceId ??
            _layoutProfile?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        refAnchors: refAnchors,
        homography: alignResult.homography,
        cropRegion: CropRegion.defaultCrop,
        widthMm: AppConfig.printWidthMm,
        heightMm: AppConfig.printHeightMm,
        refImageWidth: refSize.width.round(),
        refImageHeight: refSize.height.round(),
        alignment: AlignmentInfo(
          reprojectionError: alignResult.reprojError,
          eccScore: alignResult.eccScore,
          confidence: alignResult.confidence,
        ),
        createdAt: _layoutProfile?.createdAt ?? DateTime.now(),
      );
      await LayoutProfileStorage.save(profile);
      await _loadProfiles();

      setState(() {
        _layoutProfile = profile;
        _savedRefLabel = name;
        _activeReferenceId = profile.id;
        _cmpAligned = alignResult.alignedBytes;
        _refAligned = alignResult.refCanonicalBytes;
        _refAnchorPts = refPts;
        _cmpAnchorPts = cmpPts;
        _calStep = 0;
        _tempRefPts = [];
        _tempCmpPts = [];
      });

      if (runCompareAfter) {
        shouldRunCompare = true;
        _setCompareStatus('Совмещение рассчитано. Запускаю сравнение...');
      } else {
        xpDlg(
          context,
          'Профиль сохранён',
          '"$name"\n${alignResult.qualityLabel}  ·  ошибка ${alignResult.reprojError.toStringAsFixed(1)} пкс',
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _calibrating = false;
          if (_calStep == 3) _calStep = 0;
        });
    }
    if (shouldRunCompare && mounted) {
      await _yieldUi();
      await _runCompare();
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
      final cmpSize = await _readImageSize(_cmpImg!);
      final cmpW = cmpSize.width;
      final cmpH = cmpSize.height;

      // Предсказываем позиции на новом образце из нормализованных координат профиля
      // (простое прямое применение — нормализованные позиции те же)
      final predicted = profile.refAnchors
          .map(
            (a) => Offset(a.x, a.y),
          ) // остаётся нормализованным для AnchorPointScreen
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
      final refW =
          profile.refImageWidth > 0 ? profile.refImageWidth.toDouble() : cmpW;
      final refH =
          profile.refImageHeight > 0 ? profile.refImageHeight.toDouble() : cmpH;
      final refPtsRaw = profile.refAnchors
          .map((a) => Offset(a.x * refW, a.y * refH))
          .toList();

      setState(() => _calibrating = true);
      final alignResult = await OpenCvService.alignByAnchors(
        _refImg!,
        _cmpImg!,
        refPtsRaw,
        srcPtsRaw,
      );
      if (!mounted) return;
      if (alignResult == null) return;

      // Показываем результат валидации
      await _showAlignmentValidation(alignResult, confirmOnly: true);
      if (!mounted) return;

      setState(() {
        _layoutProfile = profile;
        _cmpAligned = alignResult.alignedBytes;
        _refAligned = alignResult.refCanonicalBytes;
        _refAnchorPts = refPtsRaw;
        _cmpAnchorPts = srcPtsRaw;
      });
    } finally {
      if (mounted) setState(() => _calibrating = false);
    }
  }

  // Validation dialog — возвращает true если пользователь принял результат
  Future<bool> _showAlignmentValidation(
    AlignByAnchorsResult r, {
    bool confirmOnly = false,
    bool canAccept = true,
  }) async {
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
            title: Row(
              children: [
                Icon(Icons.tune, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Выравнивание: ${r.qualityLabel}',
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _validationRow(
                  'Ошибка репроекции',
                  '${r.reprojError.toStringAsFixed(2)} пкс',
                  r.reprojError < 3.0 ? Colors.green : Colors.orange,
                ),
                _validationRow(
                  'ECC Score',
                  '${(r.eccScore * 100).toStringAsFixed(1)}%',
                  r.eccScore > 0.9 ? Colors.green : Colors.orange,
                ),
                _validationRow(
                  'Уверенность',
                  '${(r.confidence * 100).toStringAsFixed(0)}%',
                  r.confidence > 0.85 ? Colors.green : Colors.orange,
                ),
                if (r.reprojError >= 3.0) ...[
                  const SizedBox(height: 10),
                  Text(
                    canAccept
                        ? 'Ошибка выше идеальной нормы. Для фото под углом это допустимо, но после сохранения проверьте наложение и карту отличий.'
                        : 'Точки не совпадают как пары. Профиль не будет сохранён: переставьте точки образца в том же порядке, что на эталоне.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: color),
                  ),
                ],
              ],
            ),
            actions: !canAccept
                ? [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Переставить точки'),
                    ),
                  ]
                : confirmOnly
                    ? [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('OK'),
                        ),
                      ]
                    : [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
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
      text:
          'Профиль ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
    );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              ctrl.text.trim().isEmpty ? 'Профиль' : ctrl.text.trim(),
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleCtrlKey);
    CalibrationSettingsService.notifier.removeListener(_onCalibrationSettings);
    _jobNumberCtrl.dispose();
    _tabs.dispose();
    _overlayCtrl.dispose();
    _cmp2Ctrl.dispose();
    _workspaceScrollCtrl.dispose();
    _refAlignCtrl.dispose();
    _cmpAlignCtrl.dispose();
    _resultCmpCtrl.dispose();
    super.dispose();
  }

  // ── Зум/панорамирование картинок разрешён только при зажатом
  // Ctrl — иначе колесо мыши/трекпад над картинкой перехватывает
  // скролл страницы вместо её прокрутки.
  bool _ctrlHeld = false;
  bool _handleCtrlKey(KeyEvent event) {
    final held = HardwareKeyboard.instance.isControlPressed;
    if (held != _ctrlHeld) setState(() => _ctrlHeld = held);
    return false;
  }

  // ── Сброс масштаба всех зумируемых панелей ────────
  void _resetZoomControllers() {
    _refAlignCtrl.value = Matrix4.identity();
    _cmpAlignCtrl.value = Matrix4.identity();
    _resultCmpCtrl.value = Matrix4.identity();
  }

  // ── Второй эталон: выбор ─────────────────────────
  Future<void> _pickRef2([ImageSource? source]) async {
    final src = source ?? await _pickSource();
    if (src == null) return;
    final x = await _picker.pickImage(source: src, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _ref2Img = bytes;
      _ref1Sharpness = null;
      _ref2Sharpness = null;
    });
    // Считаем резкость обоих снимков параллельно
    final results = await Future.wait([
      compute(_laplacianSharpness, _refImg!),
      compute(_laplacianSharpness, bytes),
    ]);
    if (mounted)
      setState(() {
        _ref1Sharpness = results[0];
        _ref2Sharpness = results[1];
      });
  }

  // ── Выбрать снимок: слить оба → коррекция перспективы → сохранить ──
  // ref = выбранный (лучший), src = второй; если src == null — только коррекция
  void _openFullScreen(Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullScreenViewer(bytes: bytes),
      ),
    );
  }

  Future<void> _selectRef(Uint8List ref, [Uint8List? src]) async {
    setState(() {
      _stacking = true;
    });
    try {
      final fused =
          src != null ? await OpenCvService.fuseImages(ref, src) : ref;
      if (!mounted) return;
      final sz = await _readImageSize(fused);
      if (!mounted) return;
      setState(() {
        _refImg = fused;
        _refImgSize = sz;
        _savedRefLabel = null;
        _activeReferenceId = null;
        _refAligned = null;
        _layoutProfile = null;
        _refAnchorPts = null;
        _ref2Img = null;
        _ref1Sharpness = null;
        _ref2Sharpness = null;
        _result = null;
        _compareStatus = null;
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
    setState(() {
      _cmp2Img = bytes;
      _cmp2Ctrl.value = Matrix4.identity();
      _cmp1Sharpness = null;
      _cmp2Sharpness = null;
    });
    final results = await Future.wait([
      compute(_laplacianSharpness, _cmpImg!),
      compute(_laplacianSharpness, bytes),
    ]);
    if (mounted)
      setState(() {
        _cmp1Sharpness = results[0];
        _cmp2Sharpness = results[1];
      });
  }

  Future<void> _selectCmp(Uint8List ref, [Uint8List? src]) async {
    setState(() => _stacking = true);
    try {
      final fused =
          src != null ? await OpenCvService.fuseImages(ref, src) : ref;
      if (!mounted) return;
      final sz = await _readImageSize(fused);
      if (!mounted) return;
      setState(() {
        _cmpImg = fused;
        _cmpImgSize = sz;
        _cmpAligned = null;
        _cmpAnchorPts = null;
        _cmp2Img = null;
        _cmp2Ctrl.value = Matrix4.identity();
        _cmp1Sharpness = null;
        _cmp2Sharpness = null;
        _result = null;
        _compareStatus = null;
      });
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  Future<ImageSource?> _pickSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.silver,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Text('🖼️', style: TextStyle(fontSize: 20)),
            title: const Text('Галерея'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            leading: const Text('📷', style: TextStyle(fontSize: 20)),
            title: const Text('Камера'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ],
      ),
    );
  }

  // ── AI анализ качества эталона ───────────────────
  Future<void> _analyzeReferenceWithAi() async {
    if (_refImg == null) return;
    setState(() {
      _refAiLoading = true;
      _refAiResult = null;
    });
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
  void _setCompareStatus(String message) {
    if (!mounted) return;
    setState(() {
      _compareStatus = message;
      if (_compareSteps.isEmpty || _compareSteps.last != message) {
        _compareSteps.add(message);
      }
    });
  }

  Future<void> _yieldUi() {
    return Future<void>.delayed(const Duration(milliseconds: 16));
  }

  bool get _canRunAlignedCompare =>
      _refImg != null &&
      _cmpImg != null &&
      _layoutProfile != null &&
      _cmpAligned != null &&
      _calStep == 0 &&
      !_calibrating;

  bool get _canCalculateAndCompare =>
      _refImg != null &&
      _cmpImg != null &&
      _calStep == 2 &&
      !_calibrating &&
      _tempRefPts.isNotEmpty &&
      _tempCmpPts.length == _tempRefPts.length;

  bool get _canStartCompareAction =>
      _canRunAlignedCompare || _canCalculateAndCompare;

  String get _currentJobNumber => _jobNumber.trim();

  String get _currentJobId {
    final raw = _currentJobNumber;
    if (raw.isEmpty) return 'job-local';
    final safe = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isNotEmpty) return 'job-$safe';
    final encoded =
        raw.runes.take(24).map((r) => r.toRadixString(16)).join('-');
    return encoded.isEmpty ? 'job-local' : 'job-$encoded';
  }

  String get _currentSampleLabel => 'Отпечаток $_sampleNo';

  int _nextSampleNumberFor({
    String? referenceId,
    String? referenceLabel,
    int minValue = 1,
  }) {
    final refId = referenceId ?? _activeReferenceId ?? '';
    final refLabel = referenceLabel ?? _savedRefLabel ?? '';
    final jobNumber = _currentJobNumber;
    var maxNo = 0;
    for (final p in CheckHistoryService.checks.value) {
      final sameJob =
          jobNumber.isEmpty ? p.jobNumber.isEmpty : p.jobNumber == jobNumber;
      final sameRef = refId.isNotEmpty
          ? p.referenceId == refId
          : refLabel.isNotEmpty && p.referenceLabel == refLabel;
      if (sameJob && sameRef) maxNo = max(maxNo, p.sampleNo);
    }
    return max(minValue, maxNo + 1);
  }

  Future<void> _runCompare() async {
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    if (ref == null || cmp == null) {
      xpDlg(context, 'Ошибка', 'Загрузите оба изображения');
      return;
    }
    if (!_canRunAlignedCompare) {
      if (_canCalculateAndCompare) {
        await _runAlignmentFromPoints(runCompareAfter: true);
        return;
      }
      xpDlg(
        context,
        'Нужен этап «Рассчитать»',
        'Сначала выберите эталон, поставьте точки на образце и нажмите «Рассчитать». После этого можно запускать сравнение.',
      );
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
      _refLabFingerprint = null;
      _cmpLabFingerprint = null;
      _labFingerprintMatch = null;
      _result = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareSteps
        ..clear()
        ..add('Готовлю изображения к проверке...');
      _compareStatus = 'Готовлю изображения к проверке...';
      _resultMapMode = _ResultMapMode.deltaE;
    });
    _resultCmpCtrl.value = Matrix4.identity();
    try {
      _setCompareStatus(
        'Этап 1/5: проверяю ч/б геометрию и базовую карту отличий...',
      );
      await _yieldUi();
      final compareResult = await CompareService.compare(
        ref,
        cmp,
        onProgress: (message) => _setCompareStatus(message),
      );
      if (!mounted) return;
      setState(() {
        _result = compareResult;
      });
      _setCompareStatus(_geometryStatusLine(compareResult));
      _tabs.animateTo(3);

      // Lab-пирамида — точнее MAE, обновляем результат если OpenCV доступен.
      _setCompareStatus('Этап 2/5: рассчитываю цветовую карту Delta E...');
      await _yieldUi();
      final lab = await OpenCvService.compareImages(ref, cmp);
      if (lab != null && mounted && _result != null) {
        final r = _result!;
        setState(
          () => _result = CompareResult(
            similarity: r.similarity,
            labScore: lab.score,
            labLevel0: lab.level0,
            labLevel1: lab.level1,
            labLevel2: lab.level2,
            labLevel3: lab.level3,
            shiftDL: lab.shiftDL,
            shiftDA: lab.shiftDA,
            shiftDB: lab.shiftDB,
            meanDeltaE: _meanOf(lab.level3) ?? r.meanDeltaE,
            maxDeltaE: _maxOf(lab.level3) ?? r.maxDeltaE,
            defectZoneCount: _countAbove(lab.level3, 6.0) ?? r.defectZoneCount,
            defectAreaPercent:
                _percentAbove(lab.level3, 6.0) ?? r.defectAreaPercent,
            refCanonical: lab.refCanonical,
            cmpCanonical: lab.cmpCanonical,
            diffPixels: r.diffPixels,
            totalPixels: r.totalPixels,
            refSize: r.refSize,
            cmpSize: r.cmpSize,
            diffL3: lab.diffL3,
            geometryScore: r.geometryScore,
            geometryShiftPx: r.geometryShiftPx,
            geometryMissingPercent: r.geometryMissingPercent,
            geometryExtraPercent: r.geometryExtraPercent,
            geometryOverlapPixels: r.geometryOverlapPixels,
            geometryMissingPixels: r.geometryMissingPixels,
            geometryExtraPixels: r.geometryExtraPixels,
            geometryDiff: r.geometryDiff,
            geometryRefCanonical: r.geometryRefCanonical,
            geometryCmpCanonical: r.geometryCmpCanonical,
          ),
        );
        _setCompareStatus(
          'Delta E рассчитана: max ${_fmt(_maxOf(lab.level3))}, среднее ${_fmt(_meanOf(lab.level3))}.',
        );
      } else {
        _setCompareStatus(
          'Delta E: используется базовая карта отличий без OpenCV Lab-пирамиды.',
        );
      }

      _setCompareStatus('Этап 3/5: проверяю штрихкоды и QR...');
      await _yieldUi();
      final barcodeResults = await Future.wait([
        BarcodeService.scanImage(
          ref,
        ).catchError((Object _) => <BarcodeResult>[]),
        BarcodeService.scanImage(
          cmp,
        ).catchError((Object _) => <BarcodeResult>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _refBarcodes = barcodeResults[0];
        _cmpBarcodes = barcodeResults[1];
      });
      _setCompareStatus(
        'Штрихкоды проверены: эталон ${_refBarcodes.length}, образец ${_cmpBarcodes.length}.',
      );
      _setCompareStatus('Этап 4/5: проверяю текст OCR...');
      await _yieldUi();

      Future<OcrResult> ocrSafe(Uint8List b) async {
        try {
          return await OcrService.recognize(b).timeout(
            const Duration(seconds: 15),
            onTimeout: () => const OcrResult('', [], error: 'Таймаут OCR'),
          );
        } catch (e) {
          return OcrResult('', [], error: e.toString());
        }
      }

      final ocrResults = await Future.wait([ocrSafe(ref), ocrSafe(cmp)]);
      if (!mounted) return;
      final ro = ocrResults[0];
      final co = ocrResults[1];
      setState(() {
        _refOcr = ro;
        _cmpOcr = co;
        _textDiff = (!ro.isEmpty || !co.isEmpty)
            ? OcrService.compareTexts(ro.fullText, co.fullText)
            : null;
      });
      _setCompareStatus(
        _textDiff == null
            ? 'OCR: распознанного текста для вычитки нет.'
            : 'OCR: совпадение текста ${_textDiff!.similarity.toStringAsFixed(1)}%.',
      );

      _setCompareStatus('Этап 5/5: строю Lab ID и сохраняю протокол...');
      await _yieldUi();
      final fingerprints = await Future.wait([
        LabFingerprintService.create(ref),
        LabFingerprintService.create(cmp),
      ]);
      if (!mounted) return;
      setState(() {
        _refLabFingerprint = fingerprints[0];
        _cmpLabFingerprint = fingerprints[1];
        _labFingerprintMatch = LabFingerprintService.matchScore(
          _refLabFingerprint,
          _cmpLabFingerprint,
        );
      });
      _setCompareStatus(
        'Lab ID готов: совпадение ${_fmt(_labFingerprintMatch)}%.',
      );

      try {
        await _saveCheckResult();
        _setCompareStatus('Проверка завершена.');
      } catch (_) {
        _setCompareStatus(
          'Проверка завершена. Локальный протокол не сохранён.',
        );
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка сравнения', e.toString());
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  // ── Сводные значения по Lab-зонам ────────────────
  double? _meanOf(List<double>? values) {
    if (values == null || values.isEmpty) return null;
    final active = values.where((v) => v.isFinite).toList();
    if (active.isEmpty) return null;
    return active.reduce((a, b) => a + b) / active.length;
  }

  double? _maxOf(List<double>? values) {
    if (values == null || values.isEmpty) return null;
    final active = values.where((v) => v.isFinite).toList();
    if (active.isEmpty) return null;
    return active.reduce(max);
  }

  int? _countAbove(List<double>? values, double threshold) {
    if (values == null || values.isEmpty) return null;
    return values.where((v) => v.isFinite && v >= threshold).length;
  }

  double? _percentAbove(List<double>? values, double threshold) {
    if (values == null || values.isEmpty) return null;
    final count = _countAbove(values, threshold);
    if (count == null) return null;
    return count / values.length * 100;
  }

  String _overallStatus(double score) {
    if (score >= 90) return 'В норме';
    if (score >= 80) return 'Проверить';
    if (score >= 65) return 'Требует проверки';
    return 'Критично';
  }

  String _shortStatus(double score) {
    if (score >= 90) return 'OK';
    if (score >= 80) return 'Проверить';
    if (score >= 65) return 'Контроль';
    return 'Критично';
  }

  List<CheckProtocolStage> _checkProtocolStages(CompareResult r) {
    final colorOk = (r.maxDeltaE ?? 0) < 6 && (r.meanDeltaE ?? 0) < 3;
    final geometryOk =
        (r.geometryScore ?? 0) >= 96 && (r.geometryShiftPx ?? 0) <= 1.2;
    final barcodePct = _barcodeMatchPct();
    final textOk = _textDiff == null || _textDiff!.allOk;
    final labOk = (_labFingerprintMatch ?? 100) >= 92;

    return [
      CheckProtocolStage(
        name: 'Подготовка',
        status: 'OK',
        metric: '${r.refSize} → ${r.cmpSize}',
        comment: 'Изображения загружены, обрезка и калибровка применены.',
      ),
      CheckProtocolStage(
        name: 'Цветовая карта ΔE',
        status: colorOk ? 'OK' : 'Внимание',
        metric:
            'max ${_fmt(r.maxDeltaE)} · среднее ${_fmt(r.meanDeltaE)} · ${r.diffPercent.toStringAsFixed(1)}%',
        comment: colorOk
            ? 'Цветовые отклонения в пределах рабочего порога.'
            : 'Есть зоны с заметным цветовым отличием.',
      ),
      CheckProtocolStage(
        name: 'Геометрия ЧБ',
        status: geometryOk ? 'OK' : 'Внимание',
        metric:
            '${_fmt(r.geometryScore)}% · сдвиг ${_fmt(r.geometryShiftPx)} px',
        comment: _geometryStatusLine(r),
      ),
      CheckProtocolStage(
        name: 'Штрихкоды / QR',
        status: barcodePct == null || barcodePct >= 99 ? 'OK' : 'Внимание',
        metric: barcodePct == null ? 'не обнаружены' : '${_fmt(barcodePct)}%',
        comment: barcodePct == null
            ? 'Коды не найдены на изображениях.'
            : 'Совпадение найденных кодов.',
      ),
      CheckProtocolStage(
        name: 'Текст / OCR',
        status: textOk ? 'OK' : 'Внимание',
        metric: _textDiff == null
            ? 'нет текста'
            : '${_fmt(_textDiff!.similarity)}%',
        comment: _textDiff == null
            ? 'Распознанного текста для вычитки нет.'
            : (_textDiff!.allOk
                ? 'Текст совпадает по распознанным словам.'
                : 'Есть пропущенные или лишние слова.'),
      ),
      CheckProtocolStage(
        name: 'Lab ID',
        status: labOk ? 'OK' : 'Внимание',
        metric:
            '${_shortLabId(_refLabFingerprint?.labId)} · ${_fmt(_labFingerprintMatch)}%',
        comment: 'Сохранён локальный Lab-паспорт последней проверки.',
      ),
      CheckProtocolStage(
        name: 'Итог',
        status: _overallStatus(r.score),
        metric: '${r.score.toStringAsFixed(1)}%',
        comment: 'Общий результат без отправки в базу.',
      ),
    ];
  }

  String _fmt(num? value) => value == null ? '-' : value.toStringAsFixed(1);

  // ── % совпадения штрихкодов эталон/образец ───────
  double? _barcodeMatchPct() {
    if (_refBarcodes.isEmpty && _cmpBarcodes.isEmpty) return null;
    if (_refBarcodes.isEmpty || _cmpBarcodes.isEmpty) return 0.0;
    final refVals = _refBarcodes.map((b) => b.value).toSet();
    final cmpVals = _cmpBarcodes.map((b) => b.value).toSet();
    return refVals.intersection(cmpVals).length / refVals.length * 100;
  }

  // ── Сохранить локальный протокол последней проверки ──
  Future<void> _saveCheckResult() async {
    final r = _result;
    if (r == null) return;
    final now = DateTime.now();
    final referenceId = _activeReferenceId ?? '';
    final jobNumber = _currentJobNumber;
    final sampleNumber = _nextSampleNumberFor(
      referenceId: referenceId,
      referenceLabel: _savedRefLabel,
      minValue: _sampleNo,
    );
    final sampleImageId =
        '$_currentJobId-sample-$sampleNumber-${now.millisecondsSinceEpoch}';
    if (mounted) setState(() => _sampleNo = sampleNumber);
    await CheckHistoryService.saveLast(
      CheckProtocol(
        id: now.millisecondsSinceEpoch.toString(),
        createdAt: now,
        jobId: _currentJobId,
        jobNumber: jobNumber,
        score: r.score,
        verdict: _overallStatus(r.score),
        refSize: r.refSize,
        cmpSize: r.cmpSize,
        labId: _shortLabId(_refLabFingerprint?.labId),
        referenceId: referenceId,
        referenceLabel: _savedRefLabel ?? _layoutProfile?.name ?? 'Эталон',
        sampleLabel: 'Отпечаток $sampleNumber',
        sampleImageId: sampleImageId,
        sampleNo: sampleNumber,
        labMatch: _labFingerprintMatch,
        stages: _checkProtocolStages(r),
      ),
    );
  }

  String _shortLabId(String? value) {
    if (value == null || value.isEmpty) return '-';
    return value.length <= 8 ? value : value.substring(0, 8);
  }

  // ── Кроп рамкой ──────────────────────────────────
  Future<void> _cropImage(bool isRef) async {
    final src = isRef ? _refImg : _cmpImg;
    if (src == null) return;
    final result = await CropFrameScreen.show(
      context,
      src,
      title: isRef ? 'Рамка — Эталон' : 'Рамка — Образец',
    );
    if (result != null && mounted) {
      setState(() {
        _imageBusy = true;
        _imageBusyLabel = 'Применение рамки...';
      });
      try {
        // Обрезанная картинка имеет другие размеры — пересчитываем
        // _refImgSize/_cmpImgSize, иначе панель якорных точек продолжает
        // мапить клики по старым (необрезанным) размерам, и точки
        // оказываются смещены относительно реального изображения.
        final sz = await _readImageSize(result);
        if (!mounted) return;
        final newSize = sz;
        setState(() {
          // Точки незавершённой калибровки (_tempRefPts/_tempCmpPts) записаны
          // в пиксельных координатах старого (необрезанного) изображения —
          // после обрезки они "уезжают" относительно нового кадра, поэтому
          // сбрасываем калибровку целиком, а не только подтверждённые точки.
          _calStep = 0;
          _tempRefPts = [];
          _tempCmpPts = [];
          if (isRef) {
            _layoutProfile = null;
            _refImg = result;
            _refImgSize = newSize;
            _savedRefLabel = null;
            _activeReferenceId = null;
            _refAligned = null;
            _refAnchorPts = null;
          } else {
            _cmpImg = result;
            _cmpImgSize = newSize;
            _cmpAligned = null;
            _cmpAnchorPts = null;
          }
        });
      } finally {
        if (mounted) setState(() => _imageBusy = false);
      }
    }
  }

  // ── Выбор фото ───────────────────────────────────
  Future<void> _pickImage(bool isRef) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Material(
        color: AppTheme.silver,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Text('📂', style: TextStyle(fontSize: 20)),
              title: const Text('Открыть файл'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
            ListTile(
              leading: const Text('🖼️', style: TextStyle(fontSize: 20)),
              title: const Text('Галерея'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Text('📷', style: TextStyle(fontSize: 20)),
              title: const Text('Камера'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final source =
        result == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final x = await _picker.pickImage(source: source, imageQuality: 92);
    if (x == null) return;

    setState(() {
      _imageBusy = true;
      _imageBusyLabel = isRef ? 'Загрузка эталона...' : 'Загрузка образца...';
    });
    try {
      final bytes = await x.readAsBytes();
      if (isRef) {
        // Сбрасываем второй снимок и пропускаем через _selectRef (перспектива)
        if (!mounted) return;
        setState(() {
          _ref2Img = null;
          _ref1Sharpness = null;
          _ref2Sharpness = null;
        });
        await _selectRef(bytes);
      } else {
        final sz = await _readImageSize(bytes);
        if (!mounted) return;
        setState(() {
          _cmpImg = bytes;
          _cmpImgSize = sz;
          _cmpAligned = null;
          _cmpAnchorPts = null;
          _result = null;
          _compareStatus = null;
        });
      }
    } finally {
      if (mounted) setState(() => _imageBusy = false);
    }
  }

  // ── Build ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        XpMenuBar(
          icon: 'PC',
          menus: [
            XpMenu(
              label: 'Файл',
              items: [
                XpMenuItem(
                  label: 'Новое',
                  icon: '+',
                  shortcut: 'Ctrl+N',
                  onTap: () => setState(() {
                    _refImg = null;
                    _refImgSize = null;
                    _cmpImg = null;
                    _cmpImgSize = null;
                    _refAligned = null;
                    _cmpAligned = null;
                    _layoutProfile = null;
                    _refAnchorPts = null;
                    _cmpAnchorPts = null;
                    _result = null;
                    _compareStatus = null;
                    _aiResult = null;
                    _refBarcodes = [];
                    _cmpBarcodes = [];
                    _refOcr = null;
                    _cmpOcr = null;
                    _textDiff = null;
                    _resetZoomControllers();
                    _tabs.animateTo(0);
                  }),
                ),
                XpMenuItem.sep,
                XpMenuItem(
                  label: 'Сохранить',
                  icon: 'S',
                  shortcut: 'Ctrl+S',
                  onTap: () async {
                    if (_result == null) {
                      xpDlg(context, 'Ошибка', 'Сначала выполните сравнение');
                      return;
                    }
                    try {
                      await _saveCheckResult();
                      if (mounted) {
                        xpDlg(
                          context,
                          'Сохранено',
                          'Результат сохранён в историю',
                        );
                      }
                    } catch (e) {
                      if (mounted)
                        xpDlg(context, 'Ошибка сохранения', e.toString());
                    }
                  },
                ),
                XpMenuItem(
                  label: 'Экспорт...',
                  icon: 'EX',
                  shortcut: 'Ctrl+E',
                  onTap: () =>
                      xpDlg(context, 'Экспорт', 'Форматы: PNG, PDF, CSV'),
                ),
              ],
            ),
            XpMenu(
              label: 'Вид',
              items: [
                XpMenuItem(
                  label: 'Загрузка эталона',
                  icon: 'R',
                  onTap: () => _tabs.animateTo(0),
                ),
                XpMenuItem(
                  label: 'Образец',
                  icon: 'S',
                  onTap: () => _tabs.animateTo(1),
                ),
                XpMenuItem(
                  label: 'Совмещение',
                  icon: 'A',
                  onTap: () => _tabs.animateTo(2),
                ),
                XpMenuItem(
                  label: 'Результат',
                  icon: '%',
                  onTap: () => _tabs.animateTo(3),
                ),
              ],
            ),
            XpMenu(
              label: 'Инструменты',
              items: [
                XpMenuItem(
                  label: 'AI Анализ',
                  icon: 'AI',
                  onTap: _runAiAnalysis,
                ),
              ],
            ),
            XpMenu(
              label: 'Справка',
              items: [
                XpMenuItem(
                  label: 'Горячие клавиши',
                  icon: '?',
                  onTap: () => xpDlg(
                    context,
                    'Горячие клавиши',
                    'Ctrl+N — Новое\nCtrl+S — Сохранить\nCtrl+E — Экспорт\nCtrl+R — Повернуть\nCtrl+T — Захватить\nCtrl++/- — Зум',
                  ),
                ),
              ],
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820) {
                return _mobileWorkbench();
              }
              return _desktopWorkbench(constraints.maxWidth);
            },
          ),
        ),
      ],
    );
  }

  Widget _desktopWorkbench(double width) {
    final stepWidth = width >= 1200 ? 170.0 : 140.0;
    final inspectorWidth = width >= 1200 ? 320.0 : 280.0;

    if (_calStep != 0) {
      return Container(
        color: const Color(0xFFC9CDD3),
        child: Scrollbar(
          controller: _workspaceScrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _workspaceScrollCtrl,
            padding: const EdgeInsets.all(10),
            child: _workspaceColumn(),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFC9CDD3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: stepWidth, child: _workflowRail()),
          Expanded(
            child: Scrollbar(
              controller: _workspaceScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _workspaceScrollCtrl,
                padding: const EdgeInsets.all(10),
                child: _workspaceColumn(),
              ),
            ),
          ),
          SizedBox(width: inspectorWidth, child: _inspectorPanel()),
        ],
      ),
    );
  }

  Widget _mobileWorkbench() {
    if (_calStep != 0) {
      return Container(
        color: const Color(0xFFC9CDD3),
        child: Scrollbar(
          controller: _workspaceScrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _workspaceScrollCtrl,
            padding: const EdgeInsets.all(10),
            child: _workspaceColumn(),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFC9CDD3),
      child: Scrollbar(
        controller: _workspaceScrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _workspaceScrollCtrl,
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _workflowRail(horizontal: true),
              const SizedBox(height: 10),
              _workspaceColumn(),
              const SizedBox(height: 10),
              _inspectorPanel(compact: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workflowRail({bool horizontal = false}) {
    final hasJob = _currentJobNumber.isNotEmpty;
    final steps = [
      _FlowStep('1', 'Работа', hasJob, !hasJob),
      _FlowStep('2', 'Эталон', _refImg != null, hasJob && _refImg == null),
      _FlowStep(
        '3',
        'Отпечаток',
        _cmpImg != null,
        _refImg != null && _cmpImg == null,
      ),
      _FlowStep(
        '4',
        'Точки',
        _layoutProfile != null,
        _refImg != null && _cmpImg != null && _layoutProfile == null,
      ),
      _FlowStep(
        '5',
        'Сравнение',
        _result != null,
        _refImg != null &&
            _cmpImg != null &&
            _layoutProfile != null &&
            _result == null,
      ),
    ];

    final content = horizontal
        ? Row(
            children: steps.map((s) => Expanded(child: _stepTile(s))).toList(),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _railHeader('Процесс'),
              ...steps.map(_stepTile),
              const Spacer(),
              _railNote(),
            ],
          );

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE7E8E4),
        border: Border(right: BorderSide(color: Color(0xFF8C929C))),
      ),
      padding: horizontal
          ? const EdgeInsets.all(6)
          : const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: content,
    );
  }

  Widget _railHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.blueDark,
        border: Border.all(color: Colors.white38),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _stepTile(_FlowStep step) {
    final color = step.done
        ? AppTheme.simHigh
        : step.active
            ? AppTheme.blue
            : Colors.grey.shade600;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: step.active ? Colors.white : const Color(0xFFEDEDE8),
        border: Border.all(color: color.withOpacity(step.active ? 0.9 : 0.35)),
        boxShadow: step.active ? AppTheme.shadowSubtle : null,
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white70),
            ),
            child: Text(
              step.done ? '✓' : step.num,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              step.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: step.active ? Colors.black : Colors.black87,
                fontWeight: step.active ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railNote() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F5),
        border: Border.all(color: AppTheme.silverDark),
      ),
      child: const Text(
        'Эталон задаёт контекст. Основной анализ выполняется по образцу и карте отличий.',
        style: TextStyle(fontSize: 10, height: 1.35, color: Colors.black54),
      ),
    );
  }

  Widget _workspaceColumn() {
    if (_calStep != 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _calibrationWorkbench(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stagePanel(
          title: 'Эталон',
          subtitle: _savedRefLabel != null
              ? 'Сохранён: $_savedRefLabel'
              : (_refImg == null ? 'Загрузите цифровой файл' : 'Эталон готов'),
          bytes: _refImg,
          placeholderIcon: Icons.image_outlined,
          placeholder: 'Нажмите, чтобы загрузить эталон',
          onTap: () => _pickImage(true),
          onOpen: _refImg != null ? () => _openFullScreen(_refImg!) : null,
          actions: [
            _toolBtn(Icons.upload_file, 'Загрузить', () => _pickImage(true)),
            _toolBtn(
              Icons.crop,
              'Рамка',
              _refImg != null ? () => _cropImage(true) : null,
            ),
            _toolBtn(
              Icons.save,
              'Сохранить',
              _refImg != null ? _saveReference : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _stagePanel(
          title: 'Образец',
          subtitle: _cmpImg == null
              ? 'Снимите или загрузите проверяемую распечатку'
              : 'Основная зона анализа',
          bytes: _cmpAligned ?? _cmpImg,
          placeholderIcon: Icons.photo_camera_outlined,
          placeholder: 'Нажмите, чтобы загрузить образец',
          onTap: () => _pickImage(false),
          onOpen: _cmpImg != null
              ? () => _openFullScreen(_cmpAligned ?? _cmpImg!)
              : null,
          actions: [
            _toolBtn(Icons.add_a_photo, 'Загрузить', () => _pickImage(false)),
            _toolBtn(
              Icons.crop,
              'Рамка',
              _cmpImg != null ? () => _cropImage(false) : null,
            ),
            _toolBtn(
              Icons.tune,
              'Точки',
              _refImg != null && _cmpImg != null
                  ? () => _startCalibration()
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _comparisonStage(),
      ],
    );
  }

  Widget _stagePanel({
    required String title,
    required String subtitle,
    required Uint8List? bytes,
    required IconData placeholderIcon,
    required String placeholder,
    required VoidCallback onTap,
    VoidCallback? onOpen,
    List<Widget> actions = const [],
  }) {
    const ratio = 16 / 9;
    final busy = _stacking || _imageBusy;
    final busyLabel = _stacking ? 'Объединение снимков...' : _imageBusyLabel;
    return _xpWindow(
      title: title,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 0),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 7),
          GestureDetector(
            onTap: busy ? null : onTap,
            onDoubleTap: busy ? null : onOpen,
            child: AspectRatio(
              aspectRatio: ratio,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.black,
                child: busy
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              busyLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      )
                    : bytes != null
                        ? _uiImage(bytes, fit: BoxFit.contain)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                placeholderIcon,
                                size: 38,
                                color: Colors.white38,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                placeholder,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'JPEG, PNG, камера или галерея',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _comparisonStage() {
    final r = _result;
    return _xpWindow(
      title: 'Сравнение и карта отличий',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (r != null) SimBadge(value: r.score, fontSize: 11),
          const SizedBox(width: 6),
          _toolBtn(
            Icons.compare,
            'Сравнить',
            _canStartCompareAction ? _runCompare : null,
            primary: true,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_compareStatus != null) ...[
              _compareProgressPanel(compact: true),
              const SizedBox(height: 8),
            ],
            if (r?.diffL3 != null || r?.geometryDiff != null) ...[
              _mapModeSelector(),
              if (_showAreaLoupePanel) ...[
                const SizedBox(height: 8),
                _areaLoupePanel(),
              ],
              const SizedBox(height: 8),
              _mapLegend(),
              const SizedBox(height: 8),
              _resultMapOverlay(r!),
              Row(
                children: [
                  const Text('Эталон', style: TextStyle(fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: _diffSlider,
                      onChanged: (v) => setState(() => _diffSlider = v),
                      activeColor: AppTheme.blue,
                    ),
                  ),
                  Text(
                    _resultMapMode == _ResultMapMode.overlay
                        ? 'Образец'
                        : 'Образец + карта',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ] else if (_comparing)
              const SizedBox(
                height: 320,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: const Color(0xFF111111),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.difference_outlined,
                          size: 40,
                          color: Colors.white.withOpacity(0.34),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _result == null
                              ? 'После сравнения здесь появится карта отличий'
                              : 'Карта отличий пока рассчитывается',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (r != null) ...[const SizedBox(height: 8), _resultSummaryBar(r)],
            if (r != null) ...[
              const SizedBox(height: 8),
              _pointProbePanel(r),
            ],
            if (r != null ||
                CheckHistoryService.checks.value.any(
                  (p) =>
                      _activeReferenceId == null ||
                      p.referenceId == _activeReferenceId ||
                      p.referenceLabel == _savedRefLabel,
                )) ...[
              const SizedBox(height: 10),
              _checkProtocolListPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _compareProgressPanel({bool compact = false}) {
    final visibleSteps = compact && _compareSteps.length > 4
        ? _compareSteps.sublist(_compareSteps.length - 4)
        : _compareSteps;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _comparing ? const Color(0xFFEAF3FF) : const Color(0xFFEAF8EF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _comparing ? AppTheme.blueLight : AppTheme.simHigh,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_comparing)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.check_circle, size: 15, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _compareStatus ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (visibleSteps.length > 1) ...[
            const SizedBox(height: 7),
            ...visibleSteps.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      s == _compareStatus && _comparing
                          ? Icons.radio_button_checked
                          : Icons.done,
                      size: 12,
                      color: s == _compareStatus && _comparing
                          ? AppTheme.blue
                          : Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.25,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mapModeSelector() {
    Widget item(_ResultMapMode mode, String label) {
      final selected = _resultMapMode == mode;
      const activeColor = Color(0xFF2563EB);
      const inactiveColor = Color(0xFFE5E7EB);
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _resultMapMode = mode),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFFD1D5DB),
              ),
              boxShadow: selected
                  ? [
                      const BoxShadow(
                        color: Color(0x260F172A),
                        blurRadius: 7,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ),
        ),
      );
    }

    Widget tool(_InspectionTool tool, IconData icon, String label) {
      final selected = _inspectionTool == tool;
      const activeColor = Color(0xFF2563EB);
      const inactiveColor = Color(0xFFE5E7EB);
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _inspectionTool = tool),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFFD1D5DB),
              ),
              boxShadow: selected
                  ? [
                      const BoxShadow(
                        color: Color(0x260F172A),
                        blurRadius: 7,
                        offset: Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : const Color(0xFF64748B)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      Row(
        children: [
          item(_ResultMapMode.deltaE, 'ΔE цвет'),
          const SizedBox(width: 6),
          item(_ResultMapMode.geometry, 'Геометрия ЧБ'),
          const SizedBox(width: 6),
          item(_ResultMapMode.overlay, 'Наложение'),
        ],
      ),
      const SizedBox(height: 6),
      Row(children: [
        tool(_InspectionTool.point, Icons.gps_fixed, 'Параметры точки'),
        const SizedBox(width: 6),
        tool(_InspectionTool.loupe, Icons.zoom_in, 'Лупа области'),
      ]),
    ]);
  }

  Widget _mapLegend() {
    if (_resultMapMode == _ResultMapMode.geometry) {
      return Row(
        children: [
          _legendItem(const Color(0xFF285AFF), 'нет в образце'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFFE61E78), 'лишнее в образце'),
        ],
      );
    }
    if (_resultMapMode == _ResultMapMode.overlay) {
      return const Text(
        'Ползунок показывает эталон ↔ образец без подсветки отличий.',
        style: TextStyle(fontSize: 10, color: Colors.grey),
      );
    }
    return Row(
      children: [
        _legendItem(const Color(0xFF1EC81E), 'ΔE < 3'),
        const SizedBox(width: 12),
        _legendItem(const Color(0xFFE8A000), 'ΔE 3–6'),
        const SizedBox(width: 12),
        _legendItem(const Color(0xFFDC1414), 'ΔE > 6'),
      ],
    );
  }

  Widget _resultMapOverlay(CompareResult r) {
    final diff = switch (_resultMapMode) {
      _ResultMapMode.deltaE => r.diffL3,
      _ResultMapMode.geometry => r.geometryDiff,
      _ResultMapMode.overlay => null,
    };
    final refBase = _resultMapMode == _ResultMapMode.geometry
        ? r.geometryRefCanonical ?? r.refCanonical
        : r.refCanonical;
    final cmpBase = _resultMapMode == _ResultMapMode.geometry
        ? r.geometryCmpCanonical ?? r.cmpCanonical
        : r.cmpCanonical;
    return _diffOverlay(
      diff,
      refBase,
      cmpBase,
      _resultCmpCtrl,
      imageSize: _parseImageSize(r.refSize),
    );
  }

  Size _parseImageSize(String label) {
    final normalized = label.toLowerCase().replaceAll('x', '×');
    final parts = normalized.split('×');
    if (parts.length == 2) {
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w != null && h != null && w > 0 && h > 0) {
        return Size(w, h);
      }
    }
    return const Size(1600, 900);
  }

  bool get _showAreaLoupePanel =>
      _inspectionTool == _InspectionTool.loupe || _areaLoupe != null;

  Widget _pointProbePanel(CompareResult r) {
    final probe = _pointProbe;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const BoxDecoration(
            color: Color(0xFFEAF6FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            const Expanded(
              child: Text(
                'Контроль точки',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              probe == null
                  ? 'кликните по карте'
                  : 'x ${probe.x}, y ${probe.y}',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        if (probe == null)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'Наведите курсор на интересное место в окне сравнения и кликните мышью. Здесь появятся CMYK эталона, CMYK образца и ΔE в выбранной точке.',
              style:
                  TextStyle(fontSize: 11, height: 1.35, color: Colors.black54),
            ),
          )
        else
          Container(
            color: const Color(0xFFF8FAFC),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _probeCell(
                  'Сходство',
                  '${r.score.toStringAsFixed(1)}%\nточка ΔE ${probe.deltaE.toStringAsFixed(2)}',
                  flex: 2,
                ),
                _probeCell('CMYK эталона', probe.refCmyk.label, flex: 3),
                _probeCell('CMYK образца', probe.cmpCmyk.label, flex: 3),
                _probeCell(
                  'Lab',
                  'эталон ${probe.refLab.label}\nобразец ${probe.cmpLab.label}',
                  flex: 3,
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _areaLoupePanel() {
    final loupe = _areaLoupe;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const BoxDecoration(
            color: Color(0xFFEAF6FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(children: [
            const Expanded(
              child: Text(
                'Лупа области',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              loupe == null
                  ? 'выделите область мышью'
                  : 'эталон ${loupe.refWidth}×${loupe.refHeight} · образец ${loupe.cmpWidth}×${loupe.cmpHeight}',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        if (loupe == null)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'Зажмите мышь на карте сравнения и выделите прямоугольник. Окно сравнения приблизит выбранное место; ползунок над картой переключает эталон и образец.',
              style:
                  TextStyle(fontSize: 11, height: 1.35, color: Colors.black54),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              const Icon(Icons.zoom_in, size: 16, color: Color(0xFF1D6E68)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Область приближена в окне сравнения. Двигайте ползунок: эталон ↔ образец.',
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Colors.black54,
                  ),
                ),
              ),
              XpBtn(
                label: 'Сбросить',
                icon: Icons.restart_alt,
                primary: true,
                width: 138,
                onPressed: () {
                  _resultCmpCtrl.value = Matrix4.identity();
                  setState(() {
                    _areaLoupe = null;
                    _loupeDraftRect = null;
                    _loupeDragStart = null;
                  });
                },
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _probeCell(String title, String value, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _checkProtocolListPanel() {
    return ValueListenableBuilder<List<CheckProtocol>>(
      valueListenable: CheckHistoryService.checks,
      builder: (context, protocols, _) {
        final list = protocols
            .where(
              (p) =>
                  _activeReferenceId == null ||
                  p.referenceId == _activeReferenceId ||
                  p.referenceLabel == _savedRefLabel,
            )
            .toList();
        if (list.isEmpty && _result != null) {
          return _checkProtocolTable(
            title: 'Протокол проверки',
            stages: _checkProtocolStages(_result!),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: AppTheme.blueDark,
                child: const Text(
                  'Протокол проверки',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...list.asMap().entries.map((entry) {
                final i = entry.key;
                final p = entry.value;
                final jobLabel = p.jobNumber.isEmpty
                    ? 'Работа не задана'
                    : 'Работа ${p.jobNumber}';
                final imageId = p.sampleImageId.isEmpty
                    ? '-'
                    : _shortLabId(p.sampleImageId);
                return ExpansionTile(
                  initiallyExpanded: i == 0,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    '$jobLabel · ${p.sampleLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    '${p.referenceLabel} · файл $imageId · ${p.verdict} · ${p.score.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: SimBadge(value: p.score, fontSize: 10),
                  children: [_protocolStageTable(p.stages)],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _checkProtocolTable({
    required String title,
    required List<CheckProtocolStage> stages,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: AppTheme.blueDark,
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            color: AppTheme.silver,
            child: Row(
              children: [
                _protocolCell('Этап', flex: 3, bold: true),
                _protocolCell('Статус', flex: 2, bold: true),
                _protocolCell('Метрика', flex: 3, bold: true),
                _protocolCell('Комментарий', flex: 5, bold: true),
              ],
            ),
          ),
          ...stages.asMap().entries.map((entry) {
            final i = entry.key;
            final stage = entry.value;
            return Container(
              color: i.isEven ? Colors.white : const Color(0xFFF5F8FB),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _protocolCell(stage.name, flex: 3),
                  _protocolCell(stage.status, flex: 2),
                  _protocolCell(stage.metric, flex: 3),
                  _protocolCell(stage.comment, flex: 5),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _protocolStageTable(List<CheckProtocolStage> stages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: AppTheme.silver,
          child: Row(
            children: [
              _protocolCell('Этап', flex: 3, bold: true),
              _protocolCell('Статус', flex: 2, bold: true),
              _protocolCell('Метрика', flex: 3, bold: true),
              _protocolCell('Комментарий', flex: 5, bold: true),
            ],
          ),
        ),
        ...stages.asMap().entries.map((entry) {
          final i = entry.key;
          final stage = entry.value;
          return Container(
            color: i.isEven ? Colors.white : const Color(0xFFF5F8FB),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _protocolCell(stage.name, flex: 3),
                _protocolCell(stage.status, flex: 2),
                _protocolCell(stage.metric, flex: 3),
                _protocolCell(stage.comment, flex: 5),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _protocolCell(String text, {int flex = 1, bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppTheme.border)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            height: 1.25,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _calibrationWorkbench() {
    if (_refImg == null || _cmpImg == null) {
      return const SizedBox.shrink();
    }
    final title = _calStep == 1
        ? 'Калибровка: точки на эталоне'
        : _calStep == 2
            ? 'Калибровка: точки на образце'
            : 'Калибровка: расчёт совмещения';
    final message = _calStep == 1
        ? 'Поставьте $_minAnchorPts-$_maxAnchorPts одинаковых контрольных точек на эталоне. Точка мягко притягивается к ближайшему ч/б контрасту.'
        : _calStep == 2
            ? 'Поставьте те же ${_tempRefPts.length} точек на образце в том же порядке. Магнит работает только рядом с кликом, без дальнего прыжка.'
            : 'OpenCV рассчитывает гомографию и проверяет качество совмещения.';

    return _xpWindow(
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolBtn(Icons.undo, 'Убрать последнюю точку',
              _calStep == 1 || _calStep == 2 ? _undoLastPoint : null),
          _toolBtn(Icons.close, 'Отмена', _cancelCalibration, danger: true),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _calibrationBanner(message),
          const SizedBox(height: 8),
          _calibrationControls(),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (_, constraints) {
            final panelWidth = constraints.maxWidth;
            final viewportHeight = MediaQuery.sizeOf(context).height;
            final panelHeight = (viewportHeight - 245).clamp(460.0, 980.0);
            if (_calStep == 2) {
              return _calibrationPointPanel(
                label: 'Образец - ставьте точки',
                bytes: _cmpImg!,
                imgSize: _cmpImgSize,
                anchorPts: _cmpAnchorPts,
                ctrl: _cmpAlignCtrl,
                availableWidth: panelWidth,
                panelHeightOverride: panelHeight,
                placing: true,
                tempPts: _tempCmpPts,
                onTap: _addPanelPoint,
                onUndo: _undoLastPoint,
                minPts:
                    _tempRefPts.isEmpty ? _minAnchorPts : _tempRefPts.length,
              );
            }
            if (_calStep == 3) {
              return const SizedBox.shrink();
            }
            return _calibrationPointPanel(
              label: 'Эталон - ставьте точки',
              bytes: _refImg!,
              imgSize: _refImgSize,
              anchorPts: _refAnchorPts,
              ctrl: _refAlignCtrl,
              availableWidth: panelWidth,
              panelHeightOverride: panelHeight,
              placing: true,
              tempPts: _tempRefPts,
              onTap: _addPanelPoint,
              onUndo: _undoLastPoint,
              minPts: _minAnchorPts,
            );
          }),
        ]),
      ),
    );
  }

  Widget _calibrationBanner(String message) {
    final color = _calStep == 1
        ? AppTheme.blue
        : _calStep == 2
            ? const Color(0xFF1D6E68)
            : AppTheme.simMid;
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.65)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.control_camera, size: 16, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: TextStyle(fontSize: 11, height: 1.35, color: color),
          ),
        ),
      ]),
    );
  }

  Widget _calibrationControls() {
    if (_calStep == 3) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Расчёт совмещения...', style: TextStyle(fontSize: 12)),
        ]),
      );
    }
    if (_calStep == 1) {
      return _calibrationActionStrip(
        counter: _pointCounter('Эталон', _tempRefPts.length, _minAnchorPts),
        back:
            XpBtn(label: 'Отмена', danger: true, onPressed: _cancelCalibration),
        next: XpBtn(
          label: 'Далее ›',
          primary: true,
          onPressed: _tempRefPts.length >= _minAnchorPts
              ? () => _advanceToStep2()
              : null,
        ),
      );
    }
    return _calibrationActionStrip(
      counter: _pointCounter('Образец', _tempCmpPts.length, _tempRefPts.length),
      back: XpBtn(
        label: '‹ Назад',
        onPressed: () => setState(() {
          _calStep = 1;
          _tempCmpPts = [];
        }),
      ),
      next: XpBtn(
        label: 'Рассчитать ›',
        primary: true,
        onPressed:
            _tempCmpPts.length == _tempRefPts.length && _tempRefPts.isNotEmpty
                ? _runAlignmentFromPoints
                : null,
      ),
    );
  }

  Widget _calibrationActionStrip({
    required Widget counter,
    required Widget back,
    required Widget next,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        border: Border.all(color: const Color(0xFFD6E0EA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          back,
          const Spacer(),
          counter,
          const Spacer(),
          next,
        ],
      ),
    );
  }

  Widget _pointCounter(String label, int count, int required) {
    final ok = count >= required && required > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? AppTheme.simHigh.withOpacity(0.10) : Colors.white,
        border: Border.all(color: ok ? AppTheme.simHigh : AppTheme.silverDark),
      ),
      child: Text(
        '$label: $count / $required точек',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: ok ? AppTheme.simHigh : Colors.black87,
        ),
      ),
    );
  }

  Widget _calibrationPointPanel({
    required String label,
    required Uint8List bytes,
    required Size? imgSize,
    required List<Offset>? anchorPts,
    required TransformationController ctrl,
    required double availableWidth,
    double? panelHeightOverride,
    bool placing = false,
    List<Offset> tempPts = const [],
    void Function(Offset)? onTap,
    VoidCallback? onUndo,
    int minPts = 4,
  }) {
    final imageSize = imgSize;
    final panelHeight =
        panelHeightOverride ?? (availableWidth * 9 / 16).clamp(280.0, 520.0);

    Rect imageRect(Size boxSize) {
      if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
        return Offset.zero & boxSize;
      }
      final scale = min(
        boxSize.width / imageSize.width,
        boxSize.height / imageSize.height,
      );
      final w = imageSize.width * scale;
      final h = imageSize.height * scale;
      return Rect.fromLTWH(
        (boxSize.width - w) / 2,
        (boxSize.height - h) / 2,
        w,
        h,
      );
    }

    Offset? toImagePoint(Offset local, Size boxSize) {
      if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
        return null;
      }
      final rect = imageRect(boxSize);
      if (!rect.contains(local)) return null;
      final x = (local.dx - rect.left) / rect.width * imageSize.width;
      final y = (local.dy - rect.top) / rect.height * imageSize.height;
      return Offset(x, y);
    }

    List<Widget> pointWidgets(Size boxSize, List<Offset> points, Color color) {
      if (imageSize == null) return [];
      final rect = imageRect(boxSize);
      return points.asMap().entries.map((entry) {
        final p = entry.value;
        final x = rect.left + p.dx / imageSize.width * rect.width;
        final y = rect.top + p.dy / imageSize.height * rect.height;
        return Positioned.fill(
          child: _AnchorPointMarker(
            ctrl: ctrl,
            x: x,
            y: y,
            index: entry.key + 1,
            color: color,
          ),
        );
      }).toList();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: placing ? AppTheme.blue : AppTheme.blueDark,
        child: Row(children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (placing)
            Text(
              '${tempPts.length} / $minPts',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
        ]),
      ),
      LayoutBuilder(builder: (_, constraints) {
        final boxSize = Size(constraints.maxWidth, panelHeight);
        return Container(
          height: panelHeight,
          color: const Color(0xFF101216),
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: ctrl,
              boundaryMargin: const EdgeInsets.all(80),
              minScale: 0.8,
              maxScale: 10.0,
              panEnabled: _ctrlHeld,
              scaleEnabled: _ctrlHeld,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onTap == null
                    ? null
                    : (details) {
                        final p = toImagePoint(details.localPosition, boxSize);
                        if (p != null) onTap(p);
                      },
                child: SizedBox(
                  width: boxSize.width,
                  height: boxSize.height,
                  child: Stack(children: [
                    Positioned.fill(
                      child: _uiImage(bytes, fit: BoxFit.contain),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ImageBoundsPainter(imageRect(boxSize)),
                        ),
                      ),
                    ),
                    ...pointWidgets(boxSize, anchorPts ?? [], Colors.red),
                    ...pointWidgets(boxSize, tempPts, Colors.amber),
                    if (placing)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppTheme.blueLight,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
      Container(
        color: const Color(0xFFE7E8E4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Row(children: [
          Expanded(
            child: Text(
              placing
                  ? _anchorRefining
                      ? 'Ищу ближайший ч/б контраст рядом с кликом...'
                      : _calibrationSettings.loupeEnabled
                          ? 'Клик - открыть лупу. В лупе поставьте точную точку. Ctrl+скролл/драг - зум и сдвиг.'
                          : 'Клик - точка без лупы. Ctrl+скролл/драг - зум и сдвиг.'
                  : 'Ctrl+скролл/драг - зум и перемещение.',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
          if (placing) ...[
            _ZoomBtn(label: '−', onTap: () => _zoomCalibration(ctrl, 0.77)),
            const SizedBox(width: 4),
            _ZoomBtn(label: '+', onTap: () => _zoomCalibration(ctrl, 1.3)),
            const SizedBox(width: 4),
            _ZoomBtn(label: '⊡', onTap: () => ctrl.value = Matrix4.identity()),
            const SizedBox(width: 6),
            XpBtn(
              label: 'Убрать',
              onPressed: tempPts.isNotEmpty ? onUndo : null,
            ),
          ],
        ]),
      ),
    ]);
  }

  void _zoomCalibration(TransformationController ctrl, double factor) {
    final m = ctrl.value.clone();
    m.scale(factor, factor);
    final s = m.getMaxScaleOnAxis();
    if (s < 0.8 || s > 10.0) return;
    ctrl.value = m;
  }

  Widget _resultSummaryBar(CompareResult r) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.simColor(r.score).withOpacity(0.08),
        border: Border.all(color: AppTheme.simColor(r.score).withOpacity(0.45)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _metricChip('Сходство', '${r.score.toStringAsFixed(1)}%'),
          _metricChip('Отличия', '${r.diffPercent.toStringAsFixed(1)}%'),
          if (r.maxDeltaE != null)
            _metricChip('Макс. ΔE', r.maxDeltaE!.toStringAsFixed(1)),
          if (r.defectZoneCount != null)
            _metricChip('Зоны', '${r.defectZoneCount}'),
          if (r.labScore != null)
            _metricChip('Lab', '${r.labScore!.toStringAsFixed(1)}%'),
          _metricChip('Размер эталона', r.refSize),
          _metricChip('Размер образца', r.cmpSize),
        ],
      ),
    );
  }

  Widget _inspectorPanel({bool compact = false}) {
    final r = _result;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE3E5E1),
        border: Border(left: BorderSide(color: Color(0xFF8C929C))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _railHeader('Инспектор'),
            const SizedBox(height: 8),
            _inspectorStatusCard(),
            const SizedBox(height: 8),
            _jobInspectorSection(),
            const SizedBox(height: 8),
            _referenceProfilesInspector(),
            const SizedBox(height: 8),
            _inspectorSection('Порядок действий', [
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: '2. Загрузить эталон',
                  icon: Icons.upload_file,
                  primary: _refImg == null,
                  onPressed: _imageBusy ? null : () => _pickImage(true),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: '3. Рамка эталона',
                  icon: Icons.crop,
                  onPressed: _refImg != null && !_imageBusy
                      ? () => _cropImage(true)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: '4. Загрузить отпечаток',
                  icon: Icons.add_a_photo,
                  primary: _refImg != null && _cmpImg == null,
                  onPressed: _imageBusy ? null : () => _pickImage(false),
                ),
              ),
              if (_cmpImg != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: XpBtn(
                    label: 'Новый отпечаток',
                    icon: Icons.note_add,
                    onPressed: _imageBusy ? null : _newSample,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: '5. Рамка отпечатка',
                  icon: Icons.crop,
                  onPressed: _cmpImg != null && !_imageBusy
                      ? () => _cropImage(false)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: '6. Калибровочные точки',
                  icon: Icons.tune,
                  primary: _refImg != null &&
                      _cmpImg != null &&
                      _layoutProfile == null,
                  onPressed: _refImg != null && _cmpImg != null && !_imageBusy
                      ? () => _startCalibration()
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: _comparing
                      ? '7. Сравнение...'
                      : _canCalculateAndCompare
                          ? '7. Рассчитать и сравнить'
                          : '7. Сравнить',
                  icon: Icons.compare,
                  primary: _canStartCompareAction,
                  onPressed:
                      _canStartCompareAction && !_comparing && !_imageBusy
                          ? _runCompare
                          : null,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: XpBtn(
                  label: _aiLoading ? '8. AI анализ...' : '8. AI анализ',
                  icon: Icons.auto_awesome,
                  onPressed: _refImg != null && _cmpImg != null && !_aiLoading
                      ? _runAiAnalysis
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _inspectorSection('Файлы', [
              _checkRow(
                'Эталон',
                _refImg != null ? 'готов' : 'не загружен',
                _refImg != null,
              ),
              _checkRow(
                'Отпечаток',
                _cmpImg != null ? 'готов' : 'не загружен',
                _cmpImg != null,
              ),
              _checkRow(
                'Профиль точек',
                _layoutProfile?.name ?? 'не выбран',
                _layoutProfile != null,
              ),
            ]),
            if (_calStep != 0) ...[
              const SizedBox(height: 8),
              _calibrationInspector(),
            ],
            if (r != null) ...[
              const SizedBox(height: 8),
              _inspectorSection('Метрики', [
                _metricLine('MAE', '${r.similarity.toStringAsFixed(1)}%'),
                if (r.labScore != null)
                  _metricLine(
                    'Lab score',
                    '${r.labScore!.toStringAsFixed(1)}%',
                  ),
                _metricLine('Отличий', '${r.diffPixels} px'),
                if (r.shiftDL != null || r.shiftDA != null)
                  _metricLine(
                    'Цвет',
                    _colorComment(r.shiftDL, r.shiftDA, r.shiftDB),
                  ),
              ]),
              const SizedBox(height: 8),
              _levelConclusionsSection(r),
              const SizedBox(height: 8),
              _technicalConclusionSection(r),
            ],
            const SizedBox(height: 8),
            _inspectorSection('OCR и коды', [
              _checkRow(
                'OCR',
                _textDiff == null
                    ? 'нет данных'
                    : '${_textDiff!.similarity.toStringAsFixed(0)}%',
                _textDiff != null,
              ),
              _checkRow(
                'Штрихкоды',
                _barcodeMatchPct() == null
                    ? 'не обнаружены'
                    : '${_barcodeMatchPct()!.toStringAsFixed(0)}%',
                _barcodeMatchPct() != null,
              ),
            ]),
            const SizedBox(height: 8),
            _aiInspectorSection(),
          ],
        ),
      ),
    );
  }

  Widget _inspectorStatusCard() {
    final r = _result;
    final status = r == null ? 'ОЖИДАНИЕ' : _shortStatus(r.score);
    final color = r == null ? AppTheme.blueDark : AppTheme.simColor(r.score);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color, width: 2),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 18,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r == null
                ? 'Загрузите эталон и образец, затем запустите сравнение.'
                : 'Сходство ${r.score.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _jobInspectorSection() {
    final hasJob = _currentJobNumber.isNotEmpty;
    return _inspectorSection('Работа', [
      XpInput(
        placeholder: 'Номер работы / заказа',
        controller: _jobNumberCtrl,
        keyboardType: TextInputType.text,
        onChanged: (value) {
          final next = value.trim();
          setState(() {
            _jobNumber = next;
            _sampleNo = _nextSampleNumberFor(
              referenceId: _activeReferenceId,
              referenceLabel: _savedRefLabel,
            );
          });
        },
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _jobInfoTile(
              'Работа',
              hasJob ? _currentJobNumber : 'не задана',
              hasJob,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _jobInfoTile(
              'Отпечаток',
              _currentSampleLabel,
              _cmpImg != null,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _jobInfoTile('ID для базы', _currentJobId, hasJob),
    ]);
  }

  Widget _jobInfoTile(String label, String value, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF6FC) : Colors.white,
        border: Border.all(
          color: active ? AppTheme.blue : AppTheme.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        ),
      ]),
    );
  }

  Widget _referenceProfilesInspector() {
    if (_savedReferences.isEmpty) {
      return _inspectorSection('Эталоны', [
        const Text(
          'Сохранённых эталонов пока нет. После калибровки профиль появится здесь.',
          style: TextStyle(fontSize: 11, height: 1.35, color: Colors.black54),
        ),
      ]);
    }
    return _inspectorSection('Эталоны', [
      ..._savedReferences.take(6).map((item) {
        final selected = item.id == _activeReferenceId;
        final points = item.layoutProfile?.refAnchors.length ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => _activateSavedReference(item),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFEAF6FC) : Colors.white,
                border: Border.all(
                  color: selected ? AppTheme.blue : AppTheme.border,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.image,
                  size: 16,
                  color: selected ? AppTheme.blue : Colors.black54,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        points == 0 ? 'точки не сохранены' : '$points точек',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _calibrationInspector() {
    final text = _calStep == 1
        ? 'Эталон: ${_tempRefPts.length} / $_minAnchorPts точек'
        : _calStep == 2
            ? 'Образец: ${_tempCmpPts.length} / ${_tempRefPts.length} точек'
            : 'Расчёт совмещения...';
    return _inspectorSection('Точки', [
      Text(text, style: const TextStyle(fontSize: 11, height: 1.35)),
      const SizedBox(height: 6),
      Text(
        _calStep == 1
            ? 'Кнопка «Далее» находится между эталоном и образцом.'
            : _calStep == 2
                ? 'Кнопка «Рассчитать» находится между эталоном и образцом.'
                : 'Идёт расчёт совмещения.',
        style: const TextStyle(fontSize: 11, color: Colors.black54),
      ),
    ]);
  }

  Widget _aiInspectorSection() {
    if (_aiLoading) {
      return _inspectorSection('AI анализ', const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('AI анализирует изображения...',
                style: TextStyle(fontSize: 11)),
          ]),
        ),
      ]);
    }

    final ai = _aiResult;
    if (ai == null) {
      return _inspectorSection('AI анализ', [
        const Text(
          'AI-отчёт появится здесь: краткий вывод, найденные проблемы печати и рекомендации.',
          style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        XpBtn(
          label: 'Запустить AI',
          primary: true,
          onPressed: _refImg != null && _cmpImg != null ? _runAiAnalysis : null,
        ),
      ]);
    }

    return _inspectorSection('AI анализ', [
      _aiVerdictBadge(ai),
      if (ai.summary.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(ai.summary, style: const TextStyle(fontSize: 11, height: 1.45)),
      ],
      if (ai.issues.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...ai.issues.take(4).map(_aiIssueTile),
      ],
      if (ai.recommendations.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text(
          'Рекомендации',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ...ai.recommendations.take(4).map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 11, height: 1.35),
                        ),
                      ),
                    ]),
              ),
            ),
      ],
      const SizedBox(height: 8),
      XpBtn(label: 'Повторить AI', onPressed: _runAiAnalysis),
    ]);
  }

  Widget _technicalConclusionSection(CompareResult r) {
    final shift = _layoutProfile?.reprojError;
    final defectZones = r.defectZoneCount ?? 0;
    final maxDe = r.maxDeltaE;
    final meanDe = r.meanDeltaE;
    final defectArea = r.defectAreaPercent;
    return _inspectorSection('Техническое заключение', [
      _verdictBanner(_technicalVerdict(r, shift)),
      const SizedBox(height: 6),
      _metricLine(
        'Макс. ΔE',
        maxDe == null ? 'нет данных' : maxDe.toStringAsFixed(1),
      ),
      _metricLine(
        'Среднее ΔE',
        meanDe == null ? 'нет данных' : meanDe.toStringAsFixed(1),
      ),
      _metricLine(
        'Пятна/зоны',
        defectZones == 0
            ? 'не обнаружены'
            : '$defectZones зон${defectArea == null ? '' : ' · ${defectArea.toStringAsFixed(1)}%'}',
      ),
      _metricLine(
        'Смещение',
        shift == null ? 'нет профиля' : '${shift.toStringAsFixed(1)} px',
      ),
      _metricLine('Цвет', _colorComment(r.shiftDL, r.shiftDA, r.shiftDB)),
    ]);
  }

  Widget _levelConclusionsSection(CompareResult r) {
    final items = _levelConclusions(r);
    return _inspectorSection(
      'Заключение по уровням',
      [
        for (final item in items) ...[
          _levelConclusionTile(item),
          if (item != items.last) const SizedBox(height: 6),
        ],
      ],
    );
  }

  List<_LevelConclusion> _levelConclusions(CompareResult r) {
    return [
      _backgroundConclusion(r),
      _detailConclusion(r),
      _precisionConclusion(r),
    ];
  }

  _LevelConclusion _backgroundConclusion(CompareResult r) {
    final meanDe = _meanOf(r.labLevel1) ?? _meanOf(r.labLevel0) ?? r.meanDeltaE;
    final maxDe =
        _maxNullable(_maxOf(r.labLevel1), _maxOf(r.labLevel0)) ?? r.maxDeltaE;
    final colorShift = (r.shiftDL?.abs() ?? 0) > 2 ||
        (r.shiftDA?.abs() ?? 0) > 3 ||
        (r.shiftDB?.abs() ?? 0) > 3;
    final status = (meanDe ?? 0) >= 9 || (maxDe ?? 0) >= 18
        ? 'Критично'
        : (meanDe ?? 0) >= 3 || (maxDe ?? 0) >= 6 || colorShift
            ? 'Проверить'
            : 'OK';
    final metric = _deMetric(meanDe, maxDe);
    final message = status == 'OK'
        ? 'Фон и общий тон стабильны.'
        : 'Есть общий сдвиг фона/тона: ${_colorComment(r.shiftDL, r.shiftDA, r.shiftDB)}.';
    return _LevelConclusion(
      key: 'background',
      title: 'Фон и общий тон',
      status: status,
      message: message,
      metric: metric,
    );
  }

  _LevelConclusion _detailConclusion(CompareResult r) {
    final meanDe = _meanOf(r.labLevel2) ?? _meanOf(r.labLevel3) ?? r.meanDeltaE;
    final maxDe = _maxOf(r.labLevel2) ?? _maxOf(r.labLevel3) ?? r.maxDeltaE;
    final zones = _countAbove(r.labLevel2, 6.0) ??
        _countAbove(r.labLevel3, 6.0) ??
        r.defectZoneCount ??
        0;
    final status = (meanDe ?? 0) >= 9 || (maxDe ?? 0) >= 18 || zones >= 24
        ? 'Критично'
        : (meanDe ?? 0) >= 3 || (maxDe ?? 0) >= 6 || zones > 0
            ? 'Проверить'
            : 'OK';
    final message = status == 'OK'
        ? 'Детали изображения, предметы и тон объектов совпадают.'
        : 'Есть отклонения в деталях: $zones зон выше ΔE 6.';
    return _LevelConclusion(
      key: 'details',
      title: 'Детали изображения',
      status: status,
      message: message,
      metric: _deMetric(meanDe, maxDe),
    );
  }

  _LevelConclusion _precisionConclusion(CompareResult r) {
    final maxDe = r.maxDeltaE;
    final zones = r.defectZoneCount ?? 0;
    final area = r.defectAreaPercent ?? 0;
    final status = (maxDe ?? 0) >= 18 || zones >= 36 || area >= 8
        ? 'Критично'
        : (maxDe ?? 0) >= 6 || zones > 0 || area >= 0.5
            ? 'Проверить'
            : 'OK';
    final message = status == 'OK'
        ? 'Точки, мусор и мелкие локальные дефекты не обнаружены.'
        : 'Обнаружены мелкие локальные дефекты: $zones зон, ${area.toStringAsFixed(1)}% площади.';
    return _LevelConclusion(
      key: 'precision',
      title: 'Точки и мусор',
      status: status,
      message: message,
      metric: maxDe == null
          ? 'нет ΔE'
          : 'max ΔE ${maxDe.toStringAsFixed(1)} · ${area.toStringAsFixed(1)}%',
    );
  }

  Widget _levelConclusionTile(_LevelConclusion item) {
    final color = _statusColor(item.status);
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              item.status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              item.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        const SizedBox(height: 5),
        Text(item.message, style: const TextStyle(fontSize: 11, height: 1.35)),
        const SizedBox(height: 3),
        Text(
          item.metric,
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ]),
    );
  }

  Color _statusColor(String status) {
    return status == 'Критично'
        ? AppTheme.simLow
        : status == 'Проверить' || status == 'Контроль'
            ? AppTheme.simMid
            : AppTheme.simHigh;
  }

  double? _maxNullable(double? a, double? b) {
    if (a == null) return b;
    if (b == null) return a;
    return max(a, b);
  }

  String _deMetric(double? meanDe, double? maxDe) {
    final mean = meanDe == null ? 'нет' : meanDe.toStringAsFixed(1);
    final maxValue = maxDe == null ? 'нет' : maxDe.toStringAsFixed(1);
    return 'среднее ΔE $mean · max ΔE $maxValue';
  }

  Widget _verdictBanner(String text) {
    final lower = text.toLowerCase();
    final color = lower.contains('крит')
        ? AppTheme.simLow
        : lower.contains('вним')
            ? AppTheme.simMid
            : AppTheme.simHigh;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _technicalVerdict(CompareResult r, double? shiftPx) {
    final maxDe = r.maxDeltaE ?? 0;
    final meanDe = r.meanDeltaE ?? 0;
    final defectZones = r.defectZoneCount ?? 0;
    final shift = shiftPx ?? 0;
    if (maxDe >= 18 || meanDe >= 9 || defectZones >= 36 || shift >= 6) {
      return 'Критичные отклонения: требуется остановить и проверить макет, совмещение и печать.';
    }
    if (maxDe >= 6 || meanDe >= 3 || defectZones > 0 || shift >= 2) {
      return 'Есть отклонения: проверьте подсвеченные зоны и решите по допускам тиража.';
    }
    return 'Существенных отклонений не обнаружено.';
  }

  Widget _inspectorSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAF7),
        border: Border.all(color: AppTheme.silverDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 7),
          ...children,
        ],
      ),
    );
  }

  Widget _checkRow(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: ok ? AppTheme.simHigh : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: ok ? Colors.black87 : Colors.black45,
                fontWeight: ok ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.silverDark),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _xpWindow({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.silver,
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
            decoration: const BoxDecoration(gradient: AppTheme.blueGrad),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _toolBtn(
    IconData icon,
    String tip,
    VoidCallback? onTap, {
    bool primary = false,
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final bg = danger
        ? const Color(0xFFB4232A)
        : primary
            ? const Color(0xFF2563EB)
            : const Color(0xFFF8FAFC);
    final border = danger
        ? const Color(0xFF7F1D1D)
        : primary
            ? const Color(0xFF1D4ED8)
            : const Color(0xFFCBD5E1);
    final fg = primary || danger ? Colors.white : const Color(0xFF1F2937);
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Container(
            width: 34,
            height: 32,
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x260F172A),
                  blurRadius: 7,
                  offset: Offset(0, 3),
                ),
                BoxShadow(
                  color: Color(0x55FFFFFF),
                  blurRadius: 1,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Icon(icon, size: 18, color: fg),
          ),
        ),
      ),
    );
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
                foregroundColor: active ? Colors.black : Colors.black54,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
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
      child: Column(
        children: [
          // ── Эталон 1 ─────────────────────────────────
          XpGroup(
            label: 'Эталон 1',
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _pickImage(true),
                  onDoubleTap:
                      _refImg != null ? () => _openFullScreen(_refImg!) : null,
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.black,
                    child: _stacking
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 8),
                                Text(
                                  'Объединение снимков...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _refImg != null
                            ? _uiImage(_refImg!, fit: BoxFit.contain)
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('🖼️', style: TextStyle(fontSize: 40)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Нажмите для выбора',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  Text(
                                    'JPEG, PNG, TIFF, RAW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),

          if (_savedRefLabel != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.simHigh.withOpacity(0.08),
                border: Border.all(color: AppTheme.simHigh.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Text('💾', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Сохранён: $_savedRefLabel',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.simHigh,
                      ),
                    ),
                  ),
                  XpBtn(
                    label: '🗑 Сбросить',
                    danger: true,
                    onPressed: _clearReference,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: XpBtn(
                  label: '💾 Сохранить эталон',
                  primary: true,
                  onPressed: _refImg != null ? _saveReference : null,
                ),
              ),
              const SizedBox(width: 6),
              XpBtn(
                label: '✂ Рамка',
                onPressed: _refImg != null ? () => _cropImage(true) : null,
              ),
            ],
          ),

          // ── Эталон 2 ─────────────────────────────────
          const SizedBox(height: 8),
          XpCollapsible(
            title: 'Эталон 2 (Склейка кадров)',
            child: XpGroup(
              label: 'Эталон 2',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_refImg == null) ...[
                    const Text(
                      'Сначала загрузите Эталон 1.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
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
                            Text(
                              'Нажмите для выбора второго снимка',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white54,
                              ),
                            ),
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
                        child: LayoutBuilder(
                          builder: (_, c) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _overlayViewerSize = Size(
                                c.maxWidth,
                                c.maxHeight,
                              );
                            });
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                RepaintBoundary(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _uiImage(
                                        _refImg!,
                                        fit: BoxFit.contain,
                                      ),
                                      Opacity(
                                        opacity: _overlayOpacity,
                                        child: InteractiveViewer(
                                          transformationController:
                                              _overlayCtrl,
                                          boundaryMargin: const EdgeInsets.all(
                                            double.infinity,
                                          ),
                                          minScale: 0.1,
                                          maxScale: 6.0,
                                          child: _uiImage(
                                            _ref2Img!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const IgnorePointer(
                                  child: CustomPaint(
                                    painter: _FramePainter(0.12),
                                  ),
                                ),
                                const Positioned(
                                  left: 8,
                                  top: 8,
                                  child: _ImgLabel('Эталон 1'),
                                ),
                                const Positioned(
                                  right: 8,
                                  top: 8,
                                  child: _ImgLabel('Эталон 2 ↕↔'),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Резкость как справочная информация
                    if (_ref1Sharpness != null && _ref2Sharpness != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Резкость 1: ${_ref1Sharpness!.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _ref1Sharpness! >= _ref2Sharpness!
                                      ? AppTheme.simHigh
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Резкость 2: ${_ref2Sharpness!.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _ref2Sharpness! > _ref1Sharpness!
                                      ? AppTheme.simHigh
                                      : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        const SizedBox(
                          width: 90,
                          child: Text(
                            'Прозрачность:',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _overlayOpacity,
                            onChanged: (v) =>
                                setState(() => _overlayOpacity = v),
                            activeColor: AppTheme.blue,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(_overlayOpacity * 100).round()}%',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        XpBtn(
                          label: '🗑 Убрать',
                          danger: true,
                          onPressed: () => setState(() {
                            _ref2Img = null;
                            _overlayCtrl.value = Matrix4.identity();
                          }),
                        ),
                        const Spacer(),
                        XpBtn(
                          label: _stacking
                              ? '⏳ Обработка...'
                              : '🔀 Склейка кадров',
                          primary: true,
                          onPressed: _stacking
                              ? null
                              : () => _selectRef(_refImg!, _ref2Img),
                        ),
                      ],
                    ),
                  ],

                  // AI анализ эталона
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 6),
                  if (_refAiLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'AI анализирует эталон...',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_refAiResult != null) ...[
                    _aiVerdictBadge(_refAiResult!),
                    const SizedBox(height: 6),
                    if (_refAiResult!.recommendations.isNotEmpty)
                      ..._refAiResult!.recommendations.map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(fontSize: 11)),
                              Expanded(
                                child: Text(
                                  r,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    XpBtn(
                      label: '🔄 Повторить AI анализ',
                      onPressed: _analyzeReferenceWithAi,
                    ),
                  ] else
                    XpBtn(
                      label: '🤖 AI анализ качества эталона',
                      onPressed:
                          _refImg != null ? _analyzeReferenceWithAi : null,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              XpBtn(
                label: 'Далее ›',
                primary: true,
                onPressed: () => _tabs.animateTo(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Таб: Образец ─────────────────────────────────
  Widget _tabCmp() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // ── Образец 1 ────────────────────────────────
          XpGroup(
            label: 'Образец 1',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: () => _pickImage(false),
                  onDoubleTap:
                      _cmpImg != null ? () => _openFullScreen(_cmpImg!) : null,
                  child: Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.black,
                    child: _stacking
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 8),
                                Text(
                                  'Объединение снимков...',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _cmpImg != null
                            ? _uiImage(_cmpImg!, fit: BoxFit.contain)
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('📷', style: TextStyle(fontSize: 40)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Нажмите для выбора',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  Text(
                                    'JPEG, PNG, TIFF, RAW',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),

                // Образец 2 — для объединения
                if (_cmpImg != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      XpBtn(
                        label: '✂ Рамка',
                        onPressed: () => _cropImage(false),
                      ),
                    ],
                  ),
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
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('📷', style: TextStyle(fontSize: 30)),
                                  SizedBox(height: 6),
                                  Text(
                                    'Нажмите для второго снимка',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ClipRect(
                                child: Container(
                                  height: 260,
                                  color: Colors.black,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _uiImage(
                                        _cmpImg!,
                                        fit: BoxFit.contain,
                                      ),
                                      Opacity(
                                        opacity: _cmp2Opacity,
                                        child: InteractiveViewer(
                                          transformationController: _cmp2Ctrl,
                                          boundaryMargin: const EdgeInsets.all(
                                            double.infinity,
                                          ),
                                          minScale: 0.1,
                                          maxScale: 6.0,
                                          child: _uiImage(
                                            _cmp2Img!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      const IgnorePointer(
                                        child: CustomPaint(
                                          painter: _FramePainter(0.12),
                                        ),
                                      ),
                                      const Positioned(
                                        left: 8,
                                        top: 8,
                                        child: _ImgLabel('Образец 1'),
                                      ),
                                      const Positioned(
                                        right: 8,
                                        top: 8,
                                        child: _ImgLabel('Образец 2 ↕↔'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_cmp1Sharpness != null &&
                                  _cmp2Sharpness != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Резкость 1: ${_cmp1Sharpness!.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _cmp1Sharpness! >=
                                                    _cmp2Sharpness!
                                                ? AppTheme.simHigh
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'Резкость 2: ${_cmp2Sharpness!.toStringAsFixed(0)}',
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _cmp2Sharpness! >
                                                    _cmp1Sharpness!
                                                ? AppTheme.simHigh
                                                : Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 90,
                                    child: Text(
                                      'Прозрачность:',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _cmp2Opacity,
                                      onChanged: (v) =>
                                          setState(() => _cmp2Opacity = v),
                                      activeColor: AppTheme.blue,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 36,
                                    child: Text(
                                      '${(_cmp2Opacity * 100).round()}%',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  XpBtn(
                                    label: '🗑 Убрать',
                                    danger: true,
                                    onPressed: () => setState(() {
                                      _cmp2Img = null;
                                      _cmp2Ctrl.value = Matrix4.identity();
                                      _cmp1Sharpness = null;
                                      _cmp2Sharpness = null;
                                    }),
                                  ),
                                  const Spacer(),
                                  XpBtn(
                                    label: _stacking
                                        ? '⏳ Обработка...'
                                        : '🔀 Склейка кадров',
                                    primary: true,
                                    onPressed: _stacking
                                        ? null
                                        : () => _selectCmp(_cmpImg!, _cmp2Img),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              XpBtn(label: '‹ Эталон', onPressed: () => _tabs.animateTo(0)),
              XpBtn(
                label: 'Далее ›',
                primary: true,
                onPressed: _refImg != null && _cmpImg != null
                    ? () => _tabs.animateTo(2)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Таб: Совмещение ───────────────────────────────
  Widget _tabAlign() {
    if (_refImg == null || _cmpImg == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            const Text(
              'Сначала загрузите эталон и образец',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            XpBtn(label: '‹ Образец', onPressed: () => _tabs.animateTo(1)),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // ── Два окна предпросмотра ─────────────────────
          LayoutBuilder(
            builder: (_, constraints) {
              final wide = constraints.maxWidth > 480;
              final panels = [
                _alignPanel(
                  label: 'Эталон',
                  bytes: _refImg!,
                  imgSize: _refImgSize,
                  anchorPts: _refAnchorPts,
                  ctrl: _refAlignCtrl,
                  availableWidth: wide
                      ? (constraints.maxWidth - 8) / 2
                      : constraints.maxWidth,
                  placing: _calStep == 1,
                  tempPts: _tempRefPts,
                  onTap: _calStep == 1 ? _addPanelPoint : null,
                  onUndo: _calStep == 1 ? _undoLastPoint : null,
                  minPts: _minAnchorPts,
                ),
                _alignPanel(
                  label: 'Образец',
                  bytes: _cmpAligned ?? _cmpImg!,
                  imgSize: _cmpImgSize,
                  anchorPts: _cmpAnchorPts,
                  ctrl: _cmpAlignCtrl,
                  availableWidth: wide
                      ? (constraints.maxWidth - 8) / 2
                      : constraints.maxWidth,
                  placing: _calStep == 2,
                  tempPts: _tempCmpPts,
                  onTap: _calStep == 2 ? _addPanelPoint : null,
                  onUndo: _calStep == 2 ? _undoLastPoint : null,
                  minPts: _minAnchorPts,
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
              return Column(
                children: [panels[0], const SizedBox(height: 8), panels[1]],
              );
            },
          ),

          const SizedBox(height: 12),
          // ── Инструкция / Статус профиля ───────────────
          if (_calStep == 0 && _layoutProfile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Профиль: ${_layoutProfile!.name}  ·  ош. ${_layoutProfile!.reprojError.toStringAsFixed(1)} пкс',
                      style: const TextStyle(fontSize: 11, color: Colors.green),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _layoutProfile = null;
                      _cmpAligned = null;
                      _refAnchorPts = null;
                      _cmpAnchorPts = null;
                    }),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '✕',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
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
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Нажмите «🔧 Калибровка» и расставьте точки на эталоне и образце.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
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
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Шаг 1 / 2 — ЭТАЛОН: нажмите $_minAnchorPts–$_maxAnchorPts точек  (${_tempRefPts.length} из $_minAnchorPts мин.)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
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
                child: Row(
                  children: [
                    const Icon(Icons.touch_app, size: 16, color: Colors.teal),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Шаг 2 / 2 — ОБРАЗЕЦ: те же ${_tempRefPts.length} точек в том же порядке  (${_tempCmpPts.length} / ${_tempRefPts.length})',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_calStep == 3)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Расчёт совмещения...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          const Divider(),
          if (_calStep == 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                XpBtn(label: '‹ Образец', onPressed: () => _tabs.animateTo(1)),
                Row(
                  children: [
                    XpBtn(
                      label: '🔧 Калибровка',
                      primary: _layoutProfile == null,
                      onPressed: () => _startCalibration(),
                    ),
                    const SizedBox(width: 8),
                    if (_result != null) ...[
                      SimBadge(value: _result!.score),
                      const SizedBox(width: 8),
                    ],
                    _comparing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : XpBtn(
                            label: 'Сравнить ›',
                            primary: true,
                            onPressed:
                                _canStartCompareAction ? _runCompare : null,
                          ),
                  ],
                ),
              ],
            )
          else if (_calStep == 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                XpBtn(
                  label: 'Отмена',
                  danger: true,
                  onPressed: _cancelCalibration,
                ),
                XpBtn(
                  label: 'Далее ›',
                  primary: true,
                  onPressed: _tempRefPts.length >= _minAnchorPts
                      ? () => _advanceToStep2()
                      : null,
                ),
              ],
            )
          else if (_calStep == 2)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                XpBtn(
                  label: '← Назад',
                  onPressed: () => setState(() {
                    _calStep = 1;
                    _tempCmpPts = [];
                  }),
                ),
                XpBtn(
                  label: 'Рассчитать →',
                  primary: true,
                  onPressed: _tempCmpPts.length == _tempRefPts.length &&
                          _tempRefPts.isNotEmpty
                      ? _runAlignmentFromPoints
                      : null,
                ),
              ],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
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
    VoidCallback? onUndo,
    int minPts = 4,
  }) {
    // Вычисляем высоту контейнера по аспекту изображения (без чёрных полос)
    double panelHeight = 220;
    if (imgSize != null && imgSize.width > 0 && imgSize.height > 0) {
      panelHeight = (availableWidth * imgSize.height / imgSize.width).clamp(
        120.0,
        340.0,
      );
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
      final ratio = min(
        availableWidth / imgSize.width,
        panelHeight / imgSize.height,
      );
      final offX = (availableWidth - imgSize.width * ratio) / 2;
      final offY = (panelHeight - imgSize.height * ratio) / 2;
      return pts.asMap().entries.map((e) {
        final px = e.value.dx * ratio + offX;
        final py = e.value.dy * ratio + offY;
        return Positioned.fill(
          child: _AnchorPointMarker(
            ctrl: ctrl,
            x: px,
            y: py,
            index: e.key + 1,
            color: color,
          ),
        );
      }).toList();
    }

    final stackContent = Stack(
      children: [
        _uiImage(
          bytes,
          width: availableWidth,
          height: panelHeight,
          fit: BoxFit.contain,
        ),
        ...buildDots(anchorPts ?? [], Colors.red),
        ...buildDots(tempPts, Colors.amber),
        if (placing)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 2),
                ),
              ),
            ),
          ),
      ],
    );

    final viewerChild = onTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (d) {
              if (imgSize == null) return;
              final local = d.localPosition;
              final ratio = min(
                availableWidth / imgSize.width,
                panelHeight / imgSize.height,
              );
              final offX = (availableWidth - imgSize.width * ratio) / 2;
              final offY = (panelHeight - imgSize.height * ratio) / 2;
              final imgX = (local.dx - offX) / ratio;
              final imgY = (local.dy - offY) / ratio;
              if (imgX >= 0 &&
                  imgY >= 0 &&
                  imgX <= imgSize.width &&
                  imgY <= imgSize.height) {
                onTap(Offset(imgX, imgY));
              }
            },
            child: stackContent,
          )
        : stackContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок панели
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: placing ? const Color(0xFF0055BB) : AppTheme.blue,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Область изображения. Зум/панорамирование колесом или драгом —
        // только при зажатом Ctrl, иначе блокируется скролл страницы.
        ClipRect(
          child: SizedBox(
            height: panelHeight,
            child: InteractiveViewer(
              transformationController: ctrl,
              boundaryMargin: const EdgeInsets.all(80),
              minScale: 0.2,
              maxScale: 8.0,
              panEnabled: _ctrlHeld,
              scaleEnabled: _ctrlHeld,
              child: viewerChild,
            ),
          ),
        ),
        // Зум + счётчик точек + ⌫
        Container(
          color: AppTheme.silver,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              _ZoomBtn(label: '−', onTap: () => zoom(0.77)),
              const SizedBox(width: 4),
              _ZoomBtn(label: '+', onTap: () => zoom(1.3)),
              const SizedBox(width: 6),
              _ZoomBtn(
                label: '⊡',
                onTap: () => ctrl.value = Matrix4.identity(),
              ),
              if (!placing) ...[
                const SizedBox(width: 8),
                const Text(
                  'Ctrl+скролл/драг — зум и перемещение',
                  style: TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
              if (placing) ...[
                const Spacer(),
                Text(
                  '${tempPts.length} / $minPts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        tempPts.length >= minPts ? Colors.green : Colors.blue,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: tempPts.isNotEmpty ? onUndo : null,
                  child: Opacity(
                    opacity: tempPts.isNotEmpty ? 1.0 : 0.35,
                    child: Container(
                      width: 26,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: const Text(
                        '⌫',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
              'Загрузите оба фото, расставьте точки (🔧 Калибровка)\n'
              'и нажмите «Сравнить ›» на вкладке Совмещение',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            XpBtn(label: '‹ К совмещению', onPressed: () => _tabs.animateTo(2)),
          ],
        ),
      );
    }

    final r = _result!;
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'РЕЗУЛЬТАТ СРАВНЕНИЯ',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: SimBadge(value: r.score, fontSize: 26)),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                r.labScore != null
                    ? 'Lab: ${r.labScore!.toStringAsFixed(1)}%  ·  MAE: ${r.similarity.toStringAsFixed(1)}%'
                    : 'MAE: ${r.similarity.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              r.score >= 80
                  ? r.score >= 90
                      ? 'Высокая схожесть'
                      : 'Проверить по допускам'
                  : r.score >= 65
                      ? 'Требует проверки'
                      : 'Критичные отклонения',
              style: TextStyle(
                color: AppTheme.simColor(r.score),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_compareStatus != null) ...[
            _compareProgressPanel(),
            const SizedBox(height: 12),
          ],
          XpGroup(
            label: 'Детали',
            child: Table(
              columnWidths: const {
                0: IntrinsicColumnWidth(),
                1: FlexColumnWidth(),
              },
              children: [
                _tableRow('Эталон:', r.refSize),
                _tableRow('Фото:', r.cmpSize),
                _tableRow('Итераций:', '${AppConfig.comparisonIter}'),
                _tableRow(
                  'Отличий:',
                  '${r.diffPixels} px (${r.diffPercent.toStringAsFixed(1)}%)',
                ),
                _tableRow('Дата:', dateStr),
              ],
            ),
          ),
          // ── Анализ цвета (уровень 0 — глобальный) ──
          if (r.shiftDL != null || r.shiftDA != null)
            XpGroup(
              label: 'Цветовой анализ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _colorComment(r.shiftDL, r.shiftDA, r.shiftDB),
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),

          if (r.geometryScore != null)
            XpGroup(
              label: 'Геометрия текста и штрихов',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _geometryVerdict(r),
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _metricChip(
                        'Контуры',
                        '${r.geometryScore!.toStringAsFixed(1)}%',
                      ),
                      if (r.geometryShiftPx != null)
                        _metricChip(
                          'Смещение',
                          '${r.geometryShiftPx!.toStringAsFixed(1)} px',
                        ),
                      if (r.geometryMissingPercent != null)
                        _metricChip(
                          'Потери',
                          '${r.geometryMissingPercent!.toStringAsFixed(1)}%',
                        ),
                      if (r.geometryExtraPercent != null)
                        _metricChip(
                          'Лишнее',
                          '${r.geometryExtraPercent!.toStringAsFixed(1)}%',
                        ),
                    ],
                  ),
                ],
              ),
            ),

          // ── Карта различий (уровень 3: 27×27 детали) ──
          if (r.diffL3 != null || r.geometryDiff != null)
            XpGroup(
              label: 'Карта различий',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _mapModeSelector(),
                  if (_showAreaLoupePanel) ...[
                    const SizedBox(height: 8),
                    _areaLoupePanel(),
                  ],
                  const SizedBox(height: 8),
                  _mapLegend(),
                  const SizedBox(height: 8),
                  _resultMapOverlay(r),
                  const SizedBox(height: 2),
                  const Text(
                    'Ctrl+скролл/драг — зум и перемещение',
                    style: TextStyle(fontSize: 9, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('🖼 Эталон', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Slider(
                          value: _diffSlider,
                          onChanged: (v) => setState(() => _diffSlider = v),
                        ),
                      ),
                      const Text('📷 Образец', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          if (_refBarcodes.isNotEmpty || _cmpBarcodes.isNotEmpty)
            XpGroup(
              label: 'Штрихкоды / QR',
              child: Column(
                children: [
                  if (_refBarcodes.isNotEmpty) ...[
                    const Text(
                      'Эталон:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._refBarcodes.map(_barcodeTile),
                    const SizedBox(height: 6),
                  ],
                  if (_cmpBarcodes.isNotEmpty) ...[
                    const Text(
                      'Фото:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._cmpBarcodes.map(_barcodeTile),
                  ],
                  if (_refBarcodes.isNotEmpty && _cmpBarcodes.isNotEmpty)
                    _barcodeMatchSummary(),
                ],
              ),
            ),
          if (_refBarcodes.isEmpty && _cmpBarcodes.isEmpty && _result != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.qr_code, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  const Text(
                    'Штрихкоды не обнаружены',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          if (_refOcr != null || _cmpOcr != null)
            XpGroup(label: 'Текст (OCR)', child: _ocrSection()),
          XpGroup(
            label: 'AI Анализ',
            child: Column(
              children: [
                if (_aiResult == null && !_aiLoading) ...[
                  const Text(
                    'Claude Vision анализирует оба изображения и находит конкретные проблемы печати.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: XpBtn(
                      label: '🤖 Запустить AI анализ',
                      primary: true,
                      onPressed: _runAiAnalysis,
                    ),
                  ),
                ],
                if (_aiLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Claude анализирует...',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                if (_aiResult != null) ...[
                  _aiVerdictBadge(_aiResult!),
                  const SizedBox(height: 8),
                  if (_aiResult!.hasIssues) ...[
                    ..._aiResult!.issues.map(_aiIssueTile),
                    const SizedBox(height: 8),
                  ],
                  if (_aiResult!.recommendations.isNotEmpty) ...[
                    const Text(
                      'Рекомендации:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._aiResult!.recommendations.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontSize: 11)),
                            Expanded(
                              child: Text(
                                r,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: XpBtn(
                      label: '🔄 Повторить анализ',
                      onPressed: _runAiAnalysis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              XpBtn(label: '‹ Назад', onPressed: () => _tabs.animateTo(2)),
              Row(
                children: [
                  XpBtn(
                    label: '📤',
                    onPressed: () =>
                        xpDlg(context, 'Экспорт', 'PNG / PDF / CSV'),
                  ),
                  const SizedBox(width: 4),
                  XpBtn(
                    label: '🆕 Новое',
                    primary: true,
                    onPressed: () {
                      setState(() {
                        _refImg = null;
                        _cmpImg = null;
                        _result = null;
                        _compareStatus = null;
                        _aiResult = null;
                        _refAligned = null;
                        _cmpAligned = null;
                        _layoutProfile = null;
                        _resetZoomControllers();
                      });
                      _tabs.animateTo(0);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────
  TableRow _tableRow(String key, String val) => TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: Text(
              key,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            child: Text(val, style: const TextStyle(fontSize: 11)),
          ),
        ],
      );

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Формат — крупно
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: verdictColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    b.displayFormat,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasDims)
                  Text(
                    '${b.widthPx}×${b.heightPx} px',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Значение — крупно
            Text(
              b.value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // Масштаб
            Row(
              children: [
                Icon(Icons.straighten, size: 16, color: verdictColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    b.scalePct > 0
                        ? 'Масштаб ${b.scalePct.toStringAsFixed(0)}%'
                            '  (норма ${b.minPct.toInt()}–${b.maxPct.toInt()}%)'
                        : 'Масштаб не определён',
                    style: TextStyle(
                      fontSize: 12,
                      color: verdictColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              b.scaleVerdict,
              style: TextStyle(fontSize: 12, color: verdictColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ocrSection() {
    final diff = _textDiff;
    final refText = _refOcr?.fullText.trim() ?? '';
    final cmpText = _cmpOcr?.fullText.trim() ?? '';
    final refErr = _refOcr?.error;
    final cmpErr = _cmpOcr?.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ошибка OCR
        if (refErr != null || cmpErr != null)
          Container(
            padding: const EdgeInsets.all(8),
            color: AppTheme.simLow.withOpacity(0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, size: 14, color: AppTheme.simLow),
                    SizedBox(width: 6),
                    Text(
                      'Ошибка OCR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.simLow,
                      ),
                    ),
                  ],
                ),
                if (refErr != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Эталон: $refErr',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
                if (cmpErr != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Фото: $cmpErr',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
                if (!kIsWeb) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Добавьте в AndroidManifest.xml внутри <application>:\n'
                    '<meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="ocr"/>',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.black45,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        // Нет текста (OCR сработал но ничего не нашёл)
        if (refErr == null &&
            cmpErr == null &&
            refText.isEmpty &&
            cmpText.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.text_fields, size: 14, color: Colors.grey),
                SizedBox(width: 6),
                Text(
                  'Текст на изображениях не обнаружен',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
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
            child: Row(
              children: [
                Icon(
                  diff.allOk ? Icons.check_circle : Icons.warning,
                  size: 16,
                  color: diff.allOk
                      ? AppTheme.simHigh
                      : diff.similarity >= 80
                          ? AppTheme.simMid
                          : AppTheme.simLow,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diff.allOk
                        ? 'Текст совпадает полностью'
                        : 'Совпадение текста: ${diff.similarity.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: diff.allOk
                          ? AppTheme.simHigh
                          : diff.similarity >= 80
                              ? AppTheme.simMid
                              : AppTheme.simLow,
                    ),
                  ),
                ),
              ],
            ),
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
        if (refText.isNotEmpty) _ocrTextBlock('Текст эталона', refText),
        if (cmpText.isNotEmpty) _ocrTextBlock('Текст фото', cmpText),
      ],
    );
  }

  Widget _ocrDiffChips(String label, List<String> words, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: words
                .take(30)
                .map(
                  (w) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Text(
                      w,
                      style: TextStyle(fontSize: 10, color: color),
                    ),
                  ),
                )
                .toList(),
          ),
          if (words.length > 30)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '...и ещё ${words.length - 30}',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ocrTextBlock(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
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
        ],
      ),
    );
  }

  Widget _barcodeMatchSummary() {
    final refVals = {for (final b in _refBarcodes) b.value: b};
    final cmpVals = {for (final b in _cmpBarcodes) b.value: b};

    final issues = <_BarcodeIssue>[];

    // Коды есть в эталоне но нет в фото — ошибка
    for (final v in refVals.keys) {
      if (!cmpVals.containsKey(v)) {
        issues.add(
          _BarcodeIssue.error(
            'Код отсутствует на фото',
            'Значение: $v (${refVals[v]!.displayFormat})',
          ),
        );
      }
    }

    // Коды есть в фото но нет в эталоне — предупреждение
    for (final v in cmpVals.keys) {
      if (!refVals.containsKey(v)) {
        issues.add(
          _BarcodeIssue.warning(
            'Лишний код на фото',
            'Значение: $v (${cmpVals[v]!.displayFormat})',
          ),
        );
      }
    }

    // Масштаб вне нормы — предупреждение
    for (final b in [..._refBarcodes, ..._cmpBarcodes]) {
      if (b.scalePct > 0 && b.scalePct < b.minPct) {
        issues.add(
          _BarcodeIssue.warning(
            'Масштаб ниже минимума',
            '${b.displayFormat}: ${b.scalePct.toStringAsFixed(0)}% '
                '(мин. ${b.minPct.toInt()}%) — камера может не считать',
          ),
        );
      }
      if (b.scalePct > 0 && b.scalePct > b.maxPct) {
        issues.add(
          _BarcodeIssue.warning(
            'Масштаб выше максимума',
            '${b.displayFormat}: ${b.scalePct.toStringAsFixed(0)}% '
                '(макс. ${b.maxPct.toInt()}%)',
          ),
        );
      }
    }

    final hasErrors = issues.any((i) => i.isError);
    final hasWarnings = issues.any((i) => !i.isError);
    final allOk = issues.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        // Общий статус
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: allOk
              ? AppTheme.simHigh.withOpacity(0.08)
              : hasErrors
                  ? AppTheme.simLow.withOpacity(0.08)
                  : AppTheme.simMid.withOpacity(0.08),
          child: Row(
            children: [
              Icon(
                allOk
                    ? Icons.check_circle
                    : hasErrors
                        ? Icons.error
                        : Icons.warning,
                size: 16,
                color: allOk
                    ? AppTheme.simHigh
                    : hasErrors
                        ? AppTheme.simLow
                        : AppTheme.simMid,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  allOk
                      ? '✅ Все коды совпадают, масштаб в норме'
                      : hasErrors
                          ? '🔴 Обнаружены ошибки в кодах'
                          : '🟡 Предупреждения',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: allOk
                        ? AppTheme.simHigh
                        : hasErrors
                            ? AppTheme.simLow
                            : AppTheme.simMid,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Список проблем
        ...issues.map(
          (issue) => Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: issue.isError ? AppTheme.simLow : AppTheme.simMid,
                  width: 3,
                ),
              ),
              color: (issue.isError ? AppTheme.simLow : AppTheme.simMid)
                  .withOpacity(0.05),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      issue.isError ? '🔴 ОШИБКА' : '🟡 ПРЕДУПРЕЖДЕНИЕ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color:
                            issue.isError ? AppTheme.simLow : AppTheme.simMid,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  issue.detail,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        if (!allOk && !hasErrors && hasWarnings)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Коды совпадают, но есть предупреждения по масштабу.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                ai.verdict.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                '${ai.score.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(ai.summary, style: const TextStyle(fontSize: 11, height: 1.5)),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                issue.type,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '• ${issue.severity}',
                style: TextStyle(fontSize: 10, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  issue.location,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            issue.description,
            style: const TextStyle(fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      );

  // Карта ΔE поверх канонического ref/cmp — оба в одной системе координат,
  // что и diffL3 (см. compareImages в OpenCvPlugin.kt), наложение точное.
  // _cmpAligned/_cmpImg сюда НЕ годятся — они в другом масштабе/letterbox
  // и дают видимое смещение подсветки относительно картинки.
  // Ползунок кросс-фейдит эталон → образец, подсветка отличий проявляется
  // вместе с образцом.
  Widget _diffOverlay(
    Uint8List? diffPng,
    Uint8List? canonRef,
    Uint8List? canonCmp,
    TransformationController ctrl, {
    required Size imageSize,
  }) {
    final Uint8List? refBase = canonRef ?? _refImg;
    final Uint8List? cmpBase = canonCmp ?? _cmpAligned ?? _cmpImg;
    return ClipRect(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxSize = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: refBase != null &&
                        cmpBase != null &&
                        _inspectionTool == _InspectionTool.point
                    ? (details) => _sampleResultPoint(
                          local: details.localPosition,
                          viewportSize: boxSize,
                          refBytes: refBase,
                          cmpBytes: cmpBase,
                          ctrl: ctrl,
                        )
                    : null,
                child: Stack(children: [
                  InteractiveViewer(
                    transformationController: ctrl,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    minScale: 0.5,
                    maxScale: 8.0,
                    panEnabled: _ctrlHeld,
                    scaleEnabled: _ctrlHeld,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (refBase != null)
                          _uiImage(refBase, fit: BoxFit.contain),
                        if (cmpBase != null)
                          Opacity(
                            opacity: _diffSlider,
                            child: _uiImage(cmpBase, fit: BoxFit.contain),
                          ),
                        if (diffPng != null)
                          Opacity(
                            opacity: _diffSlider,
                            child: _uiImage(diffPng, fit: BoxFit.contain),
                          ),
                        if (_pointProbe != null)
                          CustomPaint(
                            painter: _ProbePointPainter(
                              normalized: _pointProbe!.normalized,
                              imageSize: _pointProbe!.imageSize,
                            ),
                          ),
                        if (_loupeDraftRect != null || _areaLoupe != null)
                          CustomPaint(
                            painter: _LoupeSelectionPainter(
                              normalized:
                                  _loupeDraftRect ?? _areaLoupe!.normalizedRect,
                              imageSize: _loupeImageSize ??
                                  _areaLoupe?.imageSize ??
                                  Size.zero,
                              active: _loupeDraftRect != null,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (refBase != null &&
                      cmpBase != null &&
                      _inspectionTool == _InspectionTool.loupe)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) => _startAreaLoupeSelection(
                          local: details.localPosition,
                          viewportSize: boxSize,
                          imageSize: imageSize,
                          ctrl: ctrl,
                        ),
                        onPanUpdate: (details) => _updateAreaLoupeSelection(
                          local: details.localPosition,
                          viewportSize: boxSize,
                          imageSize: imageSize,
                          ctrl: ctrl,
                        ),
                        onPanEnd: (_) => _finishAreaLoupeSelection(
                          viewportSize: boxSize,
                          imageSize: imageSize,
                          ctrl: ctrl,
                        ),
                      ),
                    ),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  void _sampleResultPoint({
    required Offset local,
    required Size viewportSize,
    required Uint8List refBytes,
    required Uint8List cmpBytes,
    required TransformationController ctrl,
  }) {
    final ref = img.decodeImage(refBytes);
    final cmp = img.decodeImage(cmpBytes);
    if (ref == null || cmp == null) return;

    final scenePoint = ctrl.toScene(local);
    final rect = _containedImageRect(
      viewportSize,
      Size(ref.width.toDouble(), ref.height.toDouble()),
    );
    if (!rect.contains(scenePoint)) return;

    final nx = ((scenePoint.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final ny = ((scenePoint.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    final rx = (nx * (ref.width - 1)).round().clamp(0, ref.width - 1);
    final ry = (ny * (ref.height - 1)).round().clamp(0, ref.height - 1);
    final cx = (nx * (cmp.width - 1)).round().clamp(0, cmp.width - 1);
    final cy = (ny * (cmp.height - 1)).round().clamp(0, cmp.height - 1);

    final refPixel = ref.getPixel(rx, ry);
    final cmpPixel = cmp.getPixel(cx, cy);
    setState(() {
      _pointProbe = _PointProbe(
        x: rx,
        y: ry,
        normalized: Offset(nx, ny),
        imageSize: Size(ref.width.toDouble(), ref.height.toDouble()),
        refLab: _LabColor.fromPixel(refPixel),
        cmpLab: _LabColor.fromPixel(cmpPixel),
        refCmyk: _CmykColor.fromPixel(refPixel),
        cmpCmyk: _CmykColor.fromPixel(cmpPixel),
        deltaE: _deltaE76(refPixel, cmpPixel),
      );
    });
  }

  void _startAreaLoupeSelection({
    required Offset local,
    required Size viewportSize,
    required Size imageSize,
    required TransformationController ctrl,
  }) {
    final p = _normalizedOverlayPoint(
      local: local,
      viewportSize: viewportSize,
      imageSize: imageSize,
      ctrl: ctrl,
    );
    if (p == null) return;
    setState(() {
      _loupeDragStart = p;
      _loupeDraftRect = Rect.fromPoints(p, p);
      _loupeImageSize = imageSize;
    });
  }

  void _updateAreaLoupeSelection({
    required Offset local,
    required Size viewportSize,
    required Size imageSize,
    required TransformationController ctrl,
  }) {
    final start = _loupeDragStart;
    if (start == null) return;
    final p = _normalizedOverlayPoint(
      local: local,
      viewportSize: viewportSize,
      imageSize: imageSize,
      ctrl: ctrl,
    );
    if (p == null) return;
    setState(() {
      _loupeDraftRect = _normalizedRectFromPoints(start, p);
      _loupeImageSize = imageSize;
    });
  }

  void _finishAreaLoupeSelection({
    required Size viewportSize,
    required Size imageSize,
    required TransformationController ctrl,
  }) {
    final draft = _loupeDraftRect;
    if (draft == null) return;
    final normalized = _expandLoupeRect(draft);
    final refCrop = _cropSizeForImage(imageSize, normalized);
    setState(() {
      _areaLoupe = _AreaLoupe(
        normalizedRect: normalized,
        imageSize: imageSize,
        refWidth: refCrop.width,
        refHeight: refCrop.height,
        cmpWidth: refCrop.width,
        cmpHeight: refCrop.height,
      );
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _loupeImageSize = imageSize;
    });
    _zoomComparisonToRect(
      normalized,
      viewportSize: viewportSize,
      imageSize: imageSize,
      ctrl: ctrl,
    );
  }

  void _zoomComparisonToRect(
    Rect normalized, {
    required Size viewportSize,
    required Size imageSize,
    required TransformationController ctrl,
  }) {
    final imageRect = _containedImageRect(viewportSize, imageSize);
    if (imageRect.width <= 0 || imageRect.height <= 0) return;
    final target = Rect.fromLTRB(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      imageRect.left + normalized.right * imageRect.width,
      imageRect.top + normalized.bottom * imageRect.height,
    );
    if (target.width <= 1 || target.height <= 1) return;
    final scale = (min(viewportSize.width / target.width,
                viewportSize.height / target.height) *
            0.86)
        .clamp(0.7, 8.0);
    final tx = viewportSize.width / 2 - target.center.dx * scale;
    final ty = viewportSize.height / 2 - target.center.dy * scale;
    ctrl.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(scale);
  }

  Offset? _normalizedOverlayPoint({
    required Offset local,
    required Size viewportSize,
    required Size imageSize,
    required TransformationController ctrl,
  }) {
    final scenePoint = ctrl.toScene(local);
    final rect = _containedImageRect(viewportSize, imageSize);
    if (!rect.contains(scenePoint)) return null;
    return Offset(
      ((scenePoint.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((scenePoint.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  Rect _normalizedRectFromPoints(Offset a, Offset b) {
    return Rect.fromLTRB(
      min(a.dx, b.dx).clamp(0.0, 1.0),
      min(a.dy, b.dy).clamp(0.0, 1.0),
      max(a.dx, b.dx).clamp(0.0, 1.0),
      max(a.dy, b.dy).clamp(0.0, 1.0),
    );
  }

  Rect _expandLoupeRect(Rect rect) {
    const minSide = 0.035;
    var left = rect.left;
    var top = rect.top;
    var right = rect.right;
    var bottom = rect.bottom;
    if (right - left < minSide) {
      final c = (left + right) / 2;
      left = (c - minSide / 2).clamp(0.0, 1.0 - minSide);
      right = left + minSide;
    }
    if (bottom - top < minSide) {
      final c = (top + bottom) / 2;
      top = (c - minSide / 2).clamp(0.0, 1.0 - minSide);
      bottom = top + minSide;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  ({int width, int height}) _cropSizeForImage(Size imageSize, Rect normalized) {
    final width = max(1, (normalized.width * imageSize.width).round());
    final height = max(1, (normalized.height * imageSize.height).round());
    return (width: width, height: height);
  }

  Rect _containedImageRect(Size box, Size image) {
    if (box.width <= 0 ||
        box.height <= 0 ||
        image.width <= 0 ||
        image.height <= 0) {
      return Offset.zero & box;
    }
    final scale = min(box.width / image.width, box.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  double _deltaE76(img.Pixel ref, img.Pixel cmp) {
    final a = _rgbToLab(ref);
    final b = _rgbToLab(cmp);
    final dl = a.l - b.l;
    final da = a.a - b.a;
    final db = a.b - b.b;
    return sqrt(dl * dl + da * da + db * db);
  }

  ({double l, double a, double b}) _rgbToLab(img.Pixel p) {
    final r = _pivotRgb(p.r);
    final g = _pivotRgb(p.g);
    final b = _pivotRgb(p.b);
    final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
    final y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750);
    final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
    final fx = _pivotXyz(x);
    final fy = _pivotXyz(y);
    final fz = _pivotXyz(z);
    return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
  }

  double _pivotRgb(num v) {
    final c = v / 255.0;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) as double;
  }

  double _pivotXyz(double v) {
    return v > 0.008856 ? pow(v, 1 / 3) as double : (7.787 * v) + 16 / 116;
  }

  // Текстовый комментарий о цветовом сдвиге образца относительно эталона.
  // da > 0 → образец краснее; da < 0 → зеленее
  // db > 0 → образец желтее;  db < 0 → синее
  // dL > 0 → образец темнее;  dL < 0 → светлее
  String _colorComment(double? dL, double? da, double? db) {
    if (dL == null && da == null && db == null) return 'Нет данных';
    final parts = <String>[];
    final thresh = 3.0; // порог значимости в единицах OpenCV Lab
    if (dL != null && dL.abs() > 2.0) {
      parts.add(
        dL > 0
            ? 'образец темнее на ${dL.abs().toStringAsFixed(1)} L*'
            : 'образец светлее на ${dL.abs().toStringAsFixed(1)} L*',
      );
    }
    if (da != null && da.abs() > thresh) {
      parts.add(
        da > 0
            ? 'смещение в красный (+${da.toStringAsFixed(1)} a*)'
            : 'смещение в зелёный (${da.toStringAsFixed(1)} a*)',
      );
    }
    if (db != null && db.abs() > thresh) {
      parts.add(
        db > 0
            ? 'смещение в жёлтый (+${db.toStringAsFixed(1)} b*)'
            : 'смещение в синий (${db.toStringAsFixed(1)} b*)',
      );
    }
    if (parts.isEmpty) return 'Общий тон в норме (глобальный сдвиг < порога)';
    return parts.join(' · ');
  }

  String _geometryVerdict(CompareResult r) {
    final score = r.geometryScore ?? 0;
    final shift = r.geometryShiftPx ?? 0;
    final missing = r.geometryMissingPercent ?? 0;
    final extra = r.geometryExtraPercent ?? 0;
    if (score >= 96 && shift <= 1.2 && missing <= 2.5 && extra <= 2.5) {
      return 'Геометрия в норме: контуры текста и штрихов совпадают, цветовые отличия не влияют на этот вывод.';
    }
    if (score >= 90 && shift <= 2.5) {
      return 'Есть небольшие геометрические отклонения: стоит проверить зоны с потерянными или лишними штрихами.';
    }
    return 'Геометрия требует проверки: возможны смещение текста, непопадание белой краски/чёрных чернил или потеря элементов.';
  }

  String _geometryStatusLine(CompareResult r) {
    final score = r.geometryScore;
    if (score == null) return 'Геометрия текста и штрихов: нет данных.';
    final shift = r.geometryShiftPx ?? 0;
    if (score >= 96 && shift <= 1.2) {
      return 'Геометрия текста и штрихов в норме.';
    }
    if (score >= 90) {
      return 'Геометрия текста и штрихов: есть небольшие отклонения.';
    }
    return 'Геометрия текста и штрихов требует проверки.';
  }
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
      sum += v;
      sumSq += v * v;
      n++;
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
  final double? other; // резкость второго снимка для сравнения
  final VoidCallback onSelect;

  const _SharpnessCard({
    required this.bytes,
    required this.label,
    required this.sharpness,
    required this.other,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isBetter = sharpness != null && other != null && sharpness! >= other!;
    final loading = sharpness == null;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isBetter ? AppTheme.simHigh : AppTheme.silver,
            width: isBetter ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Image.memory(
                  bytes,
                  height: 140,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  cacheWidth: 1000,
                  filterQuality: FilterQuality.medium,
                ),
                if (isBetter)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: _ImgLabel('✓ Резче'),
                  ),
              ],
            ),
            Container(
              color: AppTheme.silver,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (loading)
                    const Text(
                      'Анализ...',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    )
                  else ...[
                    Text(
                      'Резкость: ${sharpness!.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onSelect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isBetter ? AppTheme.simHigh : AppTheme.blue,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Выбрать',
                        style: TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final ml = size.width * margin;
    final mt = size.height * margin;
    final mr = size.width - ml;
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

    corner(ml, mt, 1, 1);
    corner(mr, mt, -1, 1);
    corner(ml, mb, 1, -1);
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
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
}

// Якорная точка с цифрой рядом. Размер точки и подписи остаётся
// постоянным на экране независимо от зума InteractiveViewer — мы
// слушаем ctrl и компенсируем масштаб обратным Transform.scale, а
// смещение подписи от точки тоже пересчитываем через inv, чтобы оно
// не "разъезжалось" при увеличении.
class _AnchorPointMarker extends StatelessWidget {
  final TransformationController ctrl;
  final double x, y;
  final int index;
  final Color color;
  const _AnchorPointMarker({
    required this.ctrl,
    required this.x,
    required this.y,
    required this.index,
    this.color = Colors.red,
  });

  static const double _dotSize = 3;
  static const double _labelOffset = 24;
  static const double _labelSize = 16;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final scale = ctrl.value.getMaxScaleOnAxis();
        final inv = scale <= 0 ? 1.0 : 1 / scale;
        final off = _labelOffset * inv;
        return Stack(
          children: [
            Positioned(
              left: x - _dotSize / 2,
              top: y - _dotSize / 2,
              width: _dotSize,
              height: _dotSize,
              child: Transform.scale(
                scale: inv,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.85),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.8),
                  ),
                ),
              ),
            ),
            Positioned(
              left: x + off,
              top: y - off - _labelSize,
              width: _labelSize,
              height: _labelSize,
              child: Transform.scale(
                scale: inv,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FlowStep {
  final String num;
  final String label;
  final bool done;
  final bool active;

  const _FlowStep(this.num, this.label, this.done, this.active);
}

class _LevelConclusion {
  final String key;
  final String title;
  final String status;
  final String message;
  final String metric;

  const _LevelConclusion({
    required this.key,
    required this.title,
    required this.status,
    required this.message,
    required this.metric,
  });
}

class _PointProbe {
  final int x;
  final int y;
  final Offset normalized;
  final Size imageSize;
  final _LabColor refLab;
  final _LabColor cmpLab;
  final _CmykColor refCmyk;
  final _CmykColor cmpCmyk;
  final double deltaE;

  const _PointProbe({
    required this.x,
    required this.y,
    required this.normalized,
    required this.imageSize,
    required this.refLab,
    required this.cmpLab,
    required this.refCmyk,
    required this.cmpCmyk,
    required this.deltaE,
  });
}

class _AreaLoupe {
  final Rect normalizedRect;
  final Size imageSize;
  final int refWidth;
  final int refHeight;
  final int cmpWidth;
  final int cmpHeight;

  const _AreaLoupe({
    required this.normalizedRect,
    required this.imageSize,
    required this.refWidth,
    required this.refHeight,
    required this.cmpWidth,
    required this.cmpHeight,
  });
}

class _LabColor {
  final double l;
  final double a;
  final double b;

  const _LabColor(this.l, this.a, this.b);

  factory _LabColor.fromPixel(img.Pixel p) {
    final lab = _rgbPixelToLab(p);
    return _LabColor(lab.l, lab.a, lab.b);
  }

  String get label =>
      'L ${l.toStringAsFixed(1)}  a ${a.toStringAsFixed(1)}  b ${b.toStringAsFixed(1)}';
}

class _CmykColor {
  final double c;
  final double m;
  final double y;
  final double k;

  const _CmykColor(this.c, this.m, this.y, this.k);

  factory _CmykColor.fromPixel(img.Pixel p) {
    final r = (p.r / 255.0).clamp(0.0, 1.0);
    final g = (p.g / 255.0).clamp(0.0, 1.0);
    final b = (p.b / 255.0).clamp(0.0, 1.0);
    final k = 1.0 - max(r, max(g, b));
    if (k >= 0.999) return const _CmykColor(0, 0, 0, 100);
    final c = (1.0 - r - k) / (1.0 - k);
    final m = (1.0 - g - k) / (1.0 - k);
    final y = (1.0 - b - k) / (1.0 - k);
    return _CmykColor(c * 100, m * 100, y * 100, k * 100);
  }

  String get label => 'C ${c.toStringAsFixed(1)}  M ${m.toStringAsFixed(1)}\n'
      'Y ${y.toStringAsFixed(1)}  K ${k.toStringAsFixed(1)}';
}

class _ImageBoundsPainter extends CustomPainter {
  final Rect rect;

  const _ImageBoundsPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageBoundsPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}

class _AnchorLoupeDialog extends StatefulWidget {
  final Uint8List bytes;
  final Size imageSize;
  final Offset roughPoint;
  final int pointIndex;
  final String title;
  final double defaultZoom;

  const _AnchorLoupeDialog({
    required this.bytes,
    required this.imageSize,
    required this.roughPoint,
    required this.pointIndex,
    required this.title,
    required this.defaultZoom,
  });

  @override
  State<_AnchorLoupeDialog> createState() => _AnchorLoupeDialogState();
}

class _AnchorLoupeDialogState extends State<_AnchorLoupeDialog> {
  ui.Image? _image;
  late Offset _center;
  Offset? _selectedPoint;
  late double _zoom;

  @override
  void initState() {
    super.initState();
    _center = _clampPoint(widget.roughPoint);
    _zoom = widget.defaultZoom;
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  Offset _clampPoint(Offset p) {
    return Offset(
      p.dx.clamp(0.0, widget.imageSize.width - 1.0),
      p.dy.clamp(0.0, widget.imageSize.height - 1.0),
    );
  }

  Rect _sourceRect(double side) {
    final imageW = widget.imageSize.width;
    final imageH = widget.imageSize.height;
    final sourceSide =
        (side / _zoom).clamp(18.0, min(imageW, imageH)).toDouble();
    var left = _center.dx - sourceSide / 2;
    var top = _center.dy - sourceSide / 2;
    left = left.clamp(0.0, max(0.0, imageW - sourceSide));
    top = top.clamp(0.0, max(0.0, imageH - sourceSide));
    return Rect.fromLTWH(left, top, sourceSide, sourceSide);
  }

  Offset _localToImage(Offset local, double side, Rect source) {
    return _clampPoint(
      Offset(
        source.left + local.dx / side * source.width,
        source.top + local.dy / side * source.height,
      ),
    );
  }

  void _pan(DragUpdateDetails details, double side, Rect source) {
    final dx = details.delta.dx / side * source.width;
    final dy = details.delta.dy / side * source.height;
    setState(() => _center = _clampPoint(_center.translate(-dx, -dy)));
  }

  void _selectPoint(Offset local, double side, Rect source) {
    final point = _localToImage(local, side, source);
    setState(() {
      _selectedPoint = point;
      _center = point;
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: const Color(0xFF111419),
      child: LayoutBuilder(builder: (context, constraints) {
        final availableW = MediaQuery.sizeOf(context).width - 44;
        final availableH = MediaQuery.sizeOf(context).height - 170;
        final side = min(availableW, availableH).clamp(300.0, 680.0);
        final source = _sourceRect(side);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(
                  '${widget.title} #${widget.pointIndex}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _selectedPoint == null
                    ? 'выберите точку'
                    : 'x ${_selectedPoint!.dx.toStringAsFixed(1)}  y ${_selectedPoint!.dy.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTapDown: image == null
                  ? null
                  : (details) =>
                      _selectPoint(details.localPosition, side, source),
              onPanUpdate: image == null
                  ? null
                  : (details) => _pan(details, side, source),
              child: Container(
                width: side,
                height: side,
                color: Colors.black,
                child: image == null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : CustomPaint(
                        painter: _AnchorLoupePainter(
                          image: image,
                          source: source,
                          roughPoint: widget.roughPoint,
                          selectedPoint: _selectedPoint,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _LoupeZoomBtn(
                label: '4x',
                selected: _zoom == 4.0,
                onTap: () => setState(() => _zoom = 4.0),
              ),
              const SizedBox(width: 6),
              _LoupeZoomBtn(
                label: '8x',
                selected: _zoom == 8.0,
                onTap: () => setState(() => _zoom = 8.0),
              ),
              const SizedBox(width: 6),
              _LoupeZoomBtn(
                label: '12x',
                selected: _zoom == 12.0,
                onTap: () => setState(() => _zoom = 12.0),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _selectedPoint == null
                    ? null
                    : () => Navigator.pop(context, _selectedPoint),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                ),
                child: const Text('Поставить точку'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
            ]),
            Text(
              _selectedPoint == null
                  ? 'Клик в лупе выбирает место. После выбора нажмите «Поставить точку».'
                  : 'Красный прицел - выбранная точка. Можно кликнуть ещё раз точнее.',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ]),
        );
      }),
    );
  }
}

class _LoupeZoomBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LoupeZoomBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.black : Colors.white,
        backgroundColor: selected ? Colors.white : Colors.transparent,
        side: BorderSide(color: selected ? Colors.white : Colors.white38),
        minimumSize: const Size(48, 34),
      ),
      child: Text(label),
    );
  }
}

class _AnchorLoupePainter extends CustomPainter {
  final ui.Image image;
  final Rect source;
  final Offset roughPoint;
  final Offset? selectedPoint;

  const _AnchorLoupePainter({
    required this.image,
    required this.source,
    required this.roughPoint,
    required this.selectedPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dest = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(image, source, dest, paint);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 1;
    if (source.width <= 120) {
      final startX = source.left.ceil();
      final endX = source.right.floor();
      for (var x = startX; x <= endX; x += 5) {
        final dx = (x - source.left) / source.width * size.width;
        canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), gridPaint);
      }
      final startY = source.top.ceil();
      final endY = source.bottom.floor();
      for (var y = startY; y <= endY; y += 5) {
        final dy = (y - source.top) / source.height * size.height;
        canvas.drawLine(Offset(0, dy), Offset(size.width, dy), gridPaint);
      }
    }

    final centerPaint = Paint()
      ..color = Colors.cyanAccent
          .withValues(alpha: selectedPoint == null ? 0.95 : 0.36)
      ..strokeWidth = 1.4;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
        center.translate(-18, 0), center.translate(18, 0), centerPaint);
    canvas.drawLine(
        center.translate(0, -18), center.translate(0, 18), centerPaint);

    if (source.contains(roughPoint)) {
      final rough = Offset(
        (roughPoint.dx - source.left) / source.width * size.width,
        (roughPoint.dy - source.top) / source.height * size.height,
      );
      final roughPaint = Paint()
        ..color = Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(rough, 9, roughPaint);
    }

    final selected = selectedPoint;
    if (selected != null && source.contains(selected)) {
      final p = Offset(
        (selected.dx - source.left) / source.width * size.width,
        (selected.dy - source.top) / source.height * size.height,
      );
      final shadow = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      final white = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4;
      final red = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      for (final paint in [shadow, white, red]) {
        canvas.drawCircle(p, 13, paint);
        canvas.drawLine(p.translate(-24, 0), p.translate(-7, 0), paint);
        canvas.drawLine(p.translate(7, 0), p.translate(24, 0), paint);
        canvas.drawLine(p.translate(0, -24), p.translate(0, -7), paint);
        canvas.drawLine(p.translate(0, 7), p.translate(0, 24), paint);
      }
      final fill = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 2.4, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _AnchorLoupePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.source != source ||
        oldDelegate.roughPoint != roughPoint ||
        oldDelegate.selectedPoint != selectedPoint;
  }
}

class _ProbePointPainter extends CustomPainter {
  final Offset normalized;
  final Size imageSize;

  const _ProbePointPainter({required this.normalized, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _containedRect(size, imageSize);
    final center = Offset(
      rect.left + normalized.dx * rect.width,
      rect.top + normalized.dy * rect.height,
    );
    final outer = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final inner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final paint in [outer, inner]) {
      canvas.drawCircle(center, 8, paint);
      canvas.drawLine(center.translate(-14, 0), center.translate(-5, 0), paint);
      canvas.drawLine(center.translate(5, 0), center.translate(14, 0), paint);
      canvas.drawLine(center.translate(0, -14), center.translate(0, -5), paint);
      canvas.drawLine(center.translate(0, 5), center.translate(0, 14), paint);
    }
  }

  Rect _containedRect(Size box, Size image) {
    if (box.width <= 0 ||
        box.height <= 0 ||
        image.width <= 0 ||
        image.height <= 0) {
      return Offset.zero & box;
    }
    final scale = min(box.width / image.width, box.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  @override
  bool shouldRepaint(covariant _ProbePointPainter oldDelegate) {
    return oldDelegate.normalized != normalized ||
        oldDelegate.imageSize != imageSize;
  }
}

class _LoupeSelectionPainter extends CustomPainter {
  final Rect normalized;
  final Size imageSize;
  final bool active;

  const _LoupeSelectionPainter({
    required this.normalized,
    required this.imageSize,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == Size.zero) return;
    final imageRect = _containedRect(size, imageSize);
    final rect = Rect.fromLTRB(
      imageRect.left + normalized.left * imageRect.width,
      imageRect.top + normalized.top * imageRect.height,
      imageRect.left + normalized.right * imageRect.width,
      imageRect.top + normalized.bottom * imageRect.height,
    );
    if (rect.width <= 1 || rect.height <= 1) return;

    final fill = Paint()
      ..color =
          (active ? AppTheme.blue : const Color(0xFF1D6E68)).withOpacity(0.13)
      ..style = PaintingStyle.fill;
    final outer = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final inner = Paint()
      ..color = active ? Colors.white : const Color(0xFFBFFFF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, outer);
    canvas.drawRect(rect, inner);
  }

  Rect _containedRect(Size box, Size image) {
    if (box.width <= 0 ||
        box.height <= 0 ||
        image.width <= 0 ||
        image.height <= 0) {
      return Offset.zero & box;
    }
    final scale = min(box.width / image.width, box.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  @override
  bool shouldRepaint(covariant _LoupeSelectionPainter oldDelegate) {
    return oldDelegate.normalized != normalized ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.active != active;
  }
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
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
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
