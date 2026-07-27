import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app/local_access_testing_service.dart';
import '../capabilities/storage/storage.dart';
import '../config/app_theme.dart';
import '../features/auth/auth.dart';
import '../features/billing/billing.dart';
import '../features/capture/capture.dart';
import '../features/color_analysis/color_analysis.dart';
import '../features/organization/organization.dart';
import '../features/production/production.dart';
import '../services/calibration_settings_service.dart';
import '../features/protocols/protocols.dart';
import '../services/compare_settings_service.dart';
import '../widgets/xp_widgets.dart';

class SettingsScreen extends StatefulWidget {
  final EntitlementSnapshot entitlements;
  final OrganizationAccess organizationAccess;
  final Future<void> Function() onAccessChanged;
  final OrganizationAdministrationService? organizationAdministrationService;
  final CustomerDirectoryService? customerDirectoryService;
  final AccountProfileService? accountProfileService;

  const SettingsScreen({
    super.key,
    required this.entitlements,
    required this.organizationAccess,
    required this.onAccessChanged,
    this.organizationAdministrationService,
    this.customerDirectoryService,
    this.accountProfileService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 1;
  double _quality = 96;
  bool _aiEnabled = false;
  bool _history = true;
  bool _notify = true;
  bool _cameraAutoWhite = true;
  bool _barcodeEnabled = true;
  bool _barcodeValueMatch = true;
  bool _ocrEnabled = true;
  bool _geometryEnabled = true;
  bool _fineDefectsEnabled = true;
  String _cameraMode = 'Встроенная камера ноутбука';
  String _captureResolution = '3840 x 2160';
  String _colorProfile = 'ISO Coated v2 / FOGRA39';
  CalibrationPointSettings _calibrationSettings =
      CalibrationPointSettings.defaults;
  CompareSettings _compareSettings = CompareSettings.defaults;
  ColorMeasurementSettings _colorMeasurementSettings =
      ColorMeasurementSettings.defaults;
  CameraCaptureSettings _cameraCaptureSettings = CameraCaptureSettings.defaults;
  StorageSettings _storageSettings = StorageSettings.defaults;
  AccessTestOverride _accessTestOverride = AccessTestOverride.disabled;
  bool _accessSaving = false;
  final _organizationNameCtrl = TextEditingController();
  final _accountNicknameCtrl = TextEditingController();
  final _accountDisplayNameCtrl = TextEditingController();
  final _memberEmailCtrl = TextEditingController();
  final _memberNicknameCtrl = TextEditingController();
  final _memberDisplayNameCtrl = TextEditingController();
  final _customerCodeCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  List<OrganizationParticipant> _organizationParticipants = const [];
  List<OrganizationCustomer> _organizationCustomers = const [];
  List<OrganizationCustomerRequest> _customerRequests = const [];
  final Map<String, String?> _requestCustomerSelections = {};
  OrganizationRole _selectedMemberRole = OrganizationRole.employee;
  Set<OrganizationMemberFunction> _selectedMemberFunctions = {
    OrganizationMemberFunction.inspectionSpecialist,
  };
  bool _organizationBusy = false;
  bool _accountProfileLoading = false;
  bool _accountProfileSaving = false;
  bool _accountProfileLoaded = false;
  AccountProfile? _accountProfile;
  bool _customerBusy = false;
  bool _customerDirectoryAvailable = true;
  String? _editingCustomerId;
  String? _customerRequestBeingCreatedId;
  String? _selectedCustomerManagerId;
  String? _selectedCustomerUserId;
  String? _selectedManagedMemberUserId;
  OrganizationRole? _selectedManagedMemberRole;

  static const _sections = [
    _SettingsSection('Аккаунт', 'профиль и синхронизация'),
    _SettingsSection('Доступ', 'план, роль и лимиты'),
    _SettingsSection('Организация', 'участники и роли'),
    _SettingsSection('Камера', 'захват с ноутбука или USB'),
    _SettingsSection('Калибровка', 'точки, лупа и магнит'),
    _SettingsSection('Цвет', 'CMYK точки и Delta E'),
    _SettingsSection('Плотности', 'оптические плотности CMYK'),
    _SettingsSection('Штрихкоды', 'EAN, QR, DataMatrix'),
    _SettingsSection('Проверка', 'уровни анализа'),
    _SettingsSection('Хранение', 'история и облако'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCalibrationSettings();
    _loadCompareSettings();
    _loadColorMeasurementSettings();
    _loadCameraCaptureSettings();
    _loadStorageSettings();
    _loadAccessTestOverride();
  }

  @override
  void dispose() {
    _organizationNameCtrl.dispose();
    _accountNicknameCtrl.dispose();
    _accountDisplayNameCtrl.dispose();
    _memberEmailCtrl.dispose();
    _memberNicknameCtrl.dispose();
    _memberDisplayNameCtrl.dispose();
    _customerCodeCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationAccess.role != widget.organizationAccess.role) {
      final assignable = OrganizationAdministrationPolicy.assignableRoles(
        widget.organizationAccess.role,
      );
      if (assignable.isNotEmpty && !assignable.contains(_selectedMemberRole)) {
        _selectedMemberRole = assignable.first;
      }
    }
  }

  OrganizationAdministrationService get _organizationService =>
      widget.organizationAdministrationService ??
      SupabaseOrganizationAdministrationService(Supabase.instance.client);

  CustomerDirectoryService get _customerService =>
      widget.customerDirectoryService ??
      SupabaseCustomerDirectoryService(Supabase.instance.client);

  AccountProfileService get _accountService =>
      widget.accountProfileService ??
      SupabaseAccountProfileService(Supabase.instance.client);

  Future<void> _loadAccountProfile({bool force = false}) async {
    if (_accountProfileLoading || (_accountProfileLoaded && !force)) return;
    setState(() => _accountProfileLoading = true);
    try {
      final profile = await _accountService.loadCurrentProfile();
      if (!mounted) return;
      setState(() {
        _accountProfile = profile;
        _accountProfileLoaded = true;
        _accountNicknameCtrl.text = profile.nickname;
        _accountDisplayNameCtrl.text = profile.displayName;
      });
    } catch (error) {
      if (!mounted) return;
      xpDlg(
        context,
        'Профиль недоступен',
        error is AccountProfileException
            ? error.message
            : 'Не удалось загрузить профиль. Проверьте подключение к Supabase.',
      );
    } finally {
      if (mounted) setState(() => _accountProfileLoading = false);
    }
  }

  Future<void> _saveAccountProfile() async {
    final nickname = _accountNicknameCtrl.text.trim().toLowerCase();
    final displayName = _accountDisplayNameCtrl.text.trim();
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(nickname)) {
      xpDlg(
        context,
        'Проверьте ник',
        'Ник: 3–24 символа, только латиница, цифры и подчёркивание.',
      );
      return;
    }
    if (displayName.length > 80) {
      xpDlg(
        context,
        'Проверьте имя',
        'Имя должно содержать не более 80 символов.',
      );
      return;
    }

    setState(() => _accountProfileSaving = true);
    try {
      final profile = await _accountService.saveCurrentProfile(
        nickname: nickname,
        displayName: displayName,
      );
      if (!mounted) return;
      setState(() {
        _accountProfile = profile;
        _accountProfileLoaded = true;
        _accountNicknameCtrl.text = profile.nickname;
        _accountDisplayNameCtrl.text = profile.displayName;
      });
      await widget.onAccessChanged();
      if (!mounted) return;
      xpDlg(
        context,
        'Профиль сохранён',
        'Ник ${profile.nickname} будет использоваться в организации, протоколах и чате.',
      );
    } catch (error) {
      if (!mounted) return;
      xpDlg(
        context,
        'Не удалось сохранить профиль',
        error is AccountProfileException
            ? error.message
            : 'Проверьте подключение к Supabase и повторите.',
      );
    } finally {
      if (mounted) setState(() => _accountProfileSaving = false);
    }
  }

  Future<void> _loadCalibrationSettings() async {
    final settings = await CalibrationSettingsService.load();
    if (mounted) setState(() => _calibrationSettings = settings);
  }

  Future<void> _loadCompareSettings() async {
    final settings = await CompareSettingsService.load();
    if (mounted) setState(() => _compareSettings = settings);
  }

  Future<void> _loadColorMeasurementSettings() async {
    final settings = await ColorMeasurementSettingsService.load();
    if (mounted) setState(() => _colorMeasurementSettings = settings);
  }

  Future<void> _loadCameraCaptureSettings() async {
    final settings = await CameraCaptureSettingsService.load();
    if (mounted) setState(() => _cameraCaptureSettings = settings);
  }

  Future<void> _loadStorageSettings() async {
    final settings = await StorageSettingsService.load();
    if (mounted) setState(() => _storageSettings = settings);
  }

  Future<void> _loadAccessTestOverride() async {
    if (!kDebugMode) return;
    final value = await const LocalAccessTestingService().load();
    if (mounted) setState(() => _accessTestOverride = value);
  }

  final _dotRows = const [
    _DotGainRow('Cyan', 'C', 25, 1.5, 3.0, 4.5, 5.5),
    _DotGainRow('Magenta', 'M', 25, 1.8, 3.2, 4.8, 5.8),
    _DotGainRow('Yellow', 'Y', 25, 1.2, 2.8, 4.2, 5.0),
    _DotGainRow('Black', 'K', 25, 2.0, 3.8, 5.6, 6.5),
  ];

  final _densityRows = const [
    _DensityRow('C', 1.35, 1.25, 1.45, 'Плашка cyan'),
    _DensityRow('M', 1.40, 1.30, 1.50, 'Плашка magenta'),
    _DensityRow('Y', 0.95, 0.85, 1.05, 'Плашка yellow'),
    _DensityRow('K', 1.70, 1.55, 1.85, 'Плашка black'),
  ];

  final _barcodeRows = const [
    _BarcodeRule('EAN-13', 80, 200, 'значение + масштаб'),
    _BarcodeRule('EAN-8', 80, 200, 'значение + масштаб'),
    _BarcodeRule('Code 128', 80, 200, 'геометрия + значение'),
    _BarcodeRule('QR Code', 80, 400, 'наличие + читаемость'),
    _BarcodeRule('DataMatrix', 80, 400, 'наличие + читаемость'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: 'ST', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
            label: 'Сохранить',
            icon: 'SV',
            shortcut: 'Ctrl+S',
            onTap: () => _saveSettings(),
          ),
          XpMenuItem.sep,
          XpMenuItem(
            label: 'Сбросить до базовых',
            icon: 'RS',
            onTap: _resetSettings,
          ),
        ]),
        XpMenu(label: 'Профили', items: [
          XpMenuItem(
            label: 'ISO Coated / FOGRA39',
            onTap: () =>
                setState(() => _colorProfile = 'ISO Coated v2 / FOGRA39'),
          ),
          XpMenuItem(
            label: 'Картон / упаковка',
            onTap: () =>
                setState(() => _colorProfile = 'Packaging board custom'),
          ),
          XpMenuItem(
            label: 'Пленка / этикетка',
            onTap: () => setState(() => _colorProfile = 'Film label custom'),
          ),
        ]),
      ]),
      Expanded(
        child: LayoutBuilder(builder: (_, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return Column(children: [
              SizedBox(height: 112, child: _sectionStrip()),
              Expanded(child: _sectionBody()),
            ]);
          }
          return Row(children: [
            SizedBox(width: 252, child: _sectionSidebar()),
            Expanded(child: _sectionBody()),
          ]);
        }),
      ),
      const XpStatusBar(
        left: 'Настройки производства',
        right: 'камера · калибровка · CMYK · штрихкоды',
      ),
    ]);
  }

  Widget _sectionSidebar() {
    return Container(
      color: const Color(0xFFEAF6FC),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Text(
            'Разделы',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _sections.length,
            itemBuilder: (_, i) => _sectionTile(i),
          ),
        ),
      ]),
    );
  }

  Widget _sectionStrip() {
    return Container(
      color: const Color(0xFFEAF6FC),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: _sections.length,
        itemBuilder: (_, i) => SizedBox(width: 200, child: _sectionTile(i)),
      ),
    );
  }

  Widget _sectionTile(int index) {
    final item = _sections[index];
    final selected = _section == index;
    return InkWell(
      onTap: () {
        setState(() => _section = index);
        if (index == 0) {
          _loadAccountProfile();
        } else if (index == 2) {
          _loadOrganizationMembers();
          _loadCustomerDirectory();
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFFF8FCFF),
          border: Border.all(
            color: selected ? AppTheme.blue : const Color(0xFFC9E2F0),
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected ? AppTheme.shadowSubtle : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            item.title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ]),
      ),
    );
  }

  Widget _sectionBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_section == 0) _accountSection(),
                if (_section == 1) _accessSection(),
                if (_section == 2) _organizationSection(),
                if (_section == 3) _cameraSection(),
                if (_section == 4) _calibrationSection(),
                if (_section == 5) _colorSection(),
                if (_section == 6) _densitySection(),
                if (_section == 7) _barcodeSection(),
                if (_section == 8) _inspectionSection(),
                if (_section == 9) _storageSection(),
              ],
            ),
          ),
        ),
        if (_section != 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FCFF),
              border: Border(
                top: BorderSide(color: Color(0xFFC9E2F0)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                XpBtn(label: 'Сбросить', onPressed: _resetSettings),
                const SizedBox(width: 8),
                XpBtn(
                  label: 'Сохранить',
                  primary: true,
                  onPressed: () => _saveSettings(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _accountSection() {
    final email = _accountProfile?.email ?? '';
    return _settingsPanel(
      title: 'Аккаунт и организация',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _infoRow('Email', email.isEmpty ? 'не указан' : email),
        const SizedBox(height: 8),
        TextField(
          controller: _accountNicknameCtrl,
          enabled: !_accountProfileLoading && !_accountProfileSaving,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Ник',
            hintText: 'например printer_ivan',
            helperText: '3–24 символа: латиница, цифры и подчёркивание',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _accountDisplayNameCtrl,
          enabled: !_accountProfileLoading && !_accountProfileSaving,
          decoration: const InputDecoration(
            labelText: 'Имя',
            hintText: 'необязательно',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        XpBtn(
          label: _accountProfileSaving
              ? 'Сохранение…'
              : _accountProfileLoading
                  ? 'Загрузка…'
                  : 'Сохранить профиль',
          primary: true,
          onPressed: _accountProfileLoading || _accountProfileSaving
              ? null
              : _saveAccountProfile,
        ),
        const SizedBox(height: 12),
        if (widget.entitlements.usesOrganizationPlan)
          _infoRow('Личный план', widget.entitlements.personalPlan.label),
        _infoRow(
          widget.entitlements.usesOrganizationPlan ? 'Рабочий план' : 'План',
          widget.entitlements.plan.label,
        ),
        _infoRow('Роль', widget.organizationAccess.role.label),
        _infoRow(
          'Организация',
          widget.organizationAccess.organizationName ?? 'личное пространство',
        ),
        if (widget.organizationAccess.organizationId != null)
          _infoRow('ID организации', widget.organizationAccess.organizationId!),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: XpBtn(
              label: 'Пароль',
              onPressed: () => xpDlg(
                context,
                'Пароль',
                'Позже добавим смену пароля через Supabase Auth.',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: XpBtn(
              label: 'Синхронизация',
              onPressed: () => xpDlg(
                context,
                'Синхронизация',
                'Настройки будут синхронизироваться после подключения облачной схемы.',
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _accessSection() {
    final checksLimit = widget.entitlements.limit(UsageLimit.checksPerDay);
    final referencesLimit =
        widget.entitlements.limit(UsageLimit.savedReferences);
    final seatsLimit = widget.entitlements.limit(UsageLimit.organizationSeats);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Текущий доступ',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Источник', _accessSourceLabel()),
          _infoRow(
            'Область тарифа',
            widget.entitlements.usesOrganizationPlan
                ? 'организация'
                : 'личный профиль',
          ),
          if (widget.entitlements.usesOrganizationPlan)
            _infoRow('Личный план', widget.entitlements.personalPlan.label),
          _infoRow(
            widget.entitlements.usesOrganizationPlan ? 'Рабочий план' : 'План',
            widget.entitlements.plan.label,
          ),
          _infoRow('Статус', _accessStatusLabel()),
          _infoRow('Роль', widget.organizationAccess.role.label),
          _infoRow(
            'Организация',
            widget.organizationAccess.organizationName ?? 'личное пространство',
          ),
          _infoRow('Область роли', widget.organizationAccess.role.scopeLabel),
          _infoRow(
            'Проверок/день',
            checksLimit == null ? 'без ограничения' : '$checksLimit',
          ),
          _infoRow(
            'Эталонов',
            referencesLimit == null ? 'без ограничения' : '$referencesLimit',
          ),
          _infoRow(
            'Мест в группе',
            seatsLimit == null ? 'без ограничения' : '$seatsLimit',
          ),
          XpBtn(
            label: _accessSaving ? 'Обновляем...' : 'Обновить права с сервера',
            onPressed: _accessSaving ? null : _refreshAccess,
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Возможности плана',
        child: _table(
          headers: const ['Возможность', 'План'],
          rows: ProductCapability.values
              .map((capability) => [
                    _capabilityLabel(capability),
                    widget.entitlements.allows(capability)
                        ? 'Разрешено планом'
                        : 'Не входит',
                  ])
              .toList(),
        ),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Права роли',
        child: _table(
          headers: const ['Действие', 'Разрешение'],
          rows: OrganizationPermission.values
              .map((permission) => [
                    _permissionLabel(permission),
                    widget.organizationAccess.allows(permission)
                        ? 'Разрешено'
                        : 'Запрещено',
                  ])
              .toList(),
        ),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Функции в конкретной работе',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _table(
            headers: const ['Функция', 'Рабочие действия'],
            rows: JobFunction.values
                .map((function) => [
                      function.label,
                      _jobFunctionDescription(function),
                    ])
                .toList(),
          ),
          const SizedBox(height: 8),
          _notePanel(
            'Функция не является ролью организации. Сотруднику можно назначить несколько функций отдельно в каждой работе. Заказчик получает только просмотр, согласование и чат своей работы.',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (kDebugMode) _accessTestingPanel() else _productionAccessPanel(),
    ]);
  }

  Widget _organizationSection() {
    final access = widget.organizationAccess;
    final canAdminister = access.role == OrganizationRole.owner ||
        access.role == OrganizationRole.admin;
    if (access.role == OrganizationRole.personal) {
      final planAllowsOrganization =
          widget.entitlements.plan != PlanTier.free ||
              widget.entitlements.legacyFallback;
      return _settingsPanel(
        title: 'Создание организации',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Текущий режим', 'личное пространство'),
          _infoRow('План', widget.entitlements.plan.label),
          _notePanel(
            'Название из регистрации является частью профиля и не даёт прав. После создания организации текущий пользователь становится её единственным владельцем.',
          ),
          const SizedBox(height: 10),
          const Text(
            'Название организации',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          XpInput(
            placeholder: 'Типография или организация',
            controller: _organizationNameCtrl,
          ),
          const SizedBox(height: 8),
          XpBtn(
            label: _organizationBusy ? 'Создаём...' : 'Создать организацию',
            primary: true,
            onPressed: !planAllowsOrganization || _organizationBusy
                ? null
                : _createOrganization,
          ),
          if (!planAllowsOrganization) ...[
            const SizedBox(height: 8),
            _notePanel('Организация доступна начиная с плана Pro.'),
          ],
        ]),
      );
    }

    if (!canAdminister) {
      return _settingsPanel(
        title: 'Моя организация',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('ID', access.organizationId ?? 'не определён'),
          _infoRow('Название', access.organizationName ?? 'не указано'),
          _infoRow('Роль', access.role.label),
          _infoRow('Область', access.role.scopeLabel),
          _notePanel(
            'Роль назначает владелец или администратор. Пользователь не может повысить собственные права.',
          ),
        ]),
      );
    }

    final assignableRoles = OrganizationAdministrationPolicy.assignableRoles(
      access.role,
    ).toList();
    final activeParticipants = _organizationParticipants
        .where((participant) => !participant.isPending)
        .length;
    final pendingParticipants = _organizationParticipants
        .where((participant) => participant.isPending)
        .length;
    final manageableParticipants = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.userId != null &&
              participant.role != OrganizationRole.owner &&
              !(access.role == OrganizationRole.admin &&
                  participant.role == OrganizationRole.admin),
        )
        .toList();
    final seatLimit = widget.entitlements.limit(UsageLimit.organizationSeats);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Организация',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Название', access.organizationName ?? 'не указано'),
          _infoRow('ID', access.organizationId ?? 'не определён'),
          _infoRow('Моя роль', access.role.label),
          _infoRow(
            'Места',
            seatLimit == null
                ? '$activeParticipants активно, $pendingParticipants ожидают'
                : '$activeParticipants активно, $pendingParticipants ожидают из $seatLimit',
          ),
          _notePanel(
            access.role == OrganizationRole.owner
                ? 'Владелец назначает администратора, сотрудников и заказчиков. Передача владения будет отдельной защищённой операцией.'
                : 'Администратор назначает сотрудников и заказчиков, но не может назначать администраторов или менять владельца.',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Пригласить участника',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          XpInput(
            placeholder: 'Email сотрудника или заказчика',
            controller: _memberEmailCtrl,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          XpInput(
            placeholder: 'Ник: например printer_ivan',
            controller: _memberNicknameCtrl,
          ),
          const SizedBox(height: 8),
          XpInput(
            placeholder: 'Имя пользователя',
            controller: _memberDisplayNameCtrl,
          ),
          const SizedBox(height: 10),
          _optionChips(
            label: 'Общая роль',
            value: _selectedMemberRole.label,
            values: assignableRoles.map((role) => role.label).toList(),
            onSelect: (value) => setState(() {
              _selectedMemberRole = assignableRoles.firstWhere(
                (role) => role.label == value,
              );
            }),
          ),
          if (_selectedMemberRole == OrganizationRole.employee)
            _memberFunctionSelection(),
          const SizedBox(height: 8),
          XpBtn(
            label: _organizationBusy
                ? 'Отправляем...'
                : 'Сохранить и отправить приглашение',
            primary: true,
            onPressed: _organizationBusy ? null : _inviteOrganizationMember,
          ),
          const SizedBox(height: 8),
          _notePanel(
            'Пароль создаёт сам пользователь после перехода по ссылке из письма. Функции сотрудника становятся начальными специализациями; доступ к конкретной работе назначается отдельно.',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Участники',
        child: _organizationBusy && _organizationParticipants.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            : _organizationParticipants.isEmpty
                ? const Text(
                    'Список пока пуст или серверная схема приглашений ещё не подключена.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _table(
                        headers: const [
                          'Email / ник',
                          'Имя',
                          'Роль и функции',
                          'Статус',
                        ],
                        rows: _organizationParticipants
                            .map(_organizationParticipantRow)
                            .toList(),
                      ),
                      if (manageableParticipants.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Изменить роль участника',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _managedMemberRoleEditor(
                          manageableParticipants,
                          assignableRoles,
                        ),
                      ],
                      if (pendingParticipants > 0) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Ожидающие приглашения',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _organizationParticipants
                              .where((participant) => participant.isPending)
                              .map(
                                (participant) => XpBtn(
                                  label: 'Отменить ${participant.nickname}',
                                  danger: true,
                                  onPressed: _organizationBusy
                                      ? null
                                      : () => _cancelOrganizationInvitation(
                                            participant,
                                          ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
      ),
      const SizedBox(height: 10),
      _customerDirectoryPanel(),
    ]);
  }

  Widget _customerDirectoryPanel() {
    final managerCandidates = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.userId != null &&
              participant.role != OrganizationRole.customer,
        )
        .toList();
    final customerUsers = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.userId != null &&
              participant.role == OrganizationRole.customer,
        )
        .toList();
    return _settingsPanel(
      title: 'Справочник заказчиков',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_customerDirectoryAvailable)
            _notePanel(
              'Справочник ещё не подключён на сервере. Нужна миграция 012.',
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: XpInput(
                    placeholder: 'Код заказчика',
                    controller: _customerCodeCtrl,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: XpInput(
                    placeholder: 'Название заказчика',
                    controller: _customerNameCtrl,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _participantDropdown(
                    label: 'Основной менеджер',
                    value: _selectedCustomerManagerId,
                    participants: managerCandidates,
                    onChanged: (value) =>
                        setState(() => _selectedCustomerManagerId = value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _participantDropdown(
                    label: 'Пользователь заказчика',
                    value: _selectedCustomerUserId,
                    participants: customerUsers,
                    onChanged: (value) =>
                        setState(() => _selectedCustomerUserId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_editingCustomerId != null) ...[
                  Expanded(
                    child: XpBtn(
                      label: 'Отменить изменение',
                      onPressed: _customerBusy ? null : _clearCustomerForm,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: XpBtn(
                    label: _customerBusy
                        ? 'Сохраняем...'
                        : _editingCustomerId == null
                            ? 'Добавить заказчика'
                            : 'Сохранить заказчика',
                    primary: true,
                    onPressed: _customerBusy ? null : _saveCustomer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_customerBusy && _organizationCustomers.isEmpty)
              const Center(child: CircularProgressIndicator())
            else if (_organizationCustomers.isEmpty)
              const Text(
                'Заказчики ещё не добавлены.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              )
            else ...[
              _table(
                headers: const [
                  'Код / название',
                  'Менеджер',
                  'Пользователь',
                  'Добавил',
                ],
                rows: _organizationCustomers
                    .map(
                      (customer) => [
                        '${customer.code}\n${customer.name}',
                        customer.primaryManagerNickname.isEmpty
                            ? 'не назначен'
                            : customer.primaryManagerNickname,
                        customer.customerUserNickname.isEmpty
                            ? 'не подключён'
                            : customer.customerUserNickname,
                        customer.createdByNickname.isEmpty
                            ? 'неизвестно'
                            : customer.createdByNickname ==
                                    customer.updatedByNickname
                                ? customer.createdByNickname
                                : '${customer.createdByNickname}\nизм. ${customer.updatedByNickname.isEmpty ? 'неизвестно' : customer.updatedByNickname}',
                      ],
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _organizationCustomers
                    .expand(
                      (customer) => [
                        XpBtn(
                          label: 'Изменить ${customer.code}',
                          onPressed: _customerBusy
                              ? null
                              : () => _editCustomer(customer),
                        ),
                        XpBtn(
                          label: 'В архив ${customer.code}',
                          danger: true,
                          onPressed: _customerBusy
                              ? null
                              : () => _archiveCustomer(customer),
                        ),
                      ],
                    )
                    .toList(),
              ),
            ],
            if (_customerRequests.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Заказчик не найден',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              ..._customerRequests.map(_customerRequestRow),
            ],
          ],
        ],
      ),
    );
  }

  Widget _participantDropdown({
    required String label,
    required String? value,
    required List<OrganizationParticipant> participants,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-${value ?? 'none'}'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Не выбран'),
        ),
        ...participants.map(
          (participant) => DropdownMenuItem<String>(
            value: participant.userId,
            child: Text(
              participant.nickname.isEmpty
                  ? participant.displayName
                  : participant.nickname,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: _customerBusy
          ? null
          : (selected) => onChanged(
                selected == null || selected.isEmpty ? null : selected,
              ),
    );
  }

  Widget _managedMemberRoleEditor(
    List<OrganizationParticipant> participants,
    List<OrganizationRole> assignableRoles,
  ) {
    final memberSelector = DropdownButtonFormField<String>(
      key: const ValueKey('managed-member-selector'),
      initialValue: _selectedManagedMemberUserId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Участник',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: participants
          .map(
            (participant) => DropdownMenuItem<String>(
              key: ValueKey('managed-member-${participant.userId}'),
              value: participant.userId,
              child: Text(
                _participantLabel(participant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _organizationBusy
          ? null
          : (userId) {
              final participant = participants.firstWhere(
                (item) => item.userId == userId,
              );
              setState(() {
                _selectedManagedMemberUserId = participant.userId;
                _selectedManagedMemberRole = participant.role;
              });
            },
    );
    final roleSelector = DropdownButtonFormField<OrganizationRole>(
      key: ValueKey(
        'managed-role-${_selectedManagedMemberRole?.name ?? 'none'}',
      ),
      initialValue: _selectedManagedMemberRole,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Новая роль',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: assignableRoles
          .map(
            (role) => DropdownMenuItem<OrganizationRole>(
              key: ValueKey('managed-role-option-${role.name}'),
              value: role,
              child: Text(role.label),
            ),
          )
          .toList(),
      onChanged: _organizationBusy || _selectedManagedMemberUserId == null
          ? null
          : (role) => setState(() => _selectedManagedMemberRole = role),
    );
    final saveButton = XpBtn(
      label: 'Сохранить роль',
      primary: true,
      onPressed: _organizationBusy ||
              _selectedManagedMemberUserId == null ||
              _selectedManagedMemberRole == null
          ? null
          : _assignExistingMemberRole,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              memberSelector,
              const SizedBox(height: 8),
              roleSelector,
              const SizedBox(height: 8),
              saveButton,
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: memberSelector),
            const SizedBox(width: 8),
            Expanded(child: roleSelector),
            const SizedBox(width: 8),
            saveButton,
          ],
        );
      },
    );
  }

  Widget _customerRequestRow(OrganizationCustomerRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        border: Border.all(color: const Color(0xFFE5C878)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${request.requestedName} · работа ${request.workNumber.isEmpty ? 'не указана' : request.workNumber}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'request-${request.id}-${_requestCustomerSelections[request.id] ?? 'none'}',
                  ),
                  initialValue: _requestCustomerSelections[request.id],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Связать с существующим',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _organizationCustomers
                      .map(
                        (customer) => DropdownMenuItem<String>(
                          value: customer.id,
                          child: Text(
                            customer.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _customerBusy
                      ? null
                      : (value) => setState(
                            () =>
                                _requestCustomerSelections[request.id] = value,
                          ),
                ),
              ),
              const SizedBox(width: 8),
              XpBtn(
                label: 'Связать',
                onPressed: _customerBusy ||
                        _requestCustomerSelections[request.id] == null
                    ? null
                    : () => _resolveCustomerRequest(request),
              ),
              const SizedBox(width: 8),
              XpBtn(
                label: 'Создать',
                primary: true,
                onPressed: _customerBusy
                    ? null
                    : () => _prepareCustomerFromRequest(request),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _createOrganization() async {
    final name = _organizationNameCtrl.text.trim();
    if (name.length < 2) {
      xpDlg(context, 'Организация', 'Введите название организации.');
      return;
    }
    setState(() => _organizationBusy = true);
    try {
      await _organizationService.createOrganization(name: name);
      await widget.onAccessChanged();
      if (mounted) {
        xpDlg(
          context,
          'Организация создана',
          'Вы назначены владельцем. Теперь можно находить пользователей по нику.',
        );
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Не удалось создать организацию', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _loadOrganizationMembers() async {
    final access = widget.organizationAccess;
    final organizationId = access.organizationId;
    if (organizationId == null ||
        (access.role != OrganizationRole.owner &&
            access.role != OrganizationRole.admin) ||
        _organizationBusy) {
      return;
    }
    setState(() => _organizationBusy = true);
    try {
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (mounted) {
        setState(() {
          _organizationParticipants = participants;
          if (!participants.any(
            (participant) => participant.userId == _selectedManagedMemberUserId,
          )) {
            _selectedManagedMemberUserId = null;
            _selectedManagedMemberRole = null;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Участники недоступны', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _loadCustomerDirectory() async {
    final access = widget.organizationAccess;
    final organizationId = access.organizationId;
    if (organizationId == null ||
        (access.role != OrganizationRole.owner &&
            access.role != OrganizationRole.admin) ||
        _customerBusy) {
      return;
    }
    setState(() => _customerBusy = true);
    try {
      final customers = await _customerService.listCustomers(organizationId);
      final requests =
          await _customerService.listPendingRequests(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _customerRequests = requests;
        _customerDirectoryAvailable = true;
        _requestCustomerSelections.removeWhere(
          (requestId, _) => !requests.any((request) => request.id == requestId),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _customerDirectoryAvailable = false);
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _saveCustomer() async {
    final organizationId = widget.organizationAccess.organizationId;
    final code = _customerCodeCtrl.text.trim();
    final name = _customerNameCtrl.text.trim();
    if (organizationId == null) return;
    if (code.isEmpty) {
      xpDlg(context, 'Заказчик', 'Введите короткий код заказчика.');
      return;
    }
    if (name.length < 2) {
      xpDlg(context, 'Заказчик', 'Введите название заказчика.');
      return;
    }

    setState(() => _customerBusy = true);
    try {
      final customerId = await _customerService.saveCustomer(
        organizationId: organizationId,
        code: code,
        name: name,
        managerUserId: _selectedCustomerManagerId,
        customerUserId: _selectedCustomerUserId,
        customerId: _editingCustomerId,
      );
      if (_customerRequestBeingCreatedId != null) {
        await _customerService.resolveRequest(
          requestId: _customerRequestBeingCreatedId!,
          customerId: customerId,
        );
      }
      _clearCustomerForm(notify: false);
      final customers = await _customerService.listCustomers(organizationId);
      final requests =
          await _customerService.listPendingRequests(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _customerRequests = requests;
        _customerDirectoryAvailable = true;
      });
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Заказчик не сохранён', _customerError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  void _editCustomer(OrganizationCustomer customer) {
    setState(() {
      _editingCustomerId = customer.id;
      _customerRequestBeingCreatedId = null;
      _customerCodeCtrl.text = customer.code;
      _customerNameCtrl.text = customer.name;
      _selectedCustomerManagerId = customer.primaryManagerUserId;
      _selectedCustomerUserId = customer.customerUserId;
    });
  }

  void _clearCustomerForm({bool notify = true}) {
    void clear() {
      _editingCustomerId = null;
      _customerRequestBeingCreatedId = null;
      _customerCodeCtrl.clear();
      _customerNameCtrl.clear();
      _selectedCustomerManagerId = null;
      _selectedCustomerUserId = null;
    }

    if (notify && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  Future<void> _archiveCustomer(OrganizationCustomer customer) async {
    setState(() => _customerBusy = true);
    try {
      await _customerService.archiveCustomer(customer.id);
      final organizationId = widget.organizationAccess.organizationId;
      if (organizationId != null) {
        final customers = await _customerService.listCustomers(organizationId);
        if (mounted) setState(() => _organizationCustomers = customers);
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Заказчик не архивирован', _customerError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  void _prepareCustomerFromRequest(OrganizationCustomerRequest request) {
    setState(() {
      _editingCustomerId = null;
      _customerRequestBeingCreatedId = request.id;
      _customerCodeCtrl.clear();
      _customerNameCtrl.text = request.requestedName;
      _selectedCustomerManagerId = null;
      _selectedCustomerUserId = null;
    });
    xpDlg(
      context,
      'Новый заказчик',
      'Название перенесено в форму. Укажите код и сохраните: заявка свяжется автоматически.',
    );
  }

  Future<void> _resolveCustomerRequest(
    OrganizationCustomerRequest request,
  ) async {
    final customerId = _requestCustomerSelections[request.id];
    if (customerId == null) return;
    setState(() => _customerBusy = true);
    try {
      await _customerService.resolveRequest(
        requestId: request.id,
        customerId: customerId,
      );
      final organizationId = widget.organizationAccess.organizationId;
      if (organizationId != null) {
        final requests =
            await _customerService.listPendingRequests(organizationId);
        if (mounted) {
          setState(() {
            _customerRequests = requests;
            _requestCustomerSelections.remove(request.id);
          });
        }
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Заявка не связана', _customerError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  String _customerError(Object error) {
    final text = error.toString();
    if (text.contains('organization_customers') ||
        text.contains('list_organization_customers_v1') ||
        text.contains('PGRST202')) {
      return 'Справочник заказчиков ещё не подключён. Нужна миграция 012.';
    }
    if (text.toLowerCase().contains('duplicate') || text.contains('23505')) {
      return 'Такой код заказчика уже используется.';
    }
    return text;
  }

  Future<void> _assignExistingMemberRole() async {
    final organizationId = widget.organizationAccess.organizationId;
    final userId = _selectedManagedMemberUserId;
    final requestedRole = _selectedManagedMemberRole;
    if (organizationId == null || userId == null || requestedRole == null) {
      return;
    }

    OrganizationParticipant? participant;
    for (final item in _organizationParticipants) {
      if (!item.isPending && item.userId == userId) {
        participant = item;
        break;
      }
    }
    if (participant == null) return;
    if (!OrganizationAdministrationPolicy.canAssign(
      actorRole: widget.organizationAccess.role,
      currentRole: participant.role,
      requestedRole: requestedRole,
    )) {
      xpDlg(
        context,
        'Роль не изменена',
        'Текущая роль не имеет права выполнить это назначение.',
      );
      return;
    }
    if (participant.role == requestedRole) {
      xpDlg(
        context,
        'Роль не изменена',
        '${_participantLabel(participant)} уже имеет роль «${requestedRole.label}».',
      );
      return;
    }

    setState(() => _organizationBusy = true);
    try {
      await _organizationService.assignMember(
        organizationId: organizationId,
        userId: userId,
        role: requestedRole,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationParticipants = participants;
        _selectedManagedMemberUserId = null;
        _selectedManagedMemberRole = null;
      });
      xpDlg(
        context,
        'Роль сохранена',
        '${_participantLabel(participant)}: ${requestedRole.label}.',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Роль не изменена', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _inviteOrganizationMember() async {
    final organizationId = widget.organizationAccess.organizationId;
    final email = _memberEmailCtrl.text.trim().toLowerCase();
    final nickname = _memberNicknameCtrl.text.trim().toLowerCase();
    final displayName = _memberDisplayNameCtrl.text.trim();
    if (organizationId == null) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      xpDlg(context, 'Приглашение', 'Введите корректный email.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(nickname)) {
      xpDlg(
        context,
        'Приглашение',
        'Ник: 3-24 символа, латиница, цифры и подчёркивание.',
      );
      return;
    }
    if (displayName.isEmpty) {
      xpDlg(context, 'Приглашение', 'Введите имя пользователя.');
      return;
    }

    setState(() => _organizationBusy = true);
    try {
      final result = await _organizationService.inviteMember(
        organizationId: organizationId,
        email: email,
        nickname: nickname,
        displayName: displayName,
        role: _selectedMemberRole,
        functions: _selectedMemberRole == OrganizationRole.employee
            ? _selectedMemberFunctions
            : const {},
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationParticipants = participants;
        _memberEmailCtrl.clear();
        _memberNicknameCtrl.clear();
        _memberDisplayNameCtrl.clear();
      });
      xpDlg(
        context,
        'Приглашение отправлено',
        '${result.email}\nНик: ${result.nickname}\nРоль: ${_selectedMemberRole.label}',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отправлено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _cancelOrganizationInvitation(
    OrganizationParticipant participant,
  ) async {
    setState(() => _organizationBusy = true);
    try {
      await _organizationService.cancelInvitation(participant.id);
      final organizationId = widget.organizationAccess.organizationId;
      if (organizationId != null) {
        final participants =
            await _organizationService.listParticipants(organizationId);
        if (mounted) {
          setState(() => _organizationParticipants = participants);
        }
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отменено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Widget _memberFunctionSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Функции сотрудника',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        ...OrganizationMemberFunction.values.map(
          (function) => Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              value: _selectedMemberFunctions.contains(function),
              onChanged: (selected) {
                setState(() {
                  final next = Set<OrganizationMemberFunction>.from(
                    _selectedMemberFunctions,
                  );
                  if (selected == true) {
                    next.add(function);
                  } else {
                    next.remove(function);
                  }
                  _selectedMemberFunctions = next;
                });
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                function.label,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _organizationParticipantRow(
    OrganizationParticipant participant,
  ) {
    final functions = participant.functions.isEmpty
        ? '-'
        : participant.functions.map((function) => function.label).join(', ');
    final status = participant.isPending
        ? participant.emailSent
            ? 'Приглашение отправлено'
            : 'Ожидает отправки email'
        : 'Активен';
    return [
      '${participant.email}\n${participant.nickname}',
      participant.displayName.isEmpty ? 'не указано' : participant.displayName,
      '${participant.role.label}\n$functions',
      status,
    ];
  }

  String _participantLabel(OrganizationParticipant participant) {
    if (participant.nickname.trim().isNotEmpty) {
      return participant.nickname.trim();
    }
    if (participant.displayName.trim().isNotEmpty) {
      return participant.displayName.trim();
    }
    return participant.email.trim();
  }

  String _accessError(Object error) {
    if (error is OrganizationInvitationException) {
      switch (error.code) {
        case 'nickname_conflict':
          return 'Этот ник уже принадлежит другому аккаунту. Проверьте email или выберите другой ник.';
        case 'email_conflict':
          return 'Для этого email уже есть приглашение в другую организацию.';
        case 'already_member':
          return 'Этот пользователь уже состоит в организации.';
        case 'seat_limit':
          return 'Достигнут лимит участников текущего плана.';
        case 'access_denied':
          return 'Недостаточно прав для управления участниками.';
        case 'invalid_email':
          return 'Введите корректный email.';
        case 'invalid_nickname':
          return 'Ник: 3-24 символа, латиница, цифры и подчёркивание.';
        case 'delivery_failed':
          return 'Приглашение сохранено, но письмо не отправлено. Повторите отправку позже.';
        case 'server_not_ready':
          return 'Сервер приглашений ещё не обновлён.';
        default:
          return error.message;
      }
    }
    final text = error.toString();
    if (text.contains('current_organization_access_v2') ||
        text.contains('create_organization_v2') ||
        text.contains('PGRST202')) {
      return 'Серверная схема организации ещё не подключена. Сначала проверьте миграцию 006 на staging.';
    }
    if (text.contains('invite-organization-member') ||
        text.contains('organization_invitations') ||
        text.contains('list_organization_participants_v1')) {
      return 'Приглашения ещё не подключены на сервере. Нужны миграция 010 и Edge Function приглашений.';
    }
    if (text.contains('seat limit')) {
      return 'Достигнут лимит участников текущего плана.';
    }
    return text;
  }

  Widget _accessTestingPanel() {
    return _settingsPanel(
      title: 'Тестирование доступа',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toggleRow(
          'Локальный тестовый режим',
          'не меняет Supabase, платежи и серверные права',
          _accessTestOverride.enabled,
          (value) => setState(() {
            _accessTestOverride = _accessTestOverride.copyWith(enabled: value);
          }),
        ),
        _optionChips(
          label: 'Тестовый план',
          value: _accessTestOverride.plan.label,
          values: PlanTier.values.map((plan) => plan.label).toList(),
          onSelect: (value) => setState(() {
            _accessTestOverride = _accessTestOverride.copyWith(
              plan: PlanTier.values.firstWhere((plan) => plan.label == value),
            );
          }),
        ),
        _optionChips(
          label: 'Тестовая роль',
          value: _accessTestOverride.role.label,
          values: OrganizationRole.values.map((role) => role.label).toList(),
          onSelect: (value) => setState(() {
            _accessTestOverride = _accessTestOverride.copyWith(
              role: OrganizationRole.values
                  .firstWhere((role) => role.label == value),
            );
          }),
        ),
        Row(children: [
          Expanded(
            child: XpBtn(
              label: 'Отключить тест',
              onPressed: _accessSaving ? null : _clearAccessTestOverride,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: XpBtn(
              label: 'Применить режим',
              primary: true,
              onPressed: _accessSaving ? null : _applyAccessTestOverride,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _productionAccessPanel() {
    return _settingsPanel(
      title: 'Управление подпиской',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _infoRow('Активация', 'через защищенный сервер'),
        if (widget.entitlements.usesOrganizationPlan)
          _infoRow('Личный тариф', widget.entitlements.personalPlan.label),
        _infoRow(
          widget.entitlements.usesOrganizationPlan
              ? 'Рабочий тариф организации'
              : 'Тариф',
          widget.entitlements.plan.label,
        ),
        XpBtn(
          label: 'Изменить план',
          primary: true,
          onPressed: () => xpDlg(
            context,
            'Платежи не подключены',
            'Тариф будет активироваться после подтверждения платежа сервером.',
          ),
        ),
      ]),
    );
  }

  String _accessSourceLabel() {
    if (kDebugMode && _accessTestOverride.enabled) {
      return 'локальный тестовый режим';
    }
    if (widget.entitlements.legacyFallback) {
      return 'переходный доступ';
    }
    return 'серверные права Supabase';
  }

  String _accessStatusLabel() {
    if (kDebugMode && _accessTestOverride.enabled) return 'тест';
    if (widget.entitlements.legacyFallback) return 'переходный';
    final validUntil = widget.entitlements.validUntil;
    if (validUntil == null) return 'активен';
    final local = validUntil.toLocal();
    return 'активен до ${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  String _capabilityLabel(ProductCapability capability) {
    switch (capability) {
      case ProductCapability.runInspection:
        return 'Запуск сравнения';
      case ProductCapability.exactDeltaE:
        return 'Точная Delta E';
      case ProductCapability.ocr:
        return 'OCR / вычитка текста';
      case ProductCapability.barcode:
        return 'Штрихкоды и QR';
      case ProductCapability.aiAnalysis:
        return 'AI-анализ';
      case ProductCapability.protocolHistory:
        return 'Протоколы проверок';
      case ProductCapability.multipleReferences:
        return 'Несколько эталонов';
      case ProductCapability.cloudSync:
        return 'Синхронизация данных';
      case ProductCapability.cloudAssets:
        return 'Облачные изображения';
      case ProductCapability.pdfReports:
        return 'PDF-отчёты';
      case ProductCapability.collaboration:
        return 'Чат и совместная работа';
    }
  }

  String _permissionLabel(OrganizationPermission permission) {
    switch (permission) {
      case OrganizationPermission.runInspection:
        return 'Проводить проверки';
      case OrganizationPermission.manageReferences:
        return 'Управлять эталонами';
      case OrganizationPermission.viewProtocols:
        return 'Смотреть протоколы';
      case OrganizationPermission.addComments:
        return 'Комментировать';
      case OrganizationPermission.manageJobs:
        return 'Управлять работами';
      case OrganizationPermission.manageSettings:
        return 'Менять рабочие настройки';
      case OrganizationPermission.manageMembers:
        return 'Управлять участниками';
      case OrganizationPermission.manageBilling:
        return 'Управлять оплатой';
      case OrganizationPermission.manageOrganization:
        return 'Владение организацией';
    }
  }

  String _jobFunctionDescription(JobFunction function) {
    switch (function) {
      case JobFunction.manager:
        return 'заказ, участники и связь с заказчиком';
      case JobFunction.designer:
        return 'макеты, версии и исправления';
      case JobFunction.inspectionSpecialist:
        return 'эталон, образцы, сравнение и протокол';
    }
  }

  Future<void> _applyAccessTestOverride() async {
    if (!kDebugMode || _accessSaving) return;
    setState(() => _accessSaving = true);
    try {
      await const LocalAccessTestingService().save(_accessTestOverride);
      await widget.onAccessChanged();
      if (mounted) {
        xpDlg(
          context,
          'Тестовый режим',
          _accessTestOverride.enabled
              ? 'Применены план ${_accessTestOverride.plan.label} и роль ${_accessTestOverride.role.label}.'
              : 'Тестовый режим отключён.',
        );
      }
    } finally {
      if (mounted) setState(() => _accessSaving = false);
    }
  }

  Future<void> _refreshAccess() async {
    if (_accessSaving) return;
    setState(() => _accessSaving = true);
    try {
      await widget.onAccessChanged();
      if (mounted) {
        xpDlg(
          context,
          'Права обновлены',
          'Роль организации и возможности плана повторно запрошены у Supabase.',
        );
      }
    } finally {
      if (mounted) setState(() => _accessSaving = false);
    }
  }

  Future<void> _clearAccessTestOverride() async {
    if (!kDebugMode || _accessSaving) return;
    setState(() {
      _accessSaving = true;
      _accessTestOverride = AccessTestOverride.disabled;
    });
    try {
      await const LocalAccessTestingService().clear();
      await widget.onAccessChanged();
      if (mounted) {
        xpDlg(
          context,
          'Тестовый режим',
          'Отключён. Восстановлен серверный или переходный доступ.',
        );
      }
    } finally {
      if (mounted) setState(() => _accessSaving = false);
    }
  }

  Widget _cameraSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Камера захвата',
        child: Column(children: [
          _optionChips(
            label: 'Источник',
            value: _cameraMode,
            values: const [
              'Встроенная камера ноутбука',
              'USB камера',
              'Документ-камера',
              'Ручная загрузка файла',
            ],
            onSelect: (v) => setState(() => _cameraMode = v),
          ),
          _optionChips(
            label: 'Разрешение',
            value: _captureResolution,
            values: const ['1920 x 1080', '2560 x 1440', '3840 x 2160'],
            onSelect: (v) => setState(() => _captureResolution = v),
          ),
          _optionChips(
            label: 'Освещение при съёмке',
            value: _cameraCaptureSettings.lighting.label,
            values: CameraLighting.values.map((value) => value.label).toList(),
            onSelect: (value) => setState(() {
              _cameraCaptureSettings = _cameraCaptureSettings.copyWith(
                lighting: CameraLighting.values.firstWhere(
                  (lighting) => lighting.label == value,
                ),
              );
            }),
          ),
          _optionChips(
            label: 'Оптический фильтр',
            value: _cameraCaptureSettings.opticalFilter.label,
            values:
                CameraOpticalFilter.values.map((value) => value.label).toList(),
            onSelect: (value) => setState(() {
              _cameraCaptureSettings = _cameraCaptureSettings.copyWith(
                opticalFilter: CameraOpticalFilter.values.firstWhere(
                  (filter) => filter.label == value,
                ),
              );
            }),
          ),
          _toggleRow(
            'Авто баланс белого',
            'для старта включен; позже добавим ручную калибровку по серой карте',
            _cameraAutoWhite,
            (v) => setState(() => _cameraAutoWhite = v),
          ),
          _numberGrid(const [
            _NumberSpec('Экспозиция EV', '0.0'),
            _NumberSpec('Температура K', '5000'),
            _NumberSpec('ISO', '100'),
            _NumberSpec('Резкость минимум', '120'),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      _notePanel(
        'Освещение и фильтр описывают условия получения готового изображения и записываются в протокол. Они не изменяют пиксели и не пересчитывают Lab программно.',
      ),
      const SizedBox(height: 10),
      _notePanel(
        'Для Chrome надо будет отдельно подключить выбор устройств через getUserMedia: список камер, проверка доступа, live-preview и контроль света.',
      ),
    ]);
  }

  Widget _calibrationSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Калибровочные точки и лупа',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _toggleRow(
            'Лупа при постановке точки',
            'первый клик открывает увеличенный фрагмент, второй ставит точку',
            _calibrationSettings.loupeEnabled,
            (v) => setState(() {
              _calibrationSettings =
                  _calibrationSettings.copyWith(loupeEnabled: v);
            }),
          ),
          _optionChips(
            label: 'Увеличение лупы по умолчанию',
            value: '${_calibrationSettings.loupeZoom.toStringAsFixed(0)}x',
            values: const ['4x', '8x', '12x'],
            onSelect: (v) {
              final zoom = double.parse(v.replaceAll('x', ''));
              setState(() {
                _calibrationSettings =
                    _calibrationSettings.copyWith(loupeZoom: zoom);
              });
            },
          ),
          _sliderRow(
            title: 'Сила ч/б магнита',
            subtitle:
                'после точного клика программа может чуть подтянуть точку к резкой границе',
            value: _calibrationSettings.magnetMaxShiftPx,
            min: 0,
            max: 8,
            divisions: 8,
            suffix: 'px',
            onChanged: (v) => setState(() {
              _calibrationSettings =
                  _calibrationSettings.copyWith(magnetMaxShiftPx: v);
            }),
          ),
          const SizedBox(height: 6),
          _infoRow(
            'Рекомендация',
            _calibrationSettings.magnetMaxShiftPx <= 0.1
                ? 'ручная точка без автоподтяжки'
                : 'для печатника удобно 1-2 px; больше 4 px может уводить точку',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _notePanel(
        'Для контрольного теста одним и тем же файлом используйте одинаковые пары точек и порядок: точка 1 на эталоне должна быть той же точкой 1 на образце.',
      ),
    ]);
  }

  Widget _colorSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Профиль цветового измерения',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _optionChips(
              label: 'Формула Delta E',
              value: _colorMeasurementSettings.deltaEFormula.label,
              values: DeltaEFormula.values.map((value) => value.label).toList(),
              onSelect: (value) => setState(() {
                _colorMeasurementSettings = _colorMeasurementSettings.copyWith(
                  deltaEFormula: DeltaEFormula.values.firstWhere(
                    (formula) => formula.label == value,
                  ),
                );
              }),
            ),
            _optionChips(
              label: 'Апертура точки',
              value: _colorMeasurementSettings.aperture.label,
              values: MeasurementAperture.values
                  .map((value) => value.label)
                  .toList(),
              onSelect: (value) => setState(() {
                _colorMeasurementSettings = _colorMeasurementSettings.copyWith(
                  aperture: MeasurementAperture.values.firstWhere(
                    (aperture) => aperture.label == value,
                  ),
                );
              }),
            ),
            _infoRow(
              'Применение',
              '${_colorMeasurementSettings.deltaEFormula.shortLabel} применяется к карте и точке; апертура ${_colorMeasurementSettings.aperture.label} усредняет круглую область точки',
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Цветовой профиль пользователя',
        child: Column(children: [
          _optionChips(
            label: 'Профиль',
            value: _colorProfile,
            values: const [
              'ISO Coated v2 / FOGRA39',
              'PSO Coated v3 / FOGRA51',
              'Packaging board custom',
              'Film label custom',
            ],
            onSelect: (v) => setState(() => _colorProfile = v),
          ),
          _numberGrid(const [
            _NumberSpec('Delta E норма', '3.0'),
            _NumberSpec('Delta E внимание', '6.0'),
            _NumberSpec('Серый баланс', '2.5'),
            _NumberSpec('Порог пятен px', '12'),
          ]),
          const SizedBox(height: 8),
          _sliderRow(
            title: 'Допуск контура Delta E',
            subtitle:
                'подавляет ореолы по краям текста и штрихов в цветовой карте; ЧБ геометрия остается строгой',
            value: _compareSettings.deltaEdgeTolerancePx.toDouble(),
            min: 0,
            max: 6,
            divisions: 6,
            suffix: 'px',
            onChanged: (v) => setState(() {
              _compareSettings = _compareSettings.copyWith(
                deltaEdgeTolerancePx: v.round(),
              );
            }),
          ),
          _infoRow(
            'Режим',
            _compareSettings.deltaEdgeTolerancePx == 0
                ? 'строгий Delta E без слияния контуров'
                : 'Delta E сливает совпадающие контуры; смещение и потерю штрихов показывает ЧБ геометрия',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Контроль точек CMYK',
        child: _dotGainTable(),
      ),
    ]);
  }

  Widget _densitySection() {
    return _settingsPanel(
      title: 'Оптические плотности CMYK',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _densityTable(),
        const SizedBox(height: 10),
        _numberGrid(const [
          _NumberSpec('Допуск плашки', '0.10'),
          _NumberSpec('Допуск баланса', '0.08'),
          _NumberSpec('Минимум белого', '0.05'),
          _NumberSpec('Сухой оттиск мин', '20'),
        ]),
      ]),
    );
  }

  Widget _barcodeSection() {
    return _settingsPanel(
      title: 'Штрихкоды и маркировка',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toggleRow(
          'Проверять штрихкоды',
          'поиск EAN, QR, DataMatrix, Code 128',
          _barcodeEnabled,
          (v) => setState(() => _barcodeEnabled = v),
        ),
        _toggleRow(
          'Сверять значение кода',
          'ошибка, если код читается, но значение отличается от эталона',
          _barcodeValueMatch,
          (v) => setState(() => _barcodeValueMatch = v),
        ),
        _barcodeTable(),
      ]),
    );
  }

  Widget _inspectionSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Уровни проверки',
        child: Column(children: [
          _toggleRow(
            'Грубый уровень',
            'фон, крупное цветовое отличие, пятна, общий тон',
            true,
            (_) {},
            locked: true,
          ),
          _toggleRow(
            'Средний уровень',
            'детали, лица, логотипы, предметы, локальные зоны',
            true,
            (_) {},
            locked: true,
          ),
          _toggleRow(
            'Точный уровень',
            'точки, мусор, царапины, мелкие дефекты',
            _fineDefectsEnabled,
            (v) => setState(() => _fineDefectsEnabled = v),
          ),
          _toggleRow(
            'ЧБ геометрия',
            'контуры текста, штрихи, белая краска по черному',
            _geometryEnabled,
            (v) => setState(() => _geometryEnabled = v),
          ),
          _toggleRow(
            'OCR / вычитка текста',
            'сверка текста отдельно от цвета',
            _ocrEnabled,
            (v) => setState(() => _ocrEnabled = v),
          ),
          _toggleRow(
            'AI заключение',
            'короткий вывод для пользователя после расчетов',
            _aiEnabled,
            (v) => setState(() => _aiEnabled = v),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Обработка изображений',
        child: Column(children: [
          Row(children: [
            const SizedBox(
              width: 160,
              child: Text('Качество JPEG', style: TextStyle(fontSize: 11)),
            ),
            Expanded(
              child: Slider(
                value: _quality,
                min: 70,
                max: 100,
                divisions: 30,
                activeColor: AppTheme.blue,
                onChanged: (v) => setState(() => _quality = v),
              ),
            ),
            Text('${_quality.round()}%', style: const TextStyle(fontSize: 11)),
          ]),
          _numberGrid(const [
            _NumberSpec('Макс. размер UI', '1600'),
            _NumberSpec('Расчет тайла px', '512'),
            _NumberSpec('Зона дефекта px', '64'),
            _NumberSpec('Калибр. точек', '4-8'),
          ]),
        ]),
      ),
    ]);
  }

  Widget _storageSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Место хранения изображений',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _storageLocationOption(
            location: AssetStorageLocation.device,
            icon: Icons.computer_outlined,
            title: 'На устройстве пользователя',
            subtitle:
                'Активно. Trimatrix обрабатывает выбранные файлы, но не загружает оригиналы в облако.',
            available: true,
          ),
          _storageLocationOption(
            location: AssetStorageLocation.supabaseStorage,
            icon: Icons.cloud_outlined,
            title: 'Облако приложения',
            subtitle:
                'Supabase Storage: превью и общие файлы. Подключение ещё не настроено.',
          ),
          _storageLocationOption(
            location: AssetStorageLocation.googleDrive,
            icon: Icons.add_to_drive_outlined,
            title: 'Google Drive пользователя',
            subtitle:
                'Потребуется отдельный вход Google OAuth. Вход Trimatrix не даёт доступа к диску.',
          ),
          _storageLocationOption(
            location: AssetStorageLocation.organizationDrive,
            icon: Icons.corporate_fare_outlined,
            title: 'Диск организации',
            subtitle:
                'Общее хранилище организации. Подключать сможет администратор с соответствующим правом.',
          ),
          const SizedBox(height: 4),
          _notePanel(
            'Авторизация Trimatrix определяет пользователя, организацию и роль. Подключение облачного хранилища настраивается отдельно и не меняет права пользователя в приложении.',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Политика данных',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Оригиналы', 'не загружаются; остаются у владельца'),
          _infoRow('Протокол', 'последняя проверка хранится локально'),
          _infoRow('Превью и карты', 'облачная отправка выключена'),
          _infoRow('Права доступа', 'план + роль + доступ к работе'),
          _infoRow('Google OAuth', 'не подключён'),
          _infoRow('Supabase Storage', 'не настроен'),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Локальные данные и уведомления',
        child: Column(children: [
          _toggleRow(
            'Сохранять историю',
            'последний протокол хранится локально',
            _history,
            (v) => setState(() => _history = v),
          ),
          _toggleRow(
            'Уведомления чата',
            'сообщения группы организации',
            _notify,
            (v) => setState(() => _notify = v),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _lastCheckHistoryGroup(),
    ]);
  }

  Widget _storageLocationOption({
    required AssetStorageLocation location,
    required IconData icon,
    required String title,
    required String subtitle,
    bool available = false,
  }) {
    final selected = _storageSettings.primaryLocation == location;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: InkWell(
        onTap: available
            ? () => setState(() {
                  _storageSettings = _storageSettings.copyWith(
                    primaryLocation: location,
                  );
                })
            : () => xpDlg(
                  context,
                  'Хранилище не подключено',
                  'Сейчас данные никуда не отправляются. Подключение появится после добавления защищённого адаптера и проверки прав.',
                ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected && available
                ? const Color(0xFFEAF6FC)
                : const Color(0xFFF8FCFF),
            border: Border.all(
              color: selected && available
                  ? AppTheme.blue
                  : const Color(0xFFC9E2F0),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(
              icon,
              size: 22,
              color: available ? AppTheme.blueDark : Colors.blueGrey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected && available
                  ? Icons.check_circle
                  : Icons.link_off_outlined,
              size: 18,
              color: selected && available ? AppTheme.blue : Colors.grey,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dotGainTable() {
    return _table(
      headers: const ['Канал', 'Точки', '25%', '50%', '75%', '100%'],
      rows: _dotRows
          .map((r) => [
                '${r.name} (${r.channel})',
                '${r.nominalDot}%',
                '+${r.dot25.toStringAsFixed(1)}',
                '+${r.dot50.toStringAsFixed(1)}',
                '+${r.dot75.toStringAsFixed(1)}',
                '+${r.dot100.toStringAsFixed(1)}',
              ])
          .toList(),
    );
  }

  Widget _densityTable() {
    return _table(
      headers: const ['Канал', 'Цель', 'Мин.', 'Макс.', 'Комментарий'],
      rows: _densityRows
          .map((r) => [
                r.channel,
                r.target.toStringAsFixed(2),
                r.min.toStringAsFixed(2),
                r.max.toStringAsFixed(2),
                r.comment,
              ])
          .toList(),
    );
  }

  Widget _barcodeTable() {
    return _table(
      headers: const ['Формат', 'Мин.', 'Макс.', 'Проверка'],
      rows: _barcodeRows
          .map((r) => [
                r.format,
                '${r.minScale.round()}%',
                '${r.maxScale.round()}%',
                r.check,
              ])
          .toList(),
    );
  }

  Widget _table(
      {required List<String> headers, required List<List<String>> rows}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: const Color(0xFFEAF6FC),
          child: Row(
            children: headers
                .map((h) =>
                    _tableCell(h, bold: true, flex: h == headers.last ? 2 : 1))
                .toList(),
          ),
        ),
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Container(
            color: i.isEven ? Colors.white : const Color(0xFFF8FCFF),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: row
                  .asMap()
                  .entries
                  .map((c) => _tableCell(c.value,
                      flex: c.key == row.length - 1 ? 2 : 1))
                  .toList(),
            ),
          );
        }),
      ]),
    );
  }

  Widget _tableCell(String text, {bool bold = false, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            height: 1.25,
            fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _settingsPanel({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _notePanel(String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE6),
        border: Border.all(color: const Color(0xFFE8C65C)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, height: 1.35)),
    );
  }

  Widget _optionChips({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: values.map((v) {
            final selected = v == value;
            return InkWell(
              onTap: () => onSelect(v),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.blue : const Color(0xFFF8FCFF),
                  border: Border.all(
                    color:
                        selected ? AppTheme.blueDark : const Color(0xFFC9E2F0),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  v,
                  style: TextStyle(
                    fontSize: 10,
                    color: selected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _toggleRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    bool locked = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Switch(
          value: value,
          onChanged: locked ? null : onChanged,
          activeThumbColor: AppTheme.blue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 6),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
            Text(
              subtitle,
              style: const TextStyle(
                  fontSize: 10, height: 1.3, color: Colors.black54),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _sliderRow({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '${value.toStringAsFixed(0)} $suffix',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ]),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style:
              const TextStyle(fontSize: 10, height: 1.3, color: Colors.black54),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.blue,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _numberGrid(List<_NumberSpec> specs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: specs.map((spec) {
        return SizedBox(
          width: 180,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.label,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 3),
            XpInput(placeholder: spec.value),
          ]),
        );
      }).toList(),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
    );
  }

  Future<void> _saveSettings() async {
    await CalibrationSettingsService.save(_calibrationSettings);
    await CompareSettingsService.save(_compareSettings);
    await ColorMeasurementSettingsService.save(_colorMeasurementSettings);
    await CameraCaptureSettingsService.save(_cameraCaptureSettings);
    await StorageSettingsService.save(_storageSettings);
    if (!mounted) return;
    xpDlg(
      context,
      'Сохранено',
      'Настройки применены локально. Хранилище изображений остаётся на устройстве; облачные подключения пока выключены.',
    );
  }

  Future<void> _resetSettings() async {
    final ok = await xpConfirm(
        context, 'Сбросить?', 'Вернуть базовые производственные настройки?');
    if (!ok || !mounted) return;
    setState(() {
      _quality = 96;
      _aiEnabled = false;
      _history = true;
      _notify = true;
      _cameraAutoWhite = true;
      _barcodeEnabled = true;
      _barcodeValueMatch = true;
      _ocrEnabled = true;
      _geometryEnabled = true;
      _fineDefectsEnabled = true;
      _cameraMode = 'Встроенная камера ноутбука';
      _captureResolution = '3840 x 2160';
      _colorProfile = 'ISO Coated v2 / FOGRA39';
      _calibrationSettings = CalibrationPointSettings.defaults;
      _compareSettings = CompareSettings.defaults;
      _colorMeasurementSettings = ColorMeasurementSettings.defaults;
      _cameraCaptureSettings = CameraCaptureSettings.defaults;
      _storageSettings = StorageSettings.defaults;
    });
    await CalibrationSettingsService.reset();
    await CompareSettingsService.reset();
    await ColorMeasurementSettingsService.reset();
    await CameraCaptureSettingsService.reset();
    await StorageSettingsService.reset();
  }

  Widget _lastCheckHistoryGroup() {
    return ValueListenableBuilder<CheckProtocol?>(
      valueListenable: CheckHistoryService.lastCheck,
      builder: (context, protocol, _) {
        return _settingsPanel(
          title: 'История проверок',
          child: protocol == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Последней проверки пока нет. Выполните сравнение, и здесь появится таблица этапов.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _protocolSummary(protocol),
                    const SizedBox(height: 10),
                    _protocolStageTable(protocol),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Spacer(),
                      XpBtn(
                        label: 'Очистить',
                        danger: true,
                        onPressed: () async {
                          final ok = await xpConfirm(
                            context,
                            'Очистить историю?',
                            'Удалить локальный протокол последней проверки?',
                          );
                          if (ok) await CheckHistoryService.clearLast();
                        },
                      ),
                    ]),
                  ],
                ),
        );
      },
    );
  }

  Widget _protocolSummary(CheckProtocol p) {
    final date =
        '${p.createdAt.day.toString().padLeft(2, '0')}.${p.createdAt.month.toString().padLeft(2, '0')}.${p.createdAt.year} '
        '${p.createdAt.hour.toString().padLeft(2, '0')}:${p.createdAt.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F5),
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SimBadge(value: p.score, fontSize: 12),
          _summaryText('Вердикт', p.verdict),
          _summaryText('Дата', date),
          _summaryText('Размер', '${p.refSize} -> ${p.cmpSize}'),
          _summaryText('Delta E', p.deltaEFormula),
          _summaryText('Освещение камеры', p.captureLighting),
          _summaryText('Фильтр камеры', p.captureFilter),
          _summaryText('Апертура', '${p.apertureMm.toStringAsFixed(0)} мм'),
          _summaryText('Lab ID', p.labId),
          _summaryText(
            'Lab match',
            p.labMatch == null ? '-' : '${p.labMatch!.toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _summaryText(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11, color: Colors.black87),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _protocolStageTable(CheckProtocol p) {
    return _table(
      headers: const ['Этап', 'Статус', 'Метрика', 'Комментарий'],
      rows:
          p.stages.map((s) => [s.name, s.status, s.metric, s.comment]).toList(),
    );
  }
}

class _SettingsSection {
  final String title;
  final String subtitle;
  const _SettingsSection(this.title, this.subtitle);
}

class _DotGainRow {
  final String name;
  final String channel;
  final int nominalDot;
  final double dot25;
  final double dot50;
  final double dot75;
  final double dot100;
  const _DotGainRow(
    this.name,
    this.channel,
    this.nominalDot,
    this.dot25,
    this.dot50,
    this.dot75,
    this.dot100,
  );
}

class _DensityRow {
  final String channel;
  final double target;
  final double min;
  final double max;
  final String comment;
  const _DensityRow(
      this.channel, this.target, this.min, this.max, this.comment);
}

class _BarcodeRule {
  final String format;
  final double minScale;
  final double maxScale;
  final String check;
  const _BarcodeRule(this.format, this.minScale, this.maxScale, this.check);
}

class _NumberSpec {
  final String label;
  final String value;
  const _NumberSpec(this.label, this.value);
}
