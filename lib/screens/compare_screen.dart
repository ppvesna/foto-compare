import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../capabilities/storage/storage.dart';
import '../features/billing/billing.dart';
import '../features/capture/capture.dart';
import '../features/color_analysis/color_analysis.dart';
import '../features/organization/organization.dart';
import '../features/production/production.dart';
import '../widgets/workspace_photo_background.dart';
import '../widgets/xp_widgets.dart';
import '../widgets/pixel_text.dart';
import '../services/compare_service.dart';
import '../features/references/references.dart';
import '../services/opencv_service.dart';
import '../services/ai_compare_service.dart';
import '../services/barcode_service.dart';
import '../services/anchor_refinement_service.dart';
import '../services/calibration_settings_service.dart';
import '../services/lab_fingerprint_service.dart';
import '../services/ocr_service.dart';
import '../features/protocols/protocols.dart';
import '../services/web_compare_worker_stub.dart'
    if (dart.library.html) '../services/web_compare_worker_web.dart'
    as web_worker;
import '../config/app_config.dart';
import '../widgets/crop_frame_screen.dart';

enum _ResultMapMode { deltaE, geometry, overlay }

enum _InspectionTool { point, loupe }

enum _WorkspaceView { reference, sample, comparison }

class _JobSelectionDraft {
  final String jobNumber;
  final String? customerId;
  final String customerName;
  final String requestedCustomerName;

  const _JobSelectionDraft({
    required this.jobNumber,
    this.customerId,
    required this.customerName,
    required this.requestedCustomerName,
  });
}

class CompareScreen extends StatefulWidget {
  final EntitlementSnapshot entitlements;
  final OrganizationAccess organizationAccess;
  final CustomerDirectoryService? customerDirectoryService;
  final ProductionJobService? productionJobService;
  final ProtocolCloudRepository? protocolCloudRepository;
  final CheckUsageService? checkUsageService;
  final ProductionWorkflowService? productionWorkflowService;
  final ProductionWorkUnit? inspectionUnit;
  final VoidCallback? onCheckUsageChanged;
  final ProductionJobContext? initialJob;
  final VoidCallback? onBackToWorks;
  final String backTooltip;
  final bool canOpenChat;
  final bool showStoredHistory;
  // App navigation lives in MainShell; the restricted role view uses this to
  // send customer representatives back to their job chat.
  final ValueChanged<int>? onNavigate;

  const CompareScreen({
    super.key,
    required this.entitlements,
    required this.organizationAccess,
    this.customerDirectoryService,
    this.productionJobService,
    this.protocolCloudRepository,
    this.checkUsageService,
    this.productionWorkflowService,
    this.inspectionUnit,
    this.onCheckUsageChanged,
    this.initialJob,
    this.onBackToWorks,
    this.backTooltip = 'Вернуться к работам',
    this.canOpenChat = true,
    this.showStoredHistory = true,
    this.onNavigate,
  });

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  static const Color _hudGreen = Color(0xFF70FF96);
  static const Color _hudGreenSecondary = Color(0xFF54EE80);
  static const Color _hudGreenLabel = Color(0xFF31D463);
  static const Color _hudWarning = Color(0xFFFF843D);
  static const Color _hudError = Color(0xFFFF4F55);

  Uint8List? _refImg;
  Uint8List? _cmpImg;
  final _picker = ImagePicker();
  bool _comparing = false;
  String? _compareStatus;
  final List<String> _compareSteps = [];
  final List<_TimedStep> _timedSteps = [];
  Stopwatch? _stageWatch;
  bool _aiLoading = false;
  CompareResult? _result;
  ProductionUnitState? _productionInspectionState;
  bool _productionDecisionBusy = false;
  AiAnalysis? _aiResult;
  List<BarcodeResult> _refBarcodes = [];
  List<BarcodeResult> _cmpBarcodes = [];
  TextDiff? _textDiff;
  LabFingerprint? _refLabFingerprint;
  LabFingerprint? _cmpLabFingerprint;
  double? _labFingerprintMatch;

  bool _allows(ProductCapability capability) =>
      widget.entitlements.allows(capability);

  void _showPlanRequired(String feature) {
    xpDlg(
      context,
      'Нет доступа',
      '$feature не входит в текущий план.',
    );
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  Future<bool> _hasDailyCheckQuota() async {
    final limit = widget.entitlements.limit(UsageLimit.checksPerDay);
    if (limit == null) return true;
    final usageService = widget.checkUsageService;
    if (usageService != null) {
      try {
        final usage = await usageService.load();
        if (!mounted) return false;
        if (!usage.limitReached) return true;
        _showDailyCheckLimit(usage);
        return false;
      } catch (_) {
        if (mounted) {
          await xpDlg(
            context,
            'Счётчик проверок недоступен',
            'Не удалось проверить общий дневной лимит на сервере. Повторите после восстановления соединения.',
          );
        }
        return false;
      }
    }
    final used = CheckHistoryService.checks.value
        .where((p) => _isToday(p.createdAt))
        .length;
    if (used < limit) return true;
    xpDlg(
      context,
      'Дневной лимит',
      'Использовано $used из $limit проверок. Новая проверка будет доступна после обновления лимита.',
    );
    return false;
  }

  void _showDailyCheckLimit(CheckUsageSnapshot usage) {
    xpDlg(
      context,
      'Дневной лимит',
      'Использовано ${usage.used} из ${usage.limit} проверок. Новая проверка будет доступна после смены серверного дня (UTC).',
    );
  }

  Uint8List? _refAligned;
  Uint8List? _cmpAligned;
  final _workspaceScrollCtrl = ScrollController();

  final _refAlignCtrl = TransformationController();
  final _cmpAlignCtrl = TransformationController();
  List<Offset>? _refAnchorPts;
  List<Offset>? _cmpAnchorPts;
  Size? _refImgSize;
  Size? _cmpImgSize;
  int _calStep = 0;
  List<Offset> _tempRefPts = [];
  List<Offset> _tempCmpPts = [];
  bool _anchorRefining = false;
  static const int _minAnchorPts = 4;
  static const int _maxAnchorPts = 8;

  bool _stacking = false;
  bool _imageBusy = false;
  bool _refCropApplied = false;
  bool _cmpCropApplied = false;
  String _imageBusyLabel = 'Обработка изображения...';
  double _diffSlider = 0.5;
  _ResultMapMode _resultMapMode = _ResultMapMode.deltaE;
  bool _exactDeltaEReady = false;
  bool _exactDeltaEComputing = false;
  bool _exactDeltaERequested = false;
  _InspectionTool? _inspectionTool;
  final _resultCmpCtrl = TransformationController();
  _WorkspaceView _workspaceView = _WorkspaceView.reference;
  _PointProbe? _pointProbe;
  _AreaLoupe? _areaLoupe;
  Offset? _loupeDragStart;
  Rect? _loupeDraftRect;
  Size? _loupeImageSize;

  String? _savedRefLabel;
  String? _activeReferenceId;
  List<SavedReferenceProfile> _savedReferences = [];
  String _jobNumber = '';
  String? _cloudJobId;
  List<OrganizationCustomer> _organizationCustomers = const [];
  String? _selectedCustomerId;
  String _selectedCustomerName = '';
  String _requestedCustomerName = '';
  bool _customerConfirmed = false;
  bool _customerDirectoryAvailable = true;
  Future<void>? _customerDirectoryLoadFuture;
  int _sampleNo = 1;
  String? _activeProtocolId;
  DateTime? _activeProtocolCreatedAt;
  String? _activeProtocolSampleImageId;
  int? _activeProtocolSampleNo;
  Future<void> _cloudProtocolSyncQueue = Future<void>.value();

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
  CalibrationPointSettings _calibrationSettings =
      CalibrationPointSettings.defaults;
  ColorMeasurementSettings _measurementSettings =
      ColorMeasurementSettings.defaults;
  CameraCaptureSettings _cameraCaptureSettings = CameraCaptureSettings.defaults;
  CameraCalibrationProfile? _cameraCalibrationProfile;

  @override
  void initState() {
    super.initState();
    _productionInspectionState = widget.inspectionUnit?.state;
    _applyInitialJob(widget.initialJob);
    _loadSavedReference();
    _loadCalibrationSettings();
    _loadColorMeasurementSettings();
    _loadCameraCaptureSettings();
    _loadCameraCalibrationProfile();
    _loadCustomerDirectory();
    CalibrationSettingsService.notifier.addListener(_onCalibrationSettings);
    CameraCalibrationProfileService.activeProfileNotifier.addListener(
      _onCameraCalibrationProfile,
    );
    HardwareKeyboard.instance.addHandler(_handleCtrlKey);
  }

  @override
  void didUpdateWidget(covariant CompareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationAccess.organizationId !=
        widget.organizationAccess.organizationId) {
      _loadCustomerDirectory();
    }
    if (oldWidget.initialJob?.jobId != widget.initialJob?.jobId) {
      setState(() => _applyInitialJob(widget.initialJob));
    }
    if (oldWidget.inspectionUnit?.id != widget.inspectionUnit?.id) {
      setState(() => _productionInspectionState = widget.inspectionUnit?.state);
    }
  }

  void _applyInitialJob(ProductionJobContext? job) {
    if (job == null) return;
    _jobNumber = job.jobNumber;
    _cloudJobId = job.jobId;
    _selectedCustomerId = job.customerId;
    _selectedCustomerName = job.customerConfirmed ? job.customerName : '';
    _requestedCustomerName = job.customerConfirmed ? '' : job.customerName;
    _customerConfirmed = job.customerConfirmed;
  }

  CustomerDirectoryService get _customerDirectoryService =>
      widget.customerDirectoryService ??
      SupabaseCustomerDirectoryService(Supabase.instance.client);

  ProductionJobService get _productionJobService =>
      widget.productionJobService ??
      SupabaseProductionJobService(Supabase.instance.client);

  Future<void> _loadCustomerDirectory() {
    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return Future.value();
    final activeLoad = _customerDirectoryLoadFuture;
    if (activeLoad != null) return activeLoad;

    final load = _loadCustomerDirectoryOnce(organizationId);
    _customerDirectoryLoadFuture = load;
    return load.whenComplete(() {
      if (identical(_customerDirectoryLoadFuture, load)) {
        _customerDirectoryLoadFuture = null;
      }
    });
  }

  Future<void> _loadCustomerDirectoryOnce(String organizationId) async {
    try {
      final customers =
          await _customerDirectoryService.listCustomers(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _customerDirectoryAvailable = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _customerDirectoryAvailable = false);
    }
  }

  Future<void> _loadCalibrationSettings() async {
    final settings = await CalibrationSettingsService.load();
    if (mounted) setState(() => _calibrationSettings = settings);
  }

  Future<void> _loadColorMeasurementSettings() async {
    final settings = await ColorMeasurementSettingsService.load();
    if (mounted) setState(() => _measurementSettings = settings);
  }

  Future<void> _loadCameraCaptureSettings() async {
    final settings = await CameraCaptureSettingsService.load();
    if (mounted) setState(() => _cameraCaptureSettings = settings);
  }

  Future<void> _loadCameraCalibrationProfile() async {
    final profile = await CameraCalibrationProfileService.loadActive();
    if (mounted) setState(() => _cameraCalibrationProfile = profile);
  }

  void _onCameraCalibrationProfile() {
    if (!mounted) return;
    setState(() {
      _cameraCalibrationProfile =
          CameraCalibrationProfileService.activeProfileNotifier.value;
    });
  }

  void _onCalibrationSettings() {
    if (!mounted) return;
    setState(() {
      _calibrationSettings = CalibrationSettingsService.notifier.value;
    });
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

  Future<void> _activateSavedReference(
    SavedReferenceProfile item, {
    bool showMessage = true,
  }) async {
    await ReferenceStorage.setActive(item.id);
    final size = await _readImageSize(item.bytes);
    if (!mounted) return;
    final profile = item.layoutProfile;
    final anchors = profile?.refAnchors
        .map((a) => Offset(a.x * size.width, a.y * size.height))
        .toList();
    setState(() {
      _workspaceView = _WorkspaceView.reference;
      _refImg = item.bytes;
      _refCropApplied = true;
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

  // ── Калибровка: пошаговая расстановка точек прямо на панелях ───────────
  Future<void> _startCalibration() async {
    if (_refImg == null || _cmpImg == null) return;
    Size? refSize = _refImgSize;
    Size? cmpSize = _cmpImgSize;
    refSize ??= await _readImageSize(_refImg!);
    cmpSize ??= await _readImageSize(_cmpImg!);
    final storedRefPtsRaw = _layoutProfile?.refAnchors
        .map((a) => Offset(a.x * refSize!.width, a.y * refSize.height))
        .toList();
    final storedRefPts = storedRefPtsRaw?.take(_maxAnchorPts).toList();
    if (!mounted) return;
    final cropTimedSteps =
        _timedSteps.where((step) => step.label.startsWith('Обрезка ')).toList();
    setState(() {
      _calStep =
          storedRefPts == null || storedRefPts.length < _minAnchorPts ? 1 : 2;
      _workspaceView =
          _calStep == 1 ? _WorkspaceView.reference : _WorkspaceView.sample;
      _tempRefPts = storedRefPts ?? [];
      _tempCmpPts = [];
      _refImgSize = refSize;
      _cmpImgSize = cmpSize;
      _cmpAligned = null;
      _cmpAnchorPts = null;
      _result = null;
      _exactDeltaEReady = false;
      _exactDeltaEComputing = false;
      _exactDeltaERequested = false;
      _activeProtocolId = null;
      _activeProtocolCreatedAt = null;
      _activeProtocolSampleImageId = null;
      _activeProtocolSampleNo = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareStatus = null;
      _compareSteps.clear();
      _timedSteps
        ..clear()
        ..addAll(cropTimedSteps);
      _stageWatch = null;
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
      _stageWatch = null;
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
    final usesPrecisionLoupe = _calibrationSettings.loupeEnabled;
    final precise = usesPrecisionLoupe
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

    // В лупе оператор уже выбрал точную точку. Повторный магнит
    // раньше снова декодировал весь файл ради окна 24×24 px.
    // Магнит остаётся для быстрого режима без лупы.
    var refined = precise;
    final shouldRefine =
        !usesPrecisionLoupe && _calibrationSettings.magnetMaxShiftPx > 0.1;
    if (shouldRefine) {
      setState(() => _anchorRefining = true);
      refined = await AnchorRefinementService.refine(
        bytes,
        precise,
        maxShift: _calibrationSettings.magnetMaxShiftPx,
      );
      if (!mounted) return;
    }
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

  Future<void> _showReferencePointHelper(int pointIndex) async {
    final bytes = _refImg;
    final imageSize = _refImgSize;
    if (bytes == null || imageSize == null || _tempRefPts.isEmpty) return;
    final activeIndex = pointIndex.clamp(1, _tempRefPts.length);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReferencePointHelperDialog(
        bytes: bytes,
        imageSize: imageSize,
        points: List<Offset>.from(_tempRefPts),
        activeIndex: activeIndex,
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
    final cropTimedSteps =
        _timedSteps.where((step) => step.label.startsWith('Обрезка ')).toList();
    setState(() {
      _calStep = 2;
      _workspaceView = _WorkspaceView.sample;
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
      _timedSteps
        ..clear()
        ..addAll(cropTimedSteps);
      _stageWatch = null;
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
      _startTimedStage('Расчёт совмещения по ${refPts.length} точкам...');
      final alignResult = await OpenCvService.alignByAnchors(
        _refImg!,
        _cmpImg!,
        refPts,
        cmpPts,
      );
      _finishTimedStage(label: 'Расчёт совмещения');
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
      if (!mounted) return;
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
          '"$name"\nТочность точек: ${alignResult.reprojError.toStringAsFixed(1)} пкс. Профиль готов к работе.',
        );
      }
    } finally {
      _finishTimedStage(label: 'Расчёт совмещения');
      if (mounted) {
        setState(() {
          _calibrating = false;
          if (_calStep == 3) _calStep = 0;
        });
      }
    }
    if (shouldRunCompare && mounted) {
      await _yieldUi();
      await _runCompare();
    }
  }

  // Validation dialog — возвращает true если пользователь принял результат
  Future<bool> _showAlignmentValidation(
    AlignByAnchorsResult r, {
    bool confirmOnly = false,
    bool canAccept = true,
  }) async {
    final status = !canAccept
        ? 'Точки не совпадают'
        : r.reprojError < 3.0
            ? 'Точки совмещены точно'
            : r.reprojError < 6.0
                ? 'Точки совмещены'
                : 'Проверьте точки';
    final color = !canAccept
        ? Colors.red
        : r.reprojError < 3.0
            ? Colors.green
            : r.reprojError < 6.0
                ? Colors.lightGreen
                : Colors.orange;
    final hasImageCorrelation = r.eccScore > 0.0;

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.tune, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _validationRow(
                  'Точность точек',
                  '${r.reprojError.toStringAsFixed(2)} пкс',
                  r.reprojError < 3.0 ? Colors.green : Colors.orange,
                ),
                if (hasImageCorrelation)
                  _validationRow(
                    'Сходство структуры',
                    '${(r.eccScore * 100).toStringAsFixed(1)}%',
                    r.eccScore > 0.9 ? Colors.green : Colors.orange,
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
    CameraCalibrationProfileService.activeProfileNotifier.removeListener(
      _onCameraCalibrationProfile,
    );
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
        _refCropApplied = false;
        _refImgSize = sz;
        _savedRefLabel = null;
        _activeReferenceId = null;
        _refAligned = null;
        _layoutProfile = null;
        _refAnchorPts = null;
        _result = null;
        _compareStatus = null;
      });
    } finally {
      if (mounted) setState(() => _stacking = false);
    }
  }

  // ── AI анализ через Claude Vision ─────────────────
  Future<void> _runAiAnalysis() async {
    if (!_allows(ProductCapability.aiAnalysis)) {
      _showPlanRequired('AI-анализ');
      return;
    }
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
  String _fmtDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '$ms мс';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)} сек';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes мин ${rest.toStringAsFixed(0)} сек';
  }

  void _finishTimedStage({String? label}) {
    final watch = _stageWatch;
    final title = label ?? _compareStatus;
    if (watch == null || title == null) return;
    watch.stop();
    _stageWatch = null;
    if (!mounted) return;
    setState(() {
      _timedSteps.add(_TimedStep(title, watch.elapsed));
    });
  }

  void _startTimedStage(String message) {
    _finishTimedStage();
    _stageWatch = Stopwatch()..start();
    _setCompareStatus(message);
  }

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
    if (_cloudJobId != null && _cloudJobId!.isNotEmpty) return _cloudJobId!;
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

  String get _currentCustomerName => _customerConfirmed
      ? _selectedCustomerName
      : _requestedCustomerName.trim();

  bool get _hasRequiredJobContext {
    if (widget.organizationAccess.organizationId == null) return true;
    if (_currentJobNumber.isEmpty) return false;
    return _currentCustomerName.isNotEmpty;
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
    if (!_allows(ProductCapability.runInspection)) {
      _showPlanRequired('Сравнение изображений');
      return;
    }
    if (!widget.organizationAccess
        .allows(OrganizationPermission.runInspection)) {
      xpDlg(
        context,
        'Нет права',
        'Роль «${widget.organizationAccess.role.label}» не может запускать проверки.',
      );
      return;
    }
    if (!await _hasDailyCheckQuota() || !mounted) return;
    if (!_hasRequiredJobContext) {
      xpDlg(
        context,
        'Работа не задана',
        widget.organizationAccess.organizationId == null
            ? 'Введите номер работы.'
            : 'Введите номер работы и выберите заказчика.',
      );
      return;
    }
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
    final preservedTimedSteps = _timedSteps
        .where(
          (s) =>
              s.label.startsWith('Обрезка ') ||
              s.label.startsWith('Расчёт совмещения'),
        )
        .toList();
    setState(() {
      _comparing = true;
      _workspaceView = _WorkspaceView.comparison;
      _inspectionTool = null;
      _aiResult = null;
      _refBarcodes = [];
      _cmpBarcodes = [];
      _textDiff = null;
      _refLabFingerprint = null;
      _cmpLabFingerprint = null;
      _labFingerprintMatch = null;
      _result = null;
      _exactDeltaEReady = false;
      _exactDeltaEComputing = false;
      _exactDeltaERequested = false;
      _activeProtocolId = null;
      _activeProtocolCreatedAt = null;
      _activeProtocolSampleImageId = null;
      _activeProtocolSampleNo = null;
      _pointProbe = null;
      _areaLoupe = null;
      _loupeDraftRect = null;
      _loupeDragStart = null;
      _compareSteps
        ..clear()
        ..add('Готовлю изображения к проверке...');
      _timedSteps
        ..clear()
        ..addAll(preservedTimedSteps);
      _stageWatch = null;
      _compareStatus = 'Готовлю изображения к проверке...';
      _resultMapMode = _ResultMapMode.geometry;
    });
    _resultCmpCtrl.value = Matrix4.identity();
    try {
      _startTimedStage(
        'Этап 1/4: проверяю ч/б геометрию и Delta E уровня 2...',
      );
      await _yieldUi();
      final measurementSettings = await ColorMeasurementSettingsService.load();
      final cameraCaptureSettings = await CameraCaptureSettingsService.load();
      if (!mounted) return;
      setState(() {
        _measurementSettings = measurementSettings;
        _cameraCaptureSettings = cameraCaptureSettings;
      });
      final compareResult = await CompareService.compare(
        ref,
        cmp,
        pixelStep: 2,
        measurementSettings: measurementSettings,
        onProgress: (message) => _setCompareStatus(message),
      );
      if (!mounted) return;
      setState(() {
        _result = compareResult;
      });
      _finishTimedStage(label: 'ЧБ геометрия и Delta E (уровень 2)');
      _setCompareStatus(_geometryStatusLine(compareResult));

      if (_allows(ProductCapability.barcode)) {
        _startTimedStage('Этап 2/4: проверяю штрихкоды и QR...');
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
        _finishTimedStage(label: 'Штрихкоды и QR');
      } else {
        _setCompareStatus('Штрихкоды: этап не входит в текущий план.');
      }

      if (_allows(ProductCapability.ocr)) {
        _startTimedStage('Этап 3/4: проверяю текст OCR...');
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
          _textDiff = (!ro.isEmpty || !co.isEmpty)
              ? OcrService.compareTexts(ro.fullText, co.fullText)
              : null;
        });
        _setCompareStatus(
          _textDiff == null
              ? 'OCR: распознанного текста для вычитки нет.'
              : 'OCR: совпадение текста ${_textDiff!.similarity.toStringAsFixed(1)}%.',
        );
        _finishTimedStage(label: 'OCR / текст');
      } else {
        _setCompareStatus('OCR: этап не входит в текущий план.');
      }

      _startTimedStage('Этап 4/4: строю Lab ID и сохраняю протокол...');
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
      _finishTimedStage(label: 'Lab ID');

      try {
        await _saveCheckResult();
        _setCompareStatus(
          'Предварительная проверка готова. '
          'Откройте «ΔE цвет» для точного расчёта.',
        );
      } on DailyCheckLimitException catch (error) {
        _showDailyCheckLimit(error.snapshot);
        _setCompareStatus('Проверка завершена, но дневной лимит уже исчерпан.');
      } catch (_) {
        _setCompareStatus(
          'Проверка завершена. Локальный протокол не сохранён.',
        );
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка сравнения', e.toString());
    } finally {
      _finishTimedStage();
      if (mounted) setState(() => _comparing = false);
      if (mounted && _exactDeltaERequested && _result != null) {
        setState(() => _exactDeltaERequested = false);
        await _runExactDeltaE();
      }
    }
  }

  // ── Сводные значения по Lab-зонам ────────────────
  Future<void> _selectResultMapMode(_ResultMapMode mode) async {
    if (mounted) {
      setState(() {
        _resultMapMode = mode;
        if (_inspectionTool == _InspectionTool.point) {
          _inspectionTool = null;
          _pointProbe = null;
        }
        if (mode != _ResultMapMode.deltaE) {
          _exactDeltaERequested = false;
        }
      });
    }
    if (mode != _ResultMapMode.deltaE ||
        _result == null ||
        _exactDeltaEReady ||
        _exactDeltaEComputing) {
      return;
    }
    if (!_allows(ProductCapability.exactDeltaE)) {
      _setCompareStatus(
        'Открыта предварительная карта Delta E. Точный расчёт не входит в текущий план.',
      );
      return;
    }
    if (_comparing) {
      setState(() => _exactDeltaERequested = true);
      _setCompareStatus(
        'Точная Delta E добавлена в очередь после OCR и Lab ID.',
      );
      return;
    }
    await _runExactDeltaE();
  }

  Future<void> _runExactDeltaE() async {
    if (!_allows(ProductCapability.exactDeltaE)) {
      _showPlanRequired('Точная Delta E');
      return;
    }
    final ref = _refAligned ?? _refImg;
    final cmp = _cmpAligned ?? _cmpImg;
    final preliminary = _result;
    if (ref == null || cmp == null || preliminary == null) return;

    setState(() => _exactDeltaEComputing = true);
    _startTimedStage('Точная Delta E: проверяю каждый пиксель...');
    try {
      await _yieldUi();
      final exactFuture = CompareService.compare(
        ref,
        cmp,
        pixelStep: 1,
        includeGeometry: false,
        includeCanonical: false,
        measurementSettings: _measurementSettings,
        onProgress: (message) => _setCompareStatus(message),
      );
      final labFuture = OpenCvService.compareImages(ref, cmp);
      final exact = await exactFuture;
      final lab = await labFuture;
      if (!mounted) return;
      final current = _result ?? preliminary;
      setState(() {
        _result = CompareResult(
          similarity: exact.similarity,
          ssim: current.ssim,
          labScore: lab?.score ?? current.labScore,
          labLevel0: lab?.level0 ?? current.labLevel0,
          labLevel1: lab?.level1 ?? current.labLevel1,
          labLevel2: lab?.level2 ?? current.labLevel2,
          labLevel3: lab?.level3 ?? current.labLevel3,
          shiftDL: lab?.shiftDL ?? current.shiftDL,
          shiftDA: lab?.shiftDA ?? current.shiftDA,
          shiftDB: lab?.shiftDB ?? current.shiftDB,
          meanDeltaE: exact.meanDeltaE,
          maxDeltaE: exact.maxDeltaE,
          defectZoneCount: exact.defectZoneCount,
          defectAreaPercent: exact.defectAreaPercent,
          refCanonical: exact.refCanonical ?? current.refCanonical,
          cmpCanonical: exact.cmpCanonical ?? current.cmpCanonical,
          diffPixels: exact.diffPixels,
          totalPixels: exact.totalPixels,
          refSize: exact.refSize,
          cmpSize: exact.cmpSize,
          diffL3: exact.diffL3,
          geometryScore: current.geometryScore,
          geometryShiftPx: current.geometryShiftPx,
          geometryMissingPercent: current.geometryMissingPercent,
          geometryExtraPercent: current.geometryExtraPercent,
          geometryOverlapPixels: current.geometryOverlapPixels,
          geometryMissingPixels: current.geometryMissingPixels,
          geometryExtraPixels: current.geometryExtraPixels,
          geometryDiff: current.geometryDiff,
          geometryRefCanonical: current.geometryRefCanonical,
          geometryCmpCanonical: current.geometryCmpCanonical,
        );
        _exactDeltaEReady = true;
      });
      _finishTimedStage(label: 'Точная Delta E (все пиксели)');
      _setCompareStatus(
        'Точная ${_measurementSettings.deltaEFormula.shortLabel} готова: max ${_fmt(exact.maxDeltaE)}, '
        'среднее ${_fmt(exact.meanDeltaE)}.',
      );
      try {
        await _saveCheckResult();
      } on DailyCheckLimitException catch (error) {
        _showDailyCheckLimit(error.snapshot);
        _setCompareStatus('Точная Delta E готова, дневной лимит уже исчерпан.');
      } catch (_) {
        _setCompareStatus(
          'Точная Delta E готова. Локальный протокол не обновлён.',
        );
      }
    } catch (e) {
      if (mounted) {
        xpDlg(context, 'Ошибка Delta E', e.toString());
      }
    } finally {
      _finishTimedStage();
      if (mounted) setState(() => _exactDeltaEComputing = false);
    }
  }

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
        name: _exactDeltaEReady
            ? 'Цветовая карта ${_measurementSettings.deltaEFormula.shortLabel}'
            : 'Цветовая карта ${_measurementSettings.deltaEFormula.shortLabel} (уровень 2)',
        status: _exactDeltaEReady
            ? (colorOk ? 'OK' : 'Внимание')
            : 'Предварительно',
        metric:
            'max ${_fmt(r.maxDeltaE)} · среднее ${_fmt(r.meanDeltaE)} · ${r.diffPercent.toStringAsFixed(1)}%',
        comment: !_exactDeltaEReady
            ? 'Быстрая оценка через пиксель. Для точного заключения откройте «ΔE цвет».'
            : colorOk
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
      if (_timedSteps.isNotEmpty)
        CheckProtocolStage(
          name: 'Время обработки',
          status: 'INFO',
          metric: _timingSummary(),
          comment: 'Локальные замеры этапов этой проверки.',
        ),
      CheckProtocolStage(
        name: 'Итог',
        status: _exactDeltaEReady ? _overallStatus(r.score) : 'Предварительно',
        metric: '${r.score.toStringAsFixed(1)}%',
        comment: _exactDeltaEReady
            ? 'Общий результат без отправки в базу.'
            : 'Окончательный PASS/FAIL будет доступен после точной Delta E.',
      ),
    ];
  }

  String _timingSummary() {
    if (_timedSteps.isEmpty) return '-';
    return _timedSteps
        .map((s) => '${s.label}: ${_fmtDuration(s.duration)}')
        .join(' · ');
  }

  String _fmt(num? value) => value == null ? '-' : value.toStringAsFixed(1);

  bool _displayScorePasses(double score) =>
      double.parse(score.toStringAsFixed(1)) >= 90;

  String _fmtDensity(double value) =>
      value.toStringAsFixed(1).replaceAll('.', ',');

  String _densityLine(OpticalDensityMeasurement density) =>
      'C=${_fmtDensity(density.cyan)}  '
      'M=${_fmtDensity(density.magenta)}  '
      'Y=${_fmtDensity(density.yellow)}  '
      'K=${_fmtDensity(density.black)}';

  int _loupeMagnificationPercent() =>
      (_resultCmpCtrl.value.getMaxScaleOnAxis() * 100).round();

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
    if (!_allows(ProductCapability.protocolHistory) &&
        widget.inspectionUnit == null) {
      return;
    }
    final r = _result;
    if (r == null) return;
    final replacingCurrent = _activeProtocolId != null &&
        _activeProtocolCreatedAt != null &&
        _activeProtocolSampleImageId != null &&
        _activeProtocolSampleNo != null;
    final now = replacingCurrent ? _activeProtocolCreatedAt! : DateTime.now();
    final referenceId = _activeReferenceId ?? '';
    final jobNumber = _currentJobNumber;
    final sampleNumber = replacingCurrent
        ? _activeProtocolSampleNo!
        : _nextSampleNumberFor(
            referenceId: referenceId,
            referenceLabel: _savedRefLabel,
            minValue: _sampleNo,
          );
    final sampleImageId = replacingCurrent
        ? _activeProtocolSampleImageId!
        : '$_currentJobId-sample-$sampleNumber-${now.millisecondsSinceEpoch}';
    final protocolId = replacingCurrent
        ? _activeProtocolId!
        : now.millisecondsSinceEpoch.toString();
    if (mounted) setState(() => _sampleNo = sampleNumber);
    final protocol = CheckProtocol(
      id: protocolId,
      createdAt: now,
      jobId: _currentJobId,
      jobNumber: jobNumber,
      customerId: _selectedCustomerId ?? '',
      customerName: _currentCustomerName,
      customerConfirmed: _customerConfirmed,
      score: r.score,
      verdict: _exactDeltaEReady ? _overallStatus(r.score) : 'Предварительно',
      refSize: r.refSize,
      cmpSize: r.cmpSize,
      labId: _shortLabId(_refLabFingerprint?.labId),
      referenceId: referenceId,
      referenceLabel: _savedRefLabel ?? _layoutProfile?.name ?? 'Эталон',
      sampleLabel: 'Отпечаток $sampleNumber',
      sampleImageId: sampleImageId,
      sampleNo: sampleNumber,
      labMatch: _labFingerprintMatch,
      deltaEFormula: _measurementSettings.deltaEFormula.shortLabel,
      captureLighting: _cameraCaptureSettings.lighting.label,
      captureFilter: _cameraCaptureSettings.opticalFilter.label,
      apertureMm: _measurementSettings.aperture.diameterMm,
      stages: _checkProtocolStages(r),
    );
    if (!replacingCurrent && widget.checkUsageService != null) {
      await widget.checkUsageService!.recordCompletedCheck(
        checkId: protocol.id,
        jobId: widget.entitlements.usesOrganizationPlan ? protocol.jobId : null,
      );
      widget.onCheckUsageChanged?.call();
    }
    await CheckHistoryService.saveLast(protocol);
    _cloudProtocolSyncQueue = _cloudProtocolSyncQueue.then(
      (_) => _syncProtocolToCloud(protocol, r.diffL3),
    );
    unawaited(_cloudProtocolSyncQueue);
    if (mounted) {
      setState(() {
        _activeProtocolId = protocolId;
        _activeProtocolCreatedAt = now;
        _activeProtocolSampleImageId = sampleImageId;
        _activeProtocolSampleNo = sampleNumber;
      });
    }
    final unit = widget.inspectionUnit;
    final workflow = widget.productionWorkflowService;
    if (unit != null && workflow != null) {
      await workflow.recordInspectionAttempt(
        unitId: unit.id,
        protocolId: protocolId,
        score: r.score,
      );
      if (mounted &&
          _productionInspectionState != ProductionUnitState.blocked) {
        setState(
            () => _productionInspectionState = ProductionUnitState.checking);
      }
    }
  }

  Future<void> _syncProtocolToCloud(
    CheckProtocol protocol,
    Uint8List? differenceMap,
  ) async {
    final repository = widget.protocolCloudRepository;
    if (repository == null ||
        !_allows(ProductCapability.cloudSync) ||
        !_allows(ProductCapability.cloudAssets)) {
      return;
    }
    final settings = await StorageSettingsService.load();
    if (settings.primaryLocation != AssetStorageLocation.supabaseStorage) {
      return;
    }
    try {
      final preview = differenceMap == null
          ? null
          : await ProtocolPreviewService.create(differenceMap);
      await repository.saveProtocol(protocol, previewPng: preview);
      _setCompareStatus(
        preview == null
            ? 'Протокол сохранён локально и в облаке.'
            : 'Протокол и превью карты отличий сохранены в облаке.',
      );
    } catch (_) {
      _setCompareStatus(
        'Протокол сохранён локально. Облачная копия сейчас не сохранена.',
      );
    }
  }

  String _shortLabId(String? value) {
    if (value == null || value.isEmpty) return '-';
    return value.length <= 8 ? value : value.substring(0, 8);
  }

  // ── Кроп рамкой ──────────────────────────────────
  Future<void> _cropImage(bool isRef) async {
    final src = isRef ? _refImg : _cmpImg;
    if (src == null) return;
    final selection = await CropFrameScreen.show(
      context,
      src,
      title: isRef ? 'Рамка — Эталон' : 'Рамка — Образец',
    );
    if (selection != null && mounted) {
      final cropWatch = Stopwatch()..start();
      final timingLabel = isRef ? 'Обрезка эталона' : 'Обрезка образца';
      var cropCompleted = false;
      setState(() {
        _imageBusy = true;
        _imageBusyLabel = 'Применение границы обработки...';
      });
      try {
        ({Uint8List bytes, int width, int height}) cropped;
        if (web_worker.isWebCompareWorkerSupported) {
          cropped = await web_worker.runWebCropWorker(
            image: src,
            x: selection.x,
            y: selection.y,
            width: selection.width,
            height: selection.height,
            onProgress: (message) {
              if (mounted) setState(() => _imageBusyLabel = message);
            },
          );
        } else {
          final bytes = await CropFrameScreen.apply(src, selection);
          cropped = (
            bytes: bytes,
            width: selection.width,
            height: selection.height,
          );
        }
        if (!mounted) return;
        final newSize = Size(
          cropped.width.toDouble(),
          cropped.height.toDouble(),
        );
        setState(() {
          // Точки незавершённой калибровки (_tempRefPts/_tempCmpPts) записаны
          // в пиксельных координатах старого (необрезанного) изображения —
          // после обрезки они "уезжают" относительно нового кадра, поэтому
          // сбрасываем калибровку целиком, а не только подтверждённые точки.
          _calStep = 0;
          _tempRefPts = [];
          _tempCmpPts = [];
          if (isRef) {
            _workspaceView = _WorkspaceView.reference;
            _refCropApplied = true;
            _layoutProfile = null;
            _refImg = cropped.bytes;
            _refImgSize = newSize;
            _savedRefLabel = null;
            _activeReferenceId = null;
            _refAligned = null;
            _refAnchorPts = null;
          } else {
            _workspaceView = _WorkspaceView.sample;
            _cmpCropApplied = true;
            _cmpImg = cropped.bytes;
            _cmpImgSize = newSize;
            _cmpAligned = null;
            _cmpAnchorPts = null;
          }
        });
        cropCompleted = true;
      } catch (error) {
        if (mounted) {
          xpDlg(context, 'Ошибка применения рамки', error.toString());
        }
      } finally {
        cropWatch.stop();
        if (mounted) {
          setState(() {
            _imageBusy = false;
            if (cropCompleted) {
              _timedSteps.removeWhere((step) => step.label == timingLabel);
              _timedSteps.add(_TimedStep(timingLabel, cropWatch.elapsed));
            }
          });
        }
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
        // Подготавливаем новый эталон и сбрасываем прежний результат.
        if (!mounted) return;
        setState(() {
          _workspaceView = _WorkspaceView.reference;
          _refCropApplied = false;
        });
        await _selectRef(bytes);
      } else {
        final sz = await _readImageSize(bytes);
        if (!mounted) return;
        setState(() {
          _workspaceView = _WorkspaceView.sample;
          _cmpImg = bytes;
          _cmpCropApplied = false;
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
    if (!widget.organizationAccess
        .allows(OrganizationPermission.runInspection)) {
      return _restrictedInspectionView();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(7, 6, 7, 5),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.appBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.workspaceChromeLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180E2A31),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _workspaceCommandBar(),
          Expanded(child: _hudWorkbench()),
        ],
      ),
    );
  }

  Widget _restrictedInspectionView() {
    return Container(
      key: const ValueKey('comparison-role-restricted'),
      margin: const EdgeInsets.fromLTRB(7, 6, 7, 5),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.appBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.workspaceChromeLine),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180E2A31),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.line),
              boxShadow: AppTheme.shadowSubtle,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F1F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    color: Color(0xFF1F747A),
                    size: 27,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Проверку выполняет производственная команда',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.graphite,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Заказчик не загружает эталоны и не запускает сравнение. '
                  'В чате работы доступны только сообщения и файлы, которые '
                  'представитель заказчика со стороны компании отправил ему.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                if (widget.onNavigate != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('comparison-open-chat'),
                    onPressed: () => widget.onNavigate!(2),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Перейти в чат'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _resetComparison() {
    setState(() {
      _workspaceView = _WorkspaceView.reference;
      _refImg = null;
      _refCropApplied = false;
      _refImgSize = null;
      _cmpImg = null;
      _cmpCropApplied = false;
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
      _textDiff = null;
      _resetZoomControllers();
    });
  }

  Widget _workspaceCommandBar() {
    return LayoutBuilder(
      builder: (context, _) {
        return DecoratedBox(
          key: const ValueKey('workspace-command-bar'),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFF223238), Color(0xFF30464D)],
            ),
            border: Border(
              bottom: BorderSide(color: Color(0xFF568087)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  if (widget.onBackToWorks != null) ...[
                    IconButton(
                      key: const ValueKey('back-to-works'),
                      tooltip: widget.backTooltip,
                      onPressed: widget.onBackToWorks,
                      style: _workspaceIconButtonStyle(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(child: _workspaceModeSelector()),
                  const SizedBox(width: 5),
                  if (widget.onNavigate != null) ...[
                    if (widget.canOpenChat)
                      _workspaceAppTool(
                        key: const ValueKey('comparison-open-chat-action'),
                        icon: Icons.chat_bubble_outline_rounded,
                        tooltip: 'Чат',
                        onTap: () => widget.onNavigate!(2),
                      ),
                    _workspaceAppTool(
                      key: const ValueKey('comparison-open-settings-action'),
                      icon: Icons.tune_rounded,
                      tooltip: 'Настройки',
                      onTap: () => widget.onNavigate!(3),
                    ),
                  ],
                  _workspaceOverflowMenu(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _workspaceModeSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: _workspaceModeButton(
            _WorkspaceView.reference,
            'Эталон',
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _workspaceModeButton(
            _WorkspaceView.sample,
            'Образец',
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _workspaceModeButton(
            _WorkspaceView.comparison,
            'Сравнение',
          ),
        ),
      ],
    );
  }

  Widget _workspaceModeButton(
    _WorkspaceView view,
    String label,
  ) {
    final selected = _workspaceView == view;
    final calibrationView = _calStep == 1
        ? _WorkspaceView.reference
        : _calStep == 2 || _calStep == 3
            ? _WorkspaceView.sample
            : null;
    final enabled = _calStep == 0 || calibrationView == view;
    return Tooltip(
      message: label,
      child: InkWell(
        key: ValueKey('workspace-mode-${view.name}'),
        onTap: enabled ? () => _selectWorkspace(view) : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xA34D747A) : const Color(0x38394F55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected ? const Color(0xFF86B5BA) : const Color(0x70677F84),
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x660C171A),
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
              if (selected)
                const BoxShadow(
                  color: Color(0x335EC5CC),
                  blurRadius: 7,
                ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: enabled
                    ? selected
                        ? const Color(0xFFF3FBFC)
                        : const Color(0xFFD1DEE1)
                    : const Color(0xFF7F9298),
                shadows: const [
                  Shadow(color: Color(0x88000000), blurRadius: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _workspaceIconButtonStyle() {
    return IconButton.styleFrom(
      foregroundColor: const Color(0xFFD5E2E5),
      minimumSize: const Size(38, 38),
      maximumSize: const Size(38, 38),
      backgroundColor: const Color(0x4D394F55),
      side: const BorderSide(color: Color(0x70677F84)),
      shadowColor: const Color(0xAA0C171A),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _workspaceAppTool({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: key,
        onPressed: onTap,
        style: _workspaceIconButtonStyle(),
        icon: Icon(icon, size: 19),
      ),
    );
  }

  Widget _workspaceOverflowMenu() {
    return Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: const Color(0x4D394F55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x70677F84)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x660C171A),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Ещё',
        padding: EdgeInsets.zero,
        color: const Color(0xFFF7FAFC),
        icon: const Icon(
          Icons.more_horiz_rounded,
          size: 19,
          color: Color(0xFFD5E2E5),
        ),
        onSelected: _handleWorkspaceMenu,
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'steps', child: Text('Все этапы')),
          PopupMenuItem(value: 'data', child: Text('Данные и параметры')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'new', child: Text('Новая проверка')),
          PopupMenuItem(value: 'save', child: Text('Сохранить результат')),
          PopupMenuItem(value: 'export', child: Text('Экспорт…')),
          PopupMenuItem(value: 'ai', child: Text('AI-анализ')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'shortcuts', child: Text('Горячие клавиши')),
        ],
      ),
    );
  }

  Future<void> _handleWorkspaceMenu(String value) async {
    switch (value) {
      case 'steps':
        _showWorkflowSheet();
      case 'data':
        _showInspectorSheet();
      case 'new':
        _resetComparison();
      case 'save':
        if (_result == null) {
          xpDlg(context, 'Ошибка', 'Сначала выполните сравнение');
          return;
        }
        try {
          await _saveCheckResult();
          if (mounted) {
            xpDlg(context, 'Сохранено', 'Результат сохранён в историю');
          }
        } catch (error) {
          if (mounted) xpDlg(context, 'Ошибка сохранения', error.toString());
        }
      case 'export':
        xpDlg(context, 'Экспорт', 'Форматы: PNG, PDF, CSV');
      case 'ai':
        _runAiAnalysis();
      case 'shortcuts':
        xpDlg(
          context,
          'Горячие клавиши',
          'Ctrl+N — Новое\nCtrl+S — Сохранить\nCtrl+E — Экспорт\nCtrl+R — Повернуть\nCtrl+T — Захватить\nCtrl++/- — Зум',
        );
    }
  }

  Widget _hudWorkbench() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: Scrollbar(
                controller: _workspaceScrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _workspaceScrollCtrl,
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: max(0, constraints.maxHeight - 24),
                    ),
                    child: _workspaceBody(),
                  ),
                ),
              ),
            ),
            if (_calStep == 0) ...[
              Positioned(
                top: 12,
                left: 12,
                child: _activeStatusHud(maxWidth: constraints.maxWidth),
              ),
            ],
            if (_workspaceView != _WorkspaceView.comparison || _result == null)
              Positioned(
                right: 12,
                bottom: 12,
                left: 12,
                child: _activeParameterStrip(),
              ),
          ],
        );
      },
    );
  }

  _WorkflowAction _currentWorkflowAction(List<_WorkflowAction> actions) {
    for (final action in actions) {
      if (action.active || action.busy) return action;
    }
    if (_result != null) return actions[6];
    for (final action in actions) {
      if (!action.done && action.onTap != null) return action;
    }
    return actions.last;
  }

  Widget _activeStatusHud({required double maxWidth}) {
    final narrow = maxWidth < 620;
    final width = narrow ? min(148.0, (maxWidth - 30) * 0.46) : 230.0;
    final result = _result;
    final status = result == null
        ? _canStartCompareAction
            ? 'ГОТОВО К СРАВНЕНИЮ'
            : 'ПОДГОТОВКА'
        : !_exactDeltaEReady
            ? 'ПРЕДВАРИТЕЛЬНО'
            : _shortStatus(result.score).toUpperCase();
    final statusColor = result == null
        ? _hudGreen
        : !_exactDeltaEReady
            ? _hudWarning
            : _displayScorePasses(result.score)
                ? _hudGreen
                : _hudError;
    Widget line(
      String keyLabel,
      String value,
      Color color, {
      bool uppercase = true,
      double top = 5,
    }) {
      return Padding(
        padding: EdgeInsets.only(top: top),
        child: Tooltip(
          message: value,
          child: PixelText(
            key: ValueKey('active-status-value-$keyLabel'),
            text: value,
            color: color,
            pixelSize: 1.15,
            uppercase: uppercase,
          ),
        ),
      );
    }

    List<Widget> densityLines(
      String keyPrefix,
      String title,
      OpticalDensityMeasurement density,
    ) {
      return [
        line('$keyPrefix-title', title, _hudGreen, top: 8),
        line(
          '$keyPrefix-c',
          'Dc=${_fmtDensity(density.cyan)}',
          _hudGreenSecondary,
          uppercase: false,
          top: 4,
        ),
        line(
          '$keyPrefix-m',
          'Dm=${_fmtDensity(density.magenta)}',
          _hudGreenSecondary,
          uppercase: false,
          top: 4,
        ),
        line(
          '$keyPrefix-y',
          'Dy=${_fmtDensity(density.yellow)}',
          _hudGreenSecondary,
          uppercase: false,
          top: 4,
        ),
        line(
          '$keyPrefix-k',
          'Dk=${_fmtDensity(density.black)}',
          _hudGreenSecondary,
          uppercase: false,
          top: 4,
        ),
      ];
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: PixelText(
                      key: const ValueKey('current-status-text'),
                      text: status,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              if (_currentJobNumber.isNotEmpty)
                line('РАБОТА', _currentJobNumber, _hudGreen),
              if (!narrow && _currentCustomerName.isNotEmpty)
                line(
                  'ЗАКАЗЧИК',
                  _currentCustomerName,
                  _hudGreenSecondary,
                ),
              if (result != null)
                line(
                  'СХОДСТВО',
                  '${result.score.toStringAsFixed(1)}%',
                  _displayScorePasses(result.score) ? _hudGreen : _hudError,
                ),
              if (result != null &&
                  _inspectionTool == _InspectionTool.point) ...[
                if (_pointProbe == null)
                  line(
                    'point-hint',
                    'НАЖМИТЕ НА ИЗОБРАЖЕНИЕ',
                    _hudGreenSecondary,
                    top: 8,
                  )
                else ...[
                  line(
                    'point-delta',
                    '${_pointProbe!.formulaLabel}=${_pointProbe!.deltaE.toStringAsFixed(2).replaceAll('.', ',')}',
                    _pointProbe!.deltaE <= 3 ? _hudGreen : _hudError,
                    top: 8,
                  ),
                  line(
                    'point-source',
                    _pointProbe!.measurementSource.toUpperCase(),
                    _hudGreenSecondary,
                    top: 4,
                  ),
                  ...densityLines(
                    'point-reference',
                    'ЭТАЛОН',
                    _pointProbe!.refDensity,
                  ),
                  ...densityLines(
                    'point-sample',
                    'ОБРАЗЕЦ',
                    _pointProbe!.cmpDensity,
                  ),
                ],
              ] else if (result != null &&
                  _inspectionTool == _InspectionTool.loupe) ...[
                line(
                  'loupe-status',
                  _areaLoupe == null
                      ? 'ВЫДЕЛИТЕ ОБЛАСТЬ'
                      : 'УВЕЛИЧЕНИЕ ${_loupeMagnificationPercent()}%',
                  _hudGreenSecondary,
                  top: 8,
                ),
              ] else if (result != null) ...[
                line(
                  'result-difference',
                  'ОТЛИЧИЯ ${result.diffPercent.toStringAsFixed(1)}%',
                  statusColor,
                  top: 8,
                ),
                if (result.maxDeltaE != null)
                  line(
                    'result-delta-max',
                    'MAX ΔE ${result.maxDeltaE!.toStringAsFixed(1)}',
                    statusColor,
                    top: 4,
                  ),
                if (result.defectZoneCount != null)
                  line(
                    'result-zones',
                    'ЗОНЫ ${result.defectZoneCount}',
                    statusColor,
                    top: 4,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _WorkflowAction? _primaryScreenAction() {
    if (_result != null || _calStep != 0) return null;
    final actions = _workflowActions();
    final action = _currentWorkflowAction(actions);
    return action.number == '8' ? null : action;
  }

  String _screenActionLabel(_WorkflowAction action) {
    return switch (action.number) {
      '1' => 'Указать работу',
      '2' => 'Загрузить эталон',
      '3' => 'Выделить область эталона',
      '4' => 'Загрузить образец',
      '5' => 'Выделить область образца',
      '6' => 'Совместить изображения',
      '7' => 'Запустить сравнение',
      _ => _aiResult == null ? 'Запустить AI' : 'Повторить AI',
    };
  }

  Widget _screenActionPrompt(_WorkflowAction action) {
    final enabled = action.onTap != null && !action.busy;
    final label = action.busy ? 'Выполняется…' : _screenActionLabel(action);
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: enabled ? Colors.white : const Color(0xFFBAC8CC),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(color: Color(0xFF081519), blurRadius: 4),
                Shadow(color: Color(0xFF081519), blurRadius: 12),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 5),
            const Text(
              'Нажмите на экран',
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFFD7EDF2),
                fontFamily: 'monospace',
                letterSpacing: 0.7,
                shadows: [
                  Shadow(color: Color(0xFF081519), blurRadius: 7),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activeParameterStrip() {
    final result = _result;
    final items = <String>[];
    if (_calStep == 1) {
      items.add('ЭТАЛОН ${_tempRefPts.length}/$_minAnchorPts ТОЧКИ');
    } else if (_calStep == 2 || _calStep == 3) {
      items.add('ОБРАЗЕЦ ${_tempCmpPts.length}/${_tempRefPts.length} ТОЧЕК');
    } else if (_compareStatus != null && _comparing) {
      items.add(_compareStatus!.toUpperCase());
    } else if (result != null) {
      if (_loupeDragStart != null) {
        items.add('ВЫДЕЛИТЕ ОБЛАСТЬ НА ИЗОБРАЖЕНИИ');
      } else if (_inspectionTool == _InspectionTool.point) {
        final probe = _pointProbe;
        if (probe == null) {
          items.add('НАЖМИТЕ НА ИЗОБРАЖЕНИЕ');
        } else {
          items.add('${probe.formulaLabel} ${probe.deltaE.toStringAsFixed(2)}');
          items.add(probe.measurementSource.toUpperCase());
          items.add('ЭТАЛОН ${_densityLine(probe.refDensity)}');
          items.add('ОБРАЗЕЦ ${_densityLine(probe.cmpDensity)}');
        }
      } else if (_inspectionTool == _InspectionTool.loupe) {
        final loupe = _areaLoupe;
        if (loupe == null) {
          items.add('ЗАЖМИТЕ И ПРОТЯНИТЕ ПО ИЗОБРАЖЕНИЮ');
        } else {
          items.add('УВЕЛИЧЕНИЕ ${_loupeMagnificationPercent()}%');
          items.add('ПОВТОРНОЕ НАЖАТИЕ — СБРОС');
        }
      } else {
        items.add('СХОДСТВО ${result.score.toStringAsFixed(1)}%');
        items.add('ОТЛИЧИЯ ${result.diffPercent.toStringAsFixed(1)}%');
        if (result.maxDeltaE != null) {
          items.add('MAX ΔE ${result.maxDeltaE!.toStringAsFixed(1)}');
        }
        if (result.defectZoneCount != null) {
          items.add('ЗОНЫ ${result.defectZoneCount}');
        }
        if (_areaLoupe != null ||
            (_loupeMagnificationPercent() - 100).abs() > 1) {
          items.add('УВЕЛИЧЕНИЕ ${_loupeMagnificationPercent()}%');
        }
      }
    } else {
      switch (_workspaceView) {
        case _WorkspaceView.reference:
          items.add(_refImg == null ? 'ЭТАЛОН НЕ ЗАГРУЖЕН' : 'ЭТАЛОН ГОТОВ');
        case _WorkspaceView.sample:
          items.add(_cmpImg == null ? 'ОБРАЗЕЦ НЕ ЗАГРУЖЕН' : 'ОБРАЗЕЦ ГОТОВ');
        case _WorkspaceView.comparison:
          items.add('ОЖИДАНИЕ СРАВНЕНИЯ');
      }
    }

    return Semantics(
      label: items.join(' · '),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (var index = 0; index < items.length; index++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (index > 0) ...[
                      Container(
                        width: 3,
                        height: 3,
                        color: _hudGreenLabel,
                      ),
                      const SizedBox(width: 9),
                    ],
                    PixelText(
                      key: ValueKey('active-parameter-$index'),
                      text: items[index],
                      color: index == 0 ? _hudGreen : _hudGreenSecondary,
                      pixelSize: 1.35,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWorkflowSheet() {
    final actions = _workflowActions();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F7F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: [
              _sheetHeader('Все этапы', () => Navigator.pop(sheetContext)),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: actions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final action = actions[index];
                    return _workflowActionTile(
                      _WorkflowAction(
                        action.number,
                        action.label,
                        action.icon,
                        done: action.done,
                        active: action.active,
                        busy: action.busy,
                        onTap: action.onTap == null
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                action.onTap!();
                              },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInspectorSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F7F8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: Column(
            children: [
              _sheetHeader(
                'Данные и параметры',
                () => Navigator.pop(sheetContext),
              ),
              Expanded(child: _inspectorPanel(compact: true)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetHeader(String title, VoidCallback onClose) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Закрыть',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _resultModeHud() {
    Widget mode(
      _ResultMapMode value,
      String label,
      String tooltip,
      IconData icon,
    ) {
      final selected =
          _inspectionTool != _InspectionTool.point && _resultMapMode == value;
      return Expanded(
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            key: ValueKey('result-mode-${value.name}'),
            onTap: () => _selectResultMapMode(value),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFBEDDE0) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected
                        ? const Color(0xFF1F747A)
                        : const Color(0xFF6B7C83),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? const Color(0xFF195F64)
                            : AppTheme.graphiteSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget pointMode() {
      final selected = _inspectionTool == _InspectionTool.point;
      return Expanded(
        child: Tooltip(
          message: 'Контроль точки',
          child: InkWell(
            key: const ValueKey('result-mode-point'),
            onTap: () => _toggleInspectionTool(_InspectionTool.point),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFBEDDE0) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.gps_fixed,
                    size: 17,
                    color: selected
                        ? const Color(0xFF1F747A)
                        : const Color(0xFF6B7C83),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Контроль точки',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? const Color(0xFF195F64)
                            : AppTheme.graphiteSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Режим изображения',
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppTheme.workspaceChrome,
          border: Border(
            top: BorderSide(color: AppTheme.workspaceChromeLine),
          ),
        ),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              mode(
                _ResultMapMode.deltaE,
                _exactDeltaEComputing
                    ? 'ΔE · расчёт'
                    : _exactDeltaEReady
                        ? 'ΔE · точно'
                        : _allows(ProductCapability.exactDeltaE)
                            ? 'ΔE цвет'
                            : 'ΔE · оценка',
                'Цветовая карта Delta E',
                Icons.palette_outlined,
              ),
              mode(
                _ResultMapMode.geometry,
                'Геометрия ЧБ',
                'Геометрия чёрно-белого изображения',
                Icons.contrast,
              ),
              mode(
                _ResultMapMode.overlay,
                'Наложение',
                'Наложение эталона и образца',
                Icons.layers_outlined,
              ),
              pointMode(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparisonLoupeControl() {
    return AnimatedBuilder(
      animation: _resultCmpCtrl,
      builder: (context, _) {
        final scale = _loupeMagnificationPercent();
        final active = _loupeDragStart != null ||
            _areaLoupe != null ||
            (scale - 100).abs() > 1;
        return Tooltip(
          message: active ? 'Сбросить увеличение' : 'Увеличить область',
          child: InkWell(
            key: const ValueKey('result-loupe-control'),
            onTap: _toggleAreaLoupeControl,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 48,
              height: 50,
              decoration: BoxDecoration(
                color:
                    active ? const Color(0xE0354146) : const Color(0xC52A363A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? const Color(0xFFFFA23F)
                      : const Color(0xFF66858B),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.zoom_out_map_rounded : Icons.zoom_in_rounded,
                    size: 22,
                    color: active ? const Color(0xFFFFA23F) : _hudGreen,
                  ),
                  PixelText(
                    text: '$scale%',
                    color: active ? const Color(0xFFFFA23F) : _hudGreen,
                    pixelSize: 0.9,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggleAreaLoupeControl() {
    final scale = _resultCmpCtrl.value.getMaxScaleOnAxis();
    final reset = _loupeDragStart != null ||
        _loupeDraftRect != null ||
        _areaLoupe != null ||
        (scale - 1).abs() > 0.01;
    if (reset) {
      _resultCmpCtrl.value = Matrix4.identity();
      setState(() {
        _areaLoupe = null;
        _loupeDraftRect = null;
        _loupeDragStart = null;
        _loupeImageSize = null;
      });
      return;
    }
    setState(() {
      // Offset.infinite marks the one-shot selection as armed. Pan start
      // replaces it with the first real image coordinate.
      _loupeDragStart = Offset.infinite;
      _loupeDraftRect = null;
    });
  }

  List<_WorkflowAction> _workflowActions() {
    final personal = widget.organizationAccess.organizationId == null;
    final hasJob = _hasRequiredJobContext;
    final hasRef = _refImg != null;
    final hasSample = _cmpImg != null;
    final aligned = _canRunAlignedCompare;
    // Загрузка или обрезка образца не завершает рамку эталона. Иначе при
    // подготовке файлов в обратном порядке действие «Рамка эталона» исчезало.
    final refCropDone = _refCropApplied || aligned || _result != null;
    final sampleCropDone = _cmpCropApplied || aligned || _result != null;
    return [
      _WorkflowAction(
        '1',
        personal
            ? 'Личная проверка'
            : widget.initialJob == null
                ? 'Работа и заказчик'
                : 'Работа ${_currentJobNumber.trim()}',
        Icons.assignment_outlined,
        done: hasJob,
        active: !hasJob,
        onTap: personal
            ? null
            : widget.initialJob == null
                ? _editJobNumber
                : null,
      ),
      _WorkflowAction(
        '2',
        'Загрузить эталон',
        Icons.upload_file,
        done: hasRef,
        active: hasJob && !hasRef,
        onTap: _imageBusy
            ? null
            : () {
                _selectWorkspace(_WorkspaceView.reference);
                _pickImage(true);
              },
      ),
      _WorkflowAction(
        '3',
        'Рамка эталона',
        Icons.crop,
        done: refCropDone,
        active: hasRef && !refCropDone,
        onTap: hasRef && !_imageBusy ? () => _cropImage(true) : null,
      ),
      _WorkflowAction(
        '4',
        'Загрузить отпечаток',
        Icons.add_a_photo_outlined,
        done: hasSample,
        active: hasRef && refCropDone && !hasSample,
        onTap: hasRef && !_imageBusy
            ? () {
                _selectWorkspace(_WorkspaceView.sample);
                _pickImage(false);
              }
            : null,
      ),
      _WorkflowAction(
        '5',
        'Рамка отпечатка',
        Icons.crop,
        done: sampleCropDone,
        active: hasSample && !sampleCropDone,
        onTap: hasSample && !_imageBusy ? () => _cropImage(false) : null,
      ),
      _WorkflowAction(
        '6',
        'Совмещение',
        Icons.control_camera_outlined,
        done: aligned,
        active: hasRef && hasSample && !aligned,
        busy: _calibrating,
        onTap:
            hasRef && hasSample && !_imageBusy && !_calibrating && _calStep == 0
                ? _startCalibration
                : null,
      ),
      _WorkflowAction(
        '7',
        _result == null ? 'Сравнить' : 'Сравнить повторно',
        Icons.compare,
        done: _result != null,
        active: _result == null && _canStartCompareAction,
        busy: _comparing,
        onTap: _canStartCompareAction && !_comparing && !_imageBusy
            ? _runCompare
            : null,
      ),
      _WorkflowAction(
        '8',
        _aiLoading
            ? 'AI-анализ...'
            : _aiResult == null
                ? 'AI-анализ'
                : 'Повторить AI-анализ',
        Icons.auto_awesome_outlined,
        done: _aiResult != null,
        active: _result != null && _aiResult == null,
        busy: _aiLoading,
        onTap: _result != null && !_aiLoading && !_comparing
            ? _runAiAnalysis
            : null,
      ),
    ];
  }

  Widget _workflowActionTile(_WorkflowAction action) {
    final enabled = action.onTap != null;
    final color = action.done
        ? AppTheme.simHigh
        : action.active
            ? AppTheme.blue
            : enabled
                ? const Color(0xFF64748B)
                : Colors.grey.shade500;
    return Tooltip(
      message: action.label,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity:
              enabled || action.done || action.active || action.busy ? 1 : 0.62,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: action.active ? Colors.white : const Color(0xFFF5F7F8),
              border: Border.all(
                color: color.withValues(alpha: action.active ? 0.95 : 0.45),
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: action.active ? AppTheme.shadowSubtle : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white70),
                  ),
                  child: action.busy
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Colors.white,
                          ),
                        )
                      : action.done
                          ? const Icon(
                              Icons.check,
                              size: 15,
                              color: Colors.white,
                            )
                          : Text(
                              action.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.15,
                          color: enabled || action.done
                              ? Colors.black87
                              : Colors.black45,
                          fontWeight: action.active || action.done
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (action.active)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'Следующий шаг',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: AppTheme.blue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(action.icon, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectWorkspace(_WorkspaceView view) {
    final calibrationView = _calStep == 1
        ? _WorkspaceView.reference
        : _calStep == 2 || _calStep == 3
            ? _WorkspaceView.sample
            : null;
    if (calibrationView != null && calibrationView != view) return;
    setState(() {
      _workspaceView = view;
      if (view == _WorkspaceView.comparison) _inspectionTool = null;
    });
  }

  Widget _workspaceBody() {
    if (_calStep != 0) return _calibrationWorkbench();
    return switch (_workspaceView) {
      _WorkspaceView.reference => _referenceWorkspace(),
      _WorkspaceView.sample => _sampleWorkspace(),
      _WorkspaceView.comparison => _comparisonStage(),
    };
  }

  Widget _referenceWorkspace() {
    return _stagePanel(
      title: 'Эталон',
      subtitle: _savedRefLabel != null
          ? 'Сохранён: $_savedRefLabel'
          : (_refImg == null ? 'Загрузите цифровой файл' : 'Эталон готов'),
      bytes: _refImg,
      transformationController: _refAlignCtrl,
      onOpen: _refImg != null ? () => _openFullScreen(_refImg!) : null,
    );
  }

  Widget _sampleWorkspace() {
    return _stagePanel(
      title: 'Образец',
      subtitle: _cmpImg == null
          ? 'Снимите или загрузите проверяемую распечатку'
          : 'Основная зона анализа',
      bytes: _cmpAligned ?? _cmpImg,
      transformationController: _cmpAlignCtrl,
      onOpen: _cmpImg != null
          ? () => _openFullScreen(_cmpAligned ?? _cmpImg!)
          : null,
    );
  }

  Widget _stagePanel({
    required String title,
    required String subtitle,
    required Uint8List? bytes,
    required TransformationController transformationController,
    VoidCallback? onOpen,
  }) {
    const ratio = 16 / 9;
    final busy = _stacking || _imageBusy;
    final busyLabel = _stacking ? 'Объединение снимков...' : _imageBusyLabel;
    final action = _primaryScreenAction();
    final actionTap = action?.busy == false ? action?.onTap : null;
    return Semantics(
      label: '$title. $subtitle',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: ratio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.canvas,
              border: Border.all(color: const Color(0xFF69757A)),
            ),
            child: busy
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF75DEE8),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          busyLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9FB3BC),
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bytes == null)
                        const WorkspacePhotoBackground()
                      else
                        ClipRect(
                          child: InteractiveViewer(
                            transformationController: transformationController,
                            boundaryMargin: const EdgeInsets.all(80),
                            minScale: 0.5,
                            maxScale: 10.0,
                            panEnabled: _ctrlHeld,
                            scaleEnabled: _ctrlHeld,
                            child: SizedBox.expand(
                              child: _uiImage(bytes, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      if (action != null)
                        Positioned.fill(
                          child: Semantics(
                            button: true,
                            label: _screenActionLabel(action),
                            child: InkWell(
                              key: const ValueKey('workspace-primary-action'),
                              onTap: actionTap,
                              onDoubleTap: onOpen,
                              child: Center(child: _screenActionPrompt(action)),
                            ),
                          ),
                        )
                      else if (onOpen != null)
                        Positioned.fill(
                          child: GestureDetector(onDoubleTap: onOpen),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _comparisonStage() {
    final r = _result;
    final action = _primaryScreenAction();
    final actionTap = action?.busy == false ? action?.onTap : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final viewportHeight =
            constraints.minHeight.isFinite ? constraints.minHeight : 0.0;
        final chromeHeight = r == null
            ? 0.0
            : widget.inspectionUnit == null
                ? 70.0
                : 116.0;
        final naturalHeight = availableWidth * 9 / 16 + chromeHeight;
        final stageHeight = max(viewportHeight, naturalHeight);

        return SizedBox(
          width: double.infinity,
          height: stageHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.appBackground,
                border: Border.all(color: AppTheme.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r != null) ...[
                    Expanded(child: _resultMapOverlay(r)),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        color: AppTheme.workspaceChrome,
                        border: Border(
                          top: BorderSide(
                            color: AppTheme.workspaceChromeLine,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text('Эталон', style: TextStyle(fontSize: 9)),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                value: _diffSlider,
                                onChanged: (v) =>
                                    setState(() => _diffSlider = v),
                                activeColor: AppTheme.blue,
                              ),
                            ),
                          ),
                          Text(
                            _inspectionTool == _InspectionTool.point ||
                                    _resultMapMode == _ResultMapMode.overlay
                                ? 'Образец'
                                : 'Образец + карта',
                            style: const TextStyle(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    _resultModeHud(),
                    if (widget.inspectionUnit != null)
                      _productionInspectionDecisionBar(),
                  ] else if (_comparing)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_refImg == null && _cmpImg == null)
                            const WorkspacePhotoBackground()
                          else
                            const ColoredBox(color: AppTheme.canvas),
                          if (action != null)
                            Positioned.fill(
                              child: Semantics(
                                button: true,
                                label: _screenActionLabel(action),
                                child: InkWell(
                                  key: const ValueKey(
                                    'workspace-primary-action',
                                  ),
                                  onTap: actionTap,
                                  child: Center(
                                    child: _screenActionPrompt(action),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _productionInspectionDecisionBar() {
    final unit = widget.inspectionUnit!;
    final blocked = _productionInspectionState == ProductionUnitState.blocked;
    final approved = _productionInspectionState == ProductionUnitState.approved;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            '${unit.fullLabel} · ${(_productionInspectionState ?? unit.state).label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: blocked
                  ? const Color(0xFFA22D25)
                  : approved
                      ? const Color(0xFF3A6E37)
                      : AppTheme.graphite,
            ),
          ),
        ),
        const SizedBox(width: 7),
        OutlinedButton.icon(
          key: const ValueKey('repeat-production-comparison'),
          onPressed: _productionDecisionBusy || _comparing ? null : _runCompare,
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: const Text('Сравнить ещё раз'),
        ),
        const SizedBox(width: 6),
        FilledButton.tonalIcon(
          key: const ValueKey('approve-production-unit'),
          onPressed: _productionDecisionBusy || blocked
              ? null
              : () => _decideProductionInspection(
                    ProductionInspectionDecision.approved,
                  ),
          icon: const Icon(Icons.task_alt_rounded, size: 16),
          label: const Text('Допустить'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const ValueKey('block-production-unit'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB53B33),
          ),
          onPressed: _productionDecisionBusy || blocked
              ? null
              : () => _decideProductionInspection(
                    ProductionInspectionDecision.blocked,
                  ),
          icon: const Icon(Icons.block_rounded, size: 16),
          label: const Text('Заблокировать'),
        ),
      ]),
    );
  }

  Future<void> _decideProductionInspection(
    ProductionInspectionDecision decision,
  ) async {
    final unit = widget.inspectionUnit;
    final workflow = widget.productionWorkflowService;
    if (unit == null || workflow == null || _result == null) return;
    var note = '';
    if (decision == ProductionInspectionDecision.blocked) {
      final controller = TextEditingController();
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Заблокировать ${unit.fullLabel}?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Причина (необязательно)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Заблокировать'),
            ),
          ],
        ),
      );
      if (submitted != true) return;
      note = controller.text;
    }
    setState(() => _productionDecisionBusy = true);
    try {
      await workflow.decideInspection(
        unitId: unit.id,
        decision: decision,
        note: note,
      );
      if (!mounted) return;
      setState(() {
        _productionInspectionState =
            decision == ProductionInspectionDecision.approved
                ? ProductionUnitState.approved
                : ProductionUnitState.blocked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(decision == ProductionInspectionDecision.approved
              ? '${unit.fullLabel}: допущено.'
              : '${unit.fullLabel}: заблокировано.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        await xpDlg(context, 'Решение не сохранено', error.toString());
      }
    } finally {
      if (mounted) setState(() => _productionDecisionBusy = false);
    }
  }

  Widget _compareProgressPanel({bool compact = false}) {
    final visibleSteps = compact && _compareSteps.length > 4
        ? _compareSteps.sublist(_compareSteps.length - 4)
        : _compareSteps;
    final visibleTimedSteps = compact && _timedSteps.length > 6
        ? _timedSteps.sublist(_timedSteps.length - 6)
        : _timedSteps;
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
          if (visibleTimedSteps.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0xFFD6E0EA)),
              ),
              child: Column(
                children: visibleTimedSteps
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: Colors.black54,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            _fmtDuration(s.duration),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.black54,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ]),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
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

  void _toggleInspectionTool(_InspectionTool tool) {
    final turningOff = _inspectionTool == tool;
    final resetLoupe = _inspectionTool == _InspectionTool.loupe && turningOff;
    if (resetLoupe) _resultCmpCtrl.value = Matrix4.identity();
    setState(() {
      _inspectionTool = turningOff ? null : tool;
      if (tool == _InspectionTool.point || turningOff) {
        _pointProbe = null;
      }
      if (resetLoupe) {
        _areaLoupe = null;
        _loupeDraftRect = null;
        _loupeDragStart = null;
        _loupeImageSize = null;
      }
      if (!turningOff && tool == _InspectionTool.loupe) {
        _pointProbe = null;
      }
    });
  }

  Widget _resultMapOverlay(CompareResult r) {
    final displayMode = _inspectionTool == _InspectionTool.point
        ? _ResultMapMode.overlay
        : _resultMapMode;
    final diff = switch (displayMode) {
      _ResultMapMode.deltaE => r.diffL3,
      _ResultMapMode.geometry => r.geometryDiff,
      _ResultMapMode.overlay => null,
    };
    final refBase = displayMode == _ResultMapMode.geometry
        ? r.geometryRefCanonical ?? r.refCanonical
        : r.refCanonical;
    final cmpBase = displayMode == _ResultMapMode.geometry
        ? r.geometryCmpCanonical ?? r.cmpCanonical
        : r.cmpCanonical;
    return Stack(
      fit: StackFit.expand,
      children: [
        _diffOverlay(
          diff,
          refBase,
          cmpBase,
          _resultCmpCtrl,
          imageSize: _parseImageSize(r.refSize),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: _comparisonLoupeControl(),
        ),
      ],
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

  Widget _pointProbePanel() {
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
              probe == null ? 'кликните по карте' : 'измерено',
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        if (probe == null)
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'Наведите курсор на интересное место в окне сравнения и кликните мышью. Здесь появятся плотности Dc, Dm, Dy, Dk для эталона и образца, а также ΔE.',
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
                  'ΔE точки',
                  '${probe.formulaLabel} ${probe.deltaE.toStringAsFixed(2)}',
                  flex: 2,
                ),
                _probeCell(
                  'Плотность эталона',
                  _densityLine(probe.refDensity),
                  flex: 3,
                ),
                _probeCell(
                  'Плотность образца',
                  _densityLine(probe.cmpDensity),
                  flex: 3,
                ),
                _probeCell(
                  'Lab',
                  'эталон ${probe.refLab.label}\nобразец ${probe.cmpLab.label}',
                  flex: 3,
                ),
                _probeCell(
                  'Измерение',
                  '${probe.measurementSource}\n'
                      'апертура ${probe.apertureLabel} · '
                      '${probe.sampledPixels} px',
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
                  : 'увеличение ${_loupeMagnificationPercent()}%',
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
              const Expanded(
                child: Text(
                  'Область приближена в окне сравнения. Двигайте ползунок: эталон ↔ образец.',
                  style: TextStyle(
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
    if (!widget.showStoredHistory) {
      final current = _result;
      if (current == null) return const SizedBox.shrink();
      return _checkProtocolTable(
        title: 'Текущая проверка',
        stages: _checkProtocolStages(current),
      );
    }
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
                final customerLabel = p.customerName.isEmpty
                    ? ''
                    : p.customerConfirmed
                        ? ' · ${p.customerName}'
                        : ' · ${p.customerName} (не подтверждён)';
                final imageId = p.sampleImageId.isEmpty
                    ? '-'
                    : _shortLabId(p.sampleImageId);
                return ExpansionTile(
                  initiallyExpanded: i == 0,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    '$jobLabel$customerLabel · ${p.sampleLabel}',
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
              style: const TextStyle(
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
        ? 'Быстрый режим: 4 точки достаточно. 5-8 точки оператор добавляет сам как контрольные, если фото снято под углом.'
        : _calStep == 2
            ? 'Перенесите те же ${_tempRefPts.length} точки на образец в том же порядке. Если нужно напомнить место, откройте сбоку помощник точек эталона.'
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
              final hasNextReferencePoint =
                  _tempCmpPts.length < _tempRefPts.length;
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
                referenceHelperPoint:
                    hasNextReferencePoint ? _tempCmpPts.length + 1 : null,
                onShowReferenceHelper: hasNextReferencePoint
                    ? () => _showReferencePointHelper(
                          _tempCmpPts.length + 1,
                        )
                    : null,
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
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.65)),
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
          label: 'Далее к образцу ›',
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
        color: ok ? AppTheme.simHigh.withValues(alpha: 0.10) : Colors.white,
        border: Border.all(color: ok ? AppTheme.simHigh : AppTheme.silverDark),
      ),
      child: Text(
        label == 'Эталон'
            ? '$label: $count / $required точки · до $_maxAnchorPts по выбору'
            : '$label: $count / $required точек',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: ok ? AppTheme.simHigh : Colors.black87,
        ),
      ),
    );
  }

  Widget _referencePointHelperButton({
    required int pointIndex,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: 'Показать точку $pointIndex на эталоне',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('reference-point-helper'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xD92B353A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF70FF96), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 24,
                  color: Color(0xFF70FF96),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 17,
                    height: 17,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF8A3D),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$pointIndex',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    int? referenceHelperPoint,
    VoidCallback? onShowReferenceHelper,
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
            viewportSize: boxSize,
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
              minPts == _minAnchorPts && tempPts.length > minPts
                  ? '${tempPts.length} / $_maxAnchorPts'
                  : '${tempPts.length} / $minPts',
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
            child: Stack(
              children: [
                Positioned.fill(
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
                              final p =
                                  toImagePoint(details.localPosition, boxSize);
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
                                painter:
                                    _ImageBoundsPainter(imageRect(boxSize)),
                              ),
                            ),
                          ),
                          ...pointWidgets(
                            boxSize,
                            anchorPts ?? [],
                            const Color(0xFF65F58B),
                          ),
                          ...pointWidgets(
                            boxSize,
                            tempPts,
                            const Color(0xFFFF8A3D),
                          ),
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
                if (referenceHelperPoint != null &&
                    onShowReferenceHelper != null)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _referencePointHelperButton(
                      pointIndex: referenceHelperPoint,
                      onTap: onShowReferenceHelper,
                    ),
                  ),
              ],
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
                          ? (minPts > _minAnchorPts
                              ? 'Клик - открыть лупу. Перенесите все выбранные точки. Ctrl+скролл/драг - зум и сдвиг.'
                              : 'Клик - открыть лупу. 4 точки достаточно, 5-8 точки контрольные по выбору. Ctrl+скролл/драг - зум и сдвиг.')
                          : (minPts > _minAnchorPts
                              ? 'Клик - точка без лупы. Перенесите все выбранные точки. Ctrl+скролл/драг - зум и сдвиг.'
                              : 'Клик - точка без лупы. 4 точки достаточно, 5-8 точки контрольные по выбору. Ctrl+скролл/драг - зум и сдвиг.')
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
    m.scaleByDouble(factor, factor, 1, 1);
    final s = m.getMaxScaleOnAxis();
    if (s < 0.8 || s > 10.0) return;
    ctrl.value = m;
  }

  Widget _inspectorPanel({bool compact = false}) {
    final r = _result;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF2F6F7),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'АКТИВНЫЕ ДАННЫЕ',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: 0.8,
                color: Color(0xFF607681),
              ),
            ),
            const SizedBox(height: 10),
            _inspectorStatusCard(),
            if (widget.organizationAccess.organizationId != null) ...[
              const SizedBox(height: 8),
              _jobInspectorSection(),
            ],
            const SizedBox(height: 8),
            _referenceProfilesInspector(),
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
            if (r != null &&
                (_inspectionTool == _InspectionTool.point ||
                    _pointProbe != null)) ...[
              const SizedBox(height: 8),
              _pointProbePanel(),
            ],
            if (r != null && _showAreaLoupePanel) ...[
              const SizedBox(height: 8),
              _areaLoupePanel(),
            ],
            if (_compareStatus != null) ...[
              const SizedBox(height: 8),
              _compareProgressPanel(compact: true),
            ],
            if (r != null ||
                (widget.showStoredHistory &&
                    CheckHistoryService.checks.value.any(
                      (protocol) =>
                          _activeReferenceId == null ||
                          protocol.referenceId == _activeReferenceId ||
                          protocol.referenceLabel == _savedRefLabel,
                    ))) ...[
              const SizedBox(height: 8),
              _checkProtocolListPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inspectorStatusCard() {
    final r = _result;
    final status = r == null
        ? 'ОЖИДАНИЕ'
        : !_exactDeltaEReady
            ? 'ПРЕДВАРИТЕЛЬНО'
            : _shortStatus(r.score);
    final color = r == null || !_exactDeltaEReady
        ? AppTheme.blueDark
        : AppTheme.simColor(r.score);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.34)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status,
            style: TextStyle(
              fontSize: 16,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r == null
                ? 'Загрузите эталон и образец, затем запустите сравнение.'
                : !_exactDeltaEReady
                    ? 'Сходство ${r.score.toStringAsFixed(1)}% · Delta E уровня 2'
                    : 'Сходство ${r.score.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _editJobNumber() async {
    await _loadCustomerDirectory();
    if (!mounted) return;
    var jobNumberInput = _currentJobNumber;
    var requestedCustomerInput = _requestedCustomerName;
    var selectedCustomerId = _selectedCustomerId;
    var selectedCustomerName = _selectedCustomerName;
    var customerNotFound =
        !_customerConfirmed && _requestedCustomerName.trim().isNotEmpty;
    if (!_customerDirectoryAvailable &&
        widget.organizationAccess.organizationId != null &&
        selectedCustomerId == null) {
      customerNotFound = true;
    }
    String? validationError;
    final selectedCustomer = _organizationCustomers
        .where((customer) => customer.id == selectedCustomerId)
        .firstOrNull;
    final value = await showDialog<_JobSelectionDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Работа и заказчик'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: jobNumberInput,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Номер работы из техзадания',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (text) => jobNumberInput = text,
                  ),
                  if (widget.organizationAccess.organizationId != null) ...[
                    const SizedBox(height: 12),
                    if (!_customerDirectoryAvailable)
                      const Text(
                        'Справочник временно недоступен. Введите название заказчика из техзадания.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      )
                    else if (!customerNotFound)
                      Autocomplete<OrganizationCustomer>(
                        initialValue: TextEditingValue(
                          text: selectedCustomer?.displayLabel ?? '',
                        ),
                        displayStringForOption: (customer) =>
                            customer.displayLabel,
                        optionsBuilder: (text) {
                          final query = text.text.trim().toLowerCase();
                          return _organizationCustomers
                              .where(
                                (customer) =>
                                    query.isEmpty ||
                                    customer.code
                                        .toLowerCase()
                                        .contains(query) ||
                                    customer.name.toLowerCase().contains(query),
                              )
                              .take(10);
                        },
                        onSelected: (customer) {
                          setDialogState(() {
                            selectedCustomerId = customer.id;
                            selectedCustomerName = customer.name;
                            validationError = null;
                          });
                        },
                        fieldViewBuilder: (
                          context,
                          textController,
                          focusNode,
                          onSubmitted,
                        ) {
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Заказчик: код или название',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (text) {
                              final selected = _organizationCustomers
                                  .where(
                                    (customer) =>
                                        customer.id == selectedCustomerId,
                                  )
                                  .firstOrNull;
                              if (selected == null ||
                                  text != selected.displayLabel) {
                                selectedCustomerId = null;
                                selectedCustomerName = '';
                              }
                            },
                            onSubmitted: (_) => onSubmitted(),
                          );
                        },
                      ),
                    CheckboxListTile(
                      value: customerNotFound,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Заказчик не найден',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        'Проверка продолжится, администратор получит заявку.',
                        style: TextStyle(fontSize: 10),
                      ),
                      onChanged: _customerDirectoryAvailable
                          ? (checked) => setDialogState(() {
                                customerNotFound = checked == true;
                                validationError = null;
                              })
                          : null,
                    ),
                    if (customerNotFound)
                      TextFormField(
                        initialValue: requestedCustomerInput,
                        decoration: const InputDecoration(
                          labelText: 'Название точно как в техзадании',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (text) => requestedCustomerInput = text,
                      ),
                  ],
                  if (validationError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      validationError!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final number = jobNumberInput.trim();
                final requestedName = requestedCustomerInput.trim();
                if (number.isEmpty) {
                  setDialogState(
                    () => validationError = 'Введите номер работы.',
                  );
                  return;
                }
                if (widget.organizationAccess.organizationId != null &&
                    !customerNotFound &&
                    selectedCustomerId == null) {
                  setDialogState(
                    () => validationError = 'Выберите заказчика из списка.',
                  );
                  return;
                }
                if (widget.organizationAccess.organizationId != null &&
                    customerNotFound &&
                    requestedName.length < 2) {
                  setDialogState(
                    () => validationError =
                        'Введите название заказчика из техзадания.',
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  _JobSelectionDraft(
                    jobNumber: number,
                    customerId: customerNotFound ? null : selectedCustomerId,
                    customerName: customerNotFound ? '' : selectedCustomerName,
                    requestedCustomerName:
                        customerNotFound ? requestedName : '',
                  ),
                );
              },
              child: const Text('Продолжить'),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      _jobNumber = value.jobNumber;
      _selectedCustomerId = value.customerId;
      _selectedCustomerName = value.customerName;
      _requestedCustomerName = value.requestedCustomerName;
      _customerConfirmed = value.customerId != null;
      _cloudJobId = null;
      _sampleNo = _nextSampleNumberFor(
        referenceId: _activeReferenceId,
        referenceLabel: _savedRefLabel,
      );
    });

    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return;
    try {
      final job = await _productionJobService.openJob(
        organizationId: organizationId,
        jobNumber: value.jobNumber,
        customerId: value.customerId,
        requestedCustomerName: value.requestedCustomerName.isEmpty
            ? null
            : value.requestedCustomerName,
      );
      if (!mounted) return;
      setState(() {
        _cloudJobId = job.jobId;
        _selectedCustomerId = job.customerId;
        _selectedCustomerName = job.customerConfirmed ? job.customerName : '';
        _requestedCustomerName = job.customerConfirmed ? '' : job.customerName;
        _customerConfirmed = job.customerConfirmed;
      });
    } catch (_) {
      if (mounted) {
        xpDlg(
          context,
          'Работа сохранена локально',
          'Проверку можно продолжать. После подключения миграции 012 или восстановления сети повторно откройте «Работа и заказчик», чтобы создать связь с организацией.',
        );
      }
    }
  }

  Widget _jobInspectorSection() {
    final hasJob = _currentJobNumber.isNotEmpty;
    return _inspectorSection('Работа', [
      _jobInfoTile(
        'Работа',
        hasJob ? _currentJobNumber : 'не задана',
        hasJob,
        maxLines: 2,
      ),
      const SizedBox(height: 6),
      if (widget.organizationAccess.organizationId != null) ...[
        _jobInfoTile(
          _customerConfirmed ? 'Заказчик' : 'Заказчик · не подтверждён',
          _currentCustomerName.isEmpty ? 'не выбран' : _currentCustomerName,
          _currentCustomerName.isNotEmpty,
        ),
        const SizedBox(height: 6),
      ],
      Row(
        children: [
          Expanded(
            child: _jobInfoTile(
              'Отпечаток',
              _currentSampleLabel,
              _cmpImg != null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _jobInfoTile('ID для базы', _currentJobId, hasJob),
          ),
        ],
      ),
    ]);
  }

  Widget _jobInfoTile(
    String label,
    String value,
    bool active, {
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEAF6F8) : const Color(0xFFF7F9FA),
        border: Border.all(
          color: active ? const Color(0xFF8ACDD5) : const Color(0xFFD8E2E6),
        ),
        borderRadius: BorderRadius.circular(10),
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
        Tooltip(
          message: value,
          child: Text(
            value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
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
        ? 'Эталон: ${_tempRefPts.length} / $_minAnchorPts точки, до $_maxAnchorPts по выбору оператора'
        : _calStep == 2
            ? 'Образец: ${_tempCmpPts.length} / ${_tempRefPts.length} точек'
            : 'Расчёт совмещения...';
    return _inspectorSection('Точки', [
      Text(text, style: const TextStyle(fontSize: 11, height: 1.35)),
      const SizedBox(height: 6),
      Text(
        _calStep == 1
            ? 'Ставьте четыре быстрые точки по понятным местам. Пятую добавляйте только при сильной перспективе.'
            : _calStep == 2
                ? 'Сверху показан мини-эталон: переносите точки по номерам, без запоминания на память.'
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
      return _inspectorSection('AI анализ', const [
        Text(
          'AI-отчёт появится здесь после запуска этапа «AI-анализ» в порядке действий.',
          style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black54),
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
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45)),
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
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD8E2E6)),
        borderRadius: BorderRadius.circular(12),
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
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
        color: color.withValues(alpha: 0.05),
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
          color: AppTheme.canvas,
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
                      (_inspectionTool == _InspectionTool.loupe ||
                          _loupeDragStart != null))
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

    final refMeasurement = ColorMeasurementEngine.measurePoint(
      ref,
      x: rx,
      y: ry,
      settings: _measurementSettings,
      pixelsPerMm: AppConfig.canonicalPixelsPerMm,
    );
    final cmpMeasurement = ColorMeasurementEngine.measurePoint(
      cmp,
      x: cx,
      y: cy,
      settings: _measurementSettings,
      pixelsPerMm: AppConfig.canonicalPixelsPerMm,
    );
    var refLab = refMeasurement.lab;
    var cmpLab = cmpMeasurement.lab;
    var refDensity = OpticalDensityMeasurement.imageRelativeFromRgb(
      refMeasurement.red,
      refMeasurement.green,
      refMeasurement.blue,
    );
    var cmpDensity = OpticalDensityMeasurement.imageRelativeFromRgb(
      cmpMeasurement.red,
      cmpMeasurement.green,
      cmpMeasurement.blue,
    );
    final calibrationProfile = _cameraCalibrationProfile;
    final calibrationModel = calibrationProfile?.model;
    if (calibrationProfile?.enabled == true && calibrationModel != null) {
      final calibratedRefLab = calibrationModel.labForRgb(
        refMeasurement.red,
        refMeasurement.green,
        refMeasurement.blue,
      );
      final calibratedCmpLab = calibrationModel.labForRgb(
        cmpMeasurement.red,
        cmpMeasurement.green,
        cmpMeasurement.blue,
      );
      refLab = LabColor(
        calibratedRefLab.l,
        calibratedRefLab.a,
        calibratedRefLab.b,
      );
      cmpLab = LabColor(
        calibratedCmpLab.l,
        calibratedCmpLab.a,
        calibratedCmpLab.b,
      );
      final calibratedRefDensity = calibrationModel.densityForRgb(
        refMeasurement.red,
        refMeasurement.green,
        refMeasurement.blue,
      );
      final calibratedCmpDensity = calibrationModel.densityForRgb(
        cmpMeasurement.red,
        cmpMeasurement.green,
        cmpMeasurement.blue,
      );
      final calibratedDensityReady =
          calibrationModel.validationDensityMae != null;
      if (calibratedDensityReady && calibratedRefDensity != null) {
        refDensity = OpticalDensityMeasurement(
          cyan: calibratedRefDensity.c,
          magenta: calibratedRefDensity.m,
          yellow: calibratedRefDensity.y,
          black: calibratedRefDensity.k,
        );
      }
      if (calibratedDensityReady && calibratedCmpDensity != null) {
        cmpDensity = OpticalDensityMeasurement(
          cyan: calibratedCmpDensity.c,
          magenta: calibratedCmpDensity.m,
          yellow: calibratedCmpDensity.y,
          black: calibratedCmpDensity.k,
        );
      }
    }
    setState(() {
      _pointProbe = _PointProbe(
        normalized: Offset(nx, ny),
        imageSize: Size(ref.width.toDouble(), ref.height.toDouble()),
        refLab: _LabColor.fromLab(refLab),
        cmpLab: _LabColor.fromLab(cmpLab),
        refDensity: refDensity,
        cmpDensity: cmpDensity,
        deltaE: ColorDifferenceCalculator.deltaE(
          refLab,
          cmpLab,
          _measurementSettings.deltaEFormula,
        ),
        formulaLabel: _measurementSettings.deltaEFormula.shortLabel,
        measurementSource:
            calibrationProfile?.enabled == true && calibrationModel != null
                ? calibrationModel.validationDensityMae == null
                    ? 'профиль ${calibrationProfile!.name} · D по изображению'
                    : 'профиль ${calibrationProfile!.name}'
                : 'по изображению',
        apertureLabel: _measurementSettings.aperture.label,
        sampledPixels: min(
          refMeasurement.sampledPixels,
          cmpMeasurement.sampledPixels,
        ),
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
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
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

  // Текстовый комментарий о цветовом сдвиге образца относительно эталона.
  // da > 0 → образец краснее; da < 0 → зеленее
  // db > 0 → образец желтее;  db < 0 → синее
  // dL > 0 → образец темнее;  dL < 0 → светлее
  String _colorComment(double? dL, double? da, double? db) {
    if (dL == null && da == null && db == null) return 'Нет данных';
    final parts = <String>[];
    const thresh = 3.0; // порог значимости в единицах OpenCV Lab
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
  final Size? viewportSize;
  final bool emphasized;
  const _AnchorPointMarker({
    required this.ctrl,
    required this.x,
    required this.y,
    required this.index,
    this.color = Colors.red,
    this.viewportSize,
    this.emphasized = false,
  });

  static const double _dotSize = 12;
  static const double _activeDotSize = 17;
  static const double _labelOffset = 18;
  static const double _labelSize = 16;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final scale = ctrl.value.getMaxScaleOnAxis();
        final inv = scale <= 0 ? 1.0 : 1 / scale;
        final off = _labelOffset * inv;
        final dotSize = emphasized ? _activeDotSize : _dotSize;
        var labelLeft = x + off;
        var labelTop = y - off - _labelSize;
        final viewport = viewportSize;
        if (viewport != null) {
          if (labelLeft + _labelSize > viewport.width - 2) {
            labelLeft = x - off - _labelSize;
          }
          if (labelTop < 2) labelTop = y + off;
          labelLeft = labelLeft.clamp(2.0, max(2.0, viewport.width - 18));
          labelTop = labelTop.clamp(2.0, max(2.0, viewport.height - 18));
        }
        return Stack(
          children: [
            Positioned(
              left: x - dotSize / 2,
              top: y - dotSize / 2,
              width: dotSize,
              height: dotSize,
              child: Transform.scale(
                scale: inv,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: emphasized ? 2.4 : 1.8,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black87, blurRadius: 3),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: labelLeft,
              top: labelTop,
              width: _labelSize,
              height: _labelSize,
              child: Transform.scale(
                scale: inv,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: color, width: 1),
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

class _WorkflowAction {
  final String number;
  final String label;
  final IconData icon;
  final bool done;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;

  const _WorkflowAction(
    this.number,
    this.label,
    this.icon, {
    required this.done,
    required this.active,
    this.busy = false,
    this.onTap,
  });
}

class _TimedStep {
  final String label;
  final Duration duration;

  const _TimedStep(this.label, this.duration);
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
  final Offset normalized;
  final Size imageSize;
  final _LabColor refLab;
  final _LabColor cmpLab;
  final OpticalDensityMeasurement refDensity;
  final OpticalDensityMeasurement cmpDensity;
  final double deltaE;
  final String formulaLabel;
  final String measurementSource;
  final String apertureLabel;
  final int sampledPixels;

  const _PointProbe({
    required this.normalized,
    required this.imageSize,
    required this.refLab,
    required this.cmpLab,
    required this.refDensity,
    required this.cmpDensity,
    required this.deltaE,
    required this.formulaLabel,
    required this.measurementSource,
    required this.apertureLabel,
    required this.sampledPixels,
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

  factory _LabColor.fromLab(LabColor lab) => _LabColor(lab.l, lab.a, lab.b);

  String get label =>
      'L ${l.toStringAsFixed(1)}  a ${a.toStringAsFixed(1)}  b ${b.toStringAsFixed(1)}';
}

class _ImageBoundsPainter extends CustomPainter {
  final Rect rect;

  const _ImageBoundsPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageBoundsPainter oldDelegate) {
    return oldDelegate.rect != rect;
  }
}

class ReferencePointHelperDialog extends StatefulWidget {
  final Uint8List bytes;
  final Size imageSize;
  final List<Offset> points;
  final int activeIndex;

  const ReferencePointHelperDialog({
    super.key,
    required this.bytes,
    required this.imageSize,
    required this.points,
    required this.activeIndex,
  });

  @override
  State<ReferencePointHelperDialog> createState() =>
      _ReferencePointHelperDialogState();
}

class _ReferencePointHelperDialogState
    extends State<ReferencePointHelperDialog> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final matrix = _controller.value.clone()
      ..multiply(Matrix4.diagonal3Values(factor, factor, 1));
    final scale = matrix.getMaxScaleOnAxis();
    if (scale < 1 || scale > 8) return;
    _controller.value = matrix;
  }

  void _focusActive(Size viewport, Rect imageRect) {
    final point = widget.points[widget.activeIndex - 1];
    final x =
        imageRect.left + point.dx / widget.imageSize.width * imageRect.width;
    final y =
        imageRect.top + point.dy / widget.imageSize.height * imageRect.height;
    const scale = 3.0;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        viewport.width / 2 - x * scale,
        viewport.height / 2 - y * scale,
        0,
      );
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final dialogWidth = min(980.0, media.width - 28);
    final dialogHeight = min(760.0, media.height - 40);
    final previewScale = min(
      1.0,
      3072 / max(widget.imageSize.width, widget.imageSize.height),
    );
    final cacheWidth = max(1, (widget.imageSize.width * previewScale).round());
    final cacheHeight =
        max(1, (widget.imageSize.height * previewScale).round());

    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: const Color(0xFF1F282D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    color: Color(0xFF70FF96),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Эталон · точка ${widget.activeIndex}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Закрыть',
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = constraints.biggest;
                  final fit = min(
                    viewport.width / widget.imageSize.width,
                    viewport.height / widget.imageSize.height,
                  );
                  final imageRect = Rect.fromLTWH(
                    (viewport.width - widget.imageSize.width * fit) / 2,
                    (viewport.height - widget.imageSize.height * fit) / 2,
                    widget.imageSize.width * fit,
                    widget.imageSize.height * fit,
                  );
                  return ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: _controller,
                            boundaryMargin: const EdgeInsets.all(160),
                            minScale: 1,
                            maxScale: 8,
                            child: SizedBox(
                              width: viewport.width,
                              height: viewport.height,
                              child: Stack(
                                children: [
                                  Positioned.fromRect(
                                    rect: imageRect,
                                    child: Image.memory(
                                      widget.bytes,
                                      fit: BoxFit.fill,
                                      cacheWidth: cacheWidth,
                                      cacheHeight: cacheHeight,
                                      gaplessPlayback: true,
                                      filterQuality: FilterQuality.medium,
                                    ),
                                  ),
                                  for (var index = 0;
                                      index < widget.points.length;
                                      index++)
                                    Positioned.fill(
                                      child: _AnchorPointMarker(
                                        ctrl: _controller,
                                        x: imageRect.left +
                                            widget.points[index].dx /
                                                widget.imageSize.width *
                                                imageRect.width,
                                        y: imageRect.top +
                                            widget.points[index].dy /
                                                widget.imageSize.height *
                                                imageRect.height,
                                        index: index + 1,
                                        color: index + 1 == widget.activeIndex
                                            ? const Color(0xFFFF8A3D)
                                            : const Color(0xFF65F58B),
                                        viewportSize: viewport,
                                        emphasized:
                                            index + 1 == widget.activeIndex,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Column(
                            children: [
                              _ReferenceHelperControl(
                                icon: Icons.gps_fixed,
                                tooltip: 'К точке ${widget.activeIndex}',
                                onTap: () => _focusActive(viewport, imageRect),
                              ),
                              const SizedBox(height: 5),
                              _ReferenceHelperControl(
                                icon: Icons.add,
                                tooltip: 'Увеличить',
                                onTap: () => _zoom(1.3),
                              ),
                              const SizedBox(height: 5),
                              _ReferenceHelperControl(
                                icon: Icons.remove,
                                tooltip: 'Уменьшить',
                                onTap: () => _zoom(0.77),
                              ),
                              const SizedBox(height: 5),
                              _ReferenceHelperControl(
                                icon: Icons.fit_screen,
                                tooltip: 'Вся карта',
                                onTap: () =>
                                    _controller.value = Matrix4.identity(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceHelperControl extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ReferenceHelperControl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xD92B353A),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: const Color(0xFF70FF96)),
          ),
        ),
      ),
    );
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
  static const double _maxPreviewEdge = 3072;
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
    final previewScale = min(
      1.0,
      _maxPreviewEdge / max(widget.imageSize.width, widget.imageSize.height),
    );
    final targetWidth = max(1, (widget.imageSize.width * previewScale).round());
    final targetHeight =
        max(1, (widget.imageSize.height * previewScale).round());
    final codec = await ui.instantiateImageCodec(
      widget.bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _image = frame.image);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
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
                          originalImageSize: widget.imageSize,
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
  final Size originalImageSize;
  final Rect source;
  final Offset roughPoint;
  final Offset? selectedPoint;

  const _AnchorLoupePainter({
    required this.image,
    required this.originalImageSize,
    required this.source,
    required this.roughPoint,
    required this.selectedPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dest = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.none;
    final sourceScaleX = image.width / originalImageSize.width;
    final sourceScaleY = image.height / originalImageSize.height;
    final previewSource = Rect.fromLTRB(
      source.left * sourceScaleX,
      source.top * sourceScaleY,
      source.right * sourceScaleX,
      source.bottom * sourceScaleY,
    );
    canvas.drawImageRect(image, previewSource, dest, paint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
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
        oldDelegate.originalImageSize != originalImageSize ||
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
      ..color = (active ? AppTheme.blue : const Color(0xFF1D6E68))
          .withValues(alpha: 0.13)
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
