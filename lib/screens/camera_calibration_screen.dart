import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../config/app_theme.dart';
import '../features/capture/capture.dart';

class CameraCalibrationScreen extends StatefulWidget {
  final CameraCaptureSettings captureSettings;
  final String cameraName;
  final String resolution;

  const CameraCalibrationScreen({
    super.key,
    required this.captureSettings,
    required this.cameraName,
    required this.resolution,
  });

  @override
  State<CameraCalibrationScreen> createState() =>
      _CameraCalibrationScreenState();
}

class _CameraCalibrationScreenState extends State<CameraCalibrationScreen> {
  final _profileNameCtrl = TextEditingController();
  final _cameraCtrl = TextEditingController();
  final _lensCtrl = TextEditingController();
  CalibrationMeasurementCondition _measurementCondition =
      CalibrationMeasurementCondition.m1;
  List<CameraCalibrationPatch> _patches = [];
  CameraCalibrationModel? _model;
  CameraCalibrationProfile? _loadedProfile;
  Uint8List? _targetBytes;
  img.Image? _targetImage;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cameraCtrl.text = widget.cameraName;
    _loadActiveProfile();
  }

  @override
  void dispose() {
    _profileNameCtrl.dispose();
    _cameraCtrl.dispose();
    _lensCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActiveProfile() async {
    final profile = await CameraCalibrationProfileService.loadActive();
    if (!mounted) return;
    setState(() {
      _loadedProfile = profile;
      if (profile != null) {
        _profileNameCtrl.text = profile.name;
        _cameraCtrl.text = profile.camera;
        _lensCtrl.text = profile.lens;
        _measurementCondition = profile.measurementCondition;
        _patches = profile.patches.toList();
        _model = profile.model;
      }
      _loading = false;
    });
  }

  CameraCalibrationProfile _draft({CameraCalibrationModel? model}) {
    final now = DateTime.now().toUtc();
    final current = _loadedProfile;
    return CameraCalibrationProfile(
      id: current?.id ?? 'camera-${now.microsecondsSinceEpoch}',
      name: _profileNameCtrl.text.trim().isEmpty
          ? 'Новый профиль камеры'
          : _profileNameCtrl.text.trim(),
      camera: _cameraCtrl.text.trim(),
      lens: _lensCtrl.text.trim(),
      lighting: widget.captureSettings.lighting.label,
      opticalFilter: widget.captureSettings.opticalFilter.label,
      measurementCondition: _measurementCondition,
      patches: List.unmodifiable(_patches),
      model: model ?? _model,
      enabled: current?.enabled ?? false,
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    final profile = _draft();
    await CameraCalibrationProfileService.save(profile);
    if (!mounted) return;
    setState(() {
      _loadedProfile = profile;
      _busy = false;
    });
    _message('Черновик калибровки сохранён.');
  }

  Future<void> _calculateProfile() async {
    setState(() => _busy = true);
    try {
      final draft = _draft(model: null).copyWith(clearModel: true);
      final model = CameraCalibrationFitter.fit(draft);
      final profile = draft.copyWith(
        model: model,
        enabled: false,
        updatedAt: DateTime.now(),
      );
      await CameraCalibrationProfileService.save(profile);
      if (!mounted) return;
      setState(() {
        _loadedProfile = profile;
        _model = model;
      });
      _message(
        profile.validationPatchCount == 0
            ? 'Профиль рассчитан. Добавьте проверочные поля для оценки точности.'
            : 'Профиль рассчитан и проверен.',
      );
    } on CameraCalibrationException catch (error) {
      _message(error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newProfile() async {
    setState(() {
      _loadedProfile = null;
      _profileNameCtrl.text = '';
      _cameraCtrl.text = widget.cameraName;
      _lensCtrl.text = '';
      _measurementCondition = CalibrationMeasurementCondition.m1;
      _patches = [];
      _model = null;
      _targetBytes = null;
      _targetImage = null;
    });
  }

  Future<void> _setProfileEnabled(bool enabled) async {
    final current = _loadedProfile;
    if (current == null || current.model == null) return;
    final updated = current.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    await CameraCalibrationProfileService.save(updated);
    if (!mounted) return;
    setState(() => _loadedProfile = updated);
  }

  Future<void> _pickTarget() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _message('Не удалось прочитать фото шкалы.', error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _targetBytes = bytes;
      _targetImage = decoded;
    });
  }

  Future<void> _sampleAt(TapDownDetails details, Size viewSize) async {
    final source = _targetImage;
    if (source == null || viewSize.width <= 0 || viewSize.height <= 0) return;
    final x = (details.localPosition.dx / viewSize.width * source.width)
        .round()
        .clamp(0, source.width - 1);
    final y = (details.localPosition.dy / viewSize.height * source.height)
        .round()
        .clamp(0, source.height - 1);
    const radius = 4;
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var count = 0;
    for (var py = max(0, y - radius);
        py <= min(source.height - 1, y + radius);
        py++) {
      for (var px = max(0, x - radius);
          px <= min(source.width - 1, x + radius);
          px++) {
        final pixel = source.getPixel(px, py);
        if (pixel.a < 250) continue;
        red += pixel.r;
        green += pixel.g;
        blue += pixel.b;
        count++;
      }
    }
    if (count == 0) return;
    final patch = await _patchDialog(
      red: red / count,
      green: green / count,
      blue: blue / count,
    );
    if (patch == null || !mounted) return;
    setState(() {
      _patches = [..._patches, patch];
      _model = null;
    });
  }

  Future<CameraCalibrationPatch?> _patchDialog({
    required double red,
    required double green,
    required double blue,
  }) async {
    final label = TextEditingController(text: 'Поле ${_patches.length + 1}');
    final l = TextEditingController();
    final a = TextEditingController();
    final b = TextEditingController();
    final dc = TextEditingController();
    final dm = TextEditingController();
    final dy = TextEditingController();
    final dk = TextEditingController();
    var validation = false;
    String? error;
    final result = await showDialog<CameraCalibrationPatch>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Измерение поля'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'RGB камеры: ${red.toStringAsFixed(1)} / ${green.toStringAsFixed(1)} / ${blue.toStringAsFixed(1)}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    decoration:
                        const InputDecoration(labelText: 'Название поля'),
                  ),
                  const SizedBox(height: 8),
                  _dialogNumberRow([
                    ('L*', l),
                    ('a*', a),
                    ('b*', b),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Плотности прибора — необязательно',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 5),
                  _dialogNumberRow([
                    ('Dc', dc),
                    ('Dm', dm),
                    ('Dy', dy),
                    ('Dk', dk),
                  ]),
                  CheckboxListTile(
                    value: validation,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Проверочное поле'),
                    subtitle: const Text(
                      'не участвует в расчёте, а проверяет точность',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => validation = value ?? false),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final labL = _number(l.text);
                final labA = _number(a.text);
                final labB = _number(b.text);
                final densityValues = [dc, dm, dy, dk]
                    .map((controller) => _number(controller.text))
                    .toList();
                final hasAnyDensity = [dc, dm, dy, dk]
                    .any((controller) => controller.text.trim().isNotEmpty);
                if (labL == null || labA == null || labB == null) {
                  setDialogState(
                    () => error = 'Введите все три значения L*a*b*.',
                  );
                  return;
                }
                if (hasAnyDensity &&
                    densityValues.any((value) => value == null)) {
                  setDialogState(
                    () => error =
                        'Плотности нужно ввести сразу для Dc, Dm, Dy и Dk.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  CameraCalibrationPatch(
                    id: 'patch-${DateTime.now().microsecondsSinceEpoch}',
                    label: label.text.trim(),
                    red: red,
                    green: green,
                    blue: blue,
                    labL: labL,
                    labA: labA,
                    labB: labB,
                    densityC: hasAnyDensity ? densityValues[0] : null,
                    densityM: hasAnyDensity ? densityValues[1] : null,
                    densityY: hasAnyDensity ? densityValues[2] : null,
                    densityK: hasAnyDensity ? densityValues[3] : null,
                    validation: validation,
                  ),
                );
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [label, l, a, b, dc, dm, dy, dk]) {
      controller.dispose();
    }
    return result;
  }

  Widget _dialogNumberRow(List<(String, TextEditingController)> fields) {
    return Row(
      children: [
        for (var index = 0; index < fields.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: fields[index].$2,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(labelText: fields[index].$1),
            ),
          ),
        ],
      ],
    );
  }

  double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade800 : const Color(0xFF1D6E68),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F7),
      appBar: AppBar(
        title: const Text('Калибровка камеры'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _newProfile,
            icon: const Icon(Icons.add),
            label: const Text('Новый профиль'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _progress(),
                const SizedBox(height: 12),
                _conditionsCard(),
                const SizedBox(height: 12),
                _targetCard(),
                const SizedBox(height: 12),
                _patchesCard(),
                const SizedBox(height: 12),
                _calculationCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _progress() {
    final steps = [
      ('1', 'Условия', _profileNameCtrl.text.trim().isNotEmpty),
      ('2', 'Фото шкалы', _targetImage != null),
      (
        '3',
        'Измерения',
        _patches.where((patch) => !patch.validation).length >= 4
      ),
      ('4', 'Профиль', _model != null),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: steps
            .map(
              (step) => Container(
                width: constraints.maxWidth < 700
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 4,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: step.$3 ? const Color(0xFFE4F5EF) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: step.$3
                        ? const Color(0xFF55B788)
                        : const Color(0xFFD6E0E5),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: step.$3
                          ? const Color(0xFF55B788)
                          : const Color(0xFF8799A2),
                      child: Text(
                        step.$1,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _conditionsCard() => _card(
        title: '1. Условия съёмки и прибор',
        child: Column(
          children: [
            _textField(_profileNameCtrl, 'Название профиля'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _textField(_cameraCtrl, 'Камера')),
                const SizedBox(width: 8),
                Expanded(child: _textField(_lensCtrl, 'Объектив')),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CalibrationMeasurementCondition>(
              key: ValueKey(_measurementCondition),
              initialValue: _measurementCondition,
              decoration: const InputDecoration(
                labelText: 'Условие спектрофотометра',
              ),
              items: CalibrationMeasurementCondition.values
                  .map(
                    (condition) => DropdownMenuItem(
                      value: condition,
                      child: Text(condition.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _measurementCondition = value ?? _measurementCondition;
                _model = null;
              }),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Свет: ${widget.captureSettings.lighting.label}  ·  '
                'фильтр: ${widget.captureSettings.opticalFilter.label}  ·  '
                'разрешение: ${widget.resolution}',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      );

  Widget _targetCard() => _card(
        title: '2. Фото калибровочной шкалы',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _pickTarget,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Загрузить фото'),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Фотографируйте RAW/файл при фиксированных свете, экспозиции и балансе белого.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              ],
            ),
            if (_targetBytes != null && _targetImage != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Нажмите в центр поля — RGB возьмётся из области 9×9 px.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final source = _targetImage!;
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxWidth * source.height / source.width,
                  );
                  return GestureDetector(
                    onTapDown: (details) => _sampleAt(details, size),
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: Image.memory(_targetBytes!, fit: BoxFit.fill),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      );

  Widget _patchesCard() => _card(
        title: '3. Поля шкалы и измерения',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Учебных: ${_patches.where((patch) => !patch.validation).length}  ·  '
              'проверочных: ${_patches.where((patch) => patch.validation).length}. '
              'Минимум — 4 разных учебных поля; для рабочего профиля лучше 24+.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            if (_patches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('Поля ещё не добавлены')),
              )
            else
              for (final patch in _patches)
                ListTile(
                  dense: true,
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color.fromARGB(
                        255,
                        patch.red.round().clamp(0, 255),
                        patch.green.round().clamp(0, 255),
                        patch.blue.round().clamp(0, 255),
                      ),
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  title: Text(
                    '${patch.label}  ·  L*a*b* '
                    '${patch.labL.toStringAsFixed(1)} / ${patch.labA.toStringAsFixed(1)} / ${patch.labB.toStringAsFixed(1)}',
                  ),
                  subtitle: Text(
                    patch.validation
                        ? 'проверочное поле'
                        : patch.hasDensities
                            ? 'учебное поле · есть Dc/Dm/Dy/Dk'
                            : 'учебное поле · только L*a*b*',
                  ),
                  trailing: IconButton(
                    tooltip: 'Удалить поле',
                    onPressed: () => setState(() {
                      _patches = _patches
                          .where((item) => item.id != patch.id)
                          .toList();
                      _model = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ),
          ],
        ),
      );

  Widget _calculationCard() => _card(
        title: '4. Расчёт и проверка профиля',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _saveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить черновик'),
                ),
                FilledButton.icon(
                  onPressed: _busy ||
                          _patches.where((patch) => !patch.validation).length <
                              4
                      ? null
                      : _calculateProfile,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calculate_outlined),
                  label: const Text('Рассчитать профиль'),
                ),
              ],
            ),
            if (_model != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF9CC9D3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Профиль рассчитан',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _model!.validationMeanDeltaE == null
                          ? 'Нет проверочных полей: точность ещё не оценена.'
                          : 'Проверка: среднее ΔE76 '
                              '${_model!.validationMeanDeltaE!.toStringAsFixed(2)}, '
                              'максимум ${_model!.validationMaxDeltaE!.toStringAsFixed(2)}.',
                    ),
                    Text(
                      _model!.densityCoefficients == null
                          ? 'Профиль плотности не построен: нужны 4+ учебных поля с Dc/Dm/Dy/Dk.'
                          : _model!.validationDensityMae == null
                              ? 'Плотности рассчитаны, но ещё не проверены.'
                              : 'Средняя ошибка плотности: '
                                  '${_model!.validationDensityMae!.toStringAsFixed(3)} D.',
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _loadedProfile?.enabled ?? false,
                      title: const Text('Использовать профиль'),
                      subtitle: Text(
                        _model!.validationMeanDeltaE == null
                            ? 'сначала добавьте проверочные поля'
                            : _model!.validationDensityMae == null
                                ? 'L*a*b* и ΔE контрольной точки; '
                                    'плотности останутся относительными'
                                : 'L*a*b*, ΔE и плотности '
                                    'контрольной точки',
                      ),
                      onChanged: _model!.validationMeanDeltaE == null
                          ? null
                          : _setProfileEnabled,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Профиль не меняет общий результат сравнения. После проверки его можно включить для L*a*b*, ΔE и плотностей в «Контрольной точке».',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );

  Widget _textField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        onChanged: (_) => setState(() => _model = null),
        decoration: InputDecoration(labelText: label),
      );

  Widget _card({required String title, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD5E0E5)),
          boxShadow: AppTheme.shadowSubtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}
