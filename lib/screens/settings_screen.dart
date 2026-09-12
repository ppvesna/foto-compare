import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

enum _TeamDraftAction { invite, clear }

enum _TeamAction { edit, resendInvitation, cancelInvitation, remove }

enum _CustomerDraftAction {
  save,
  invite,
  saveWithoutRepresentative,
  clear,
}

enum _CustomerAction {
  edit,
  addRepresentative,
  linkExistingRepresentative,
  resendInvitation,
  cancelInvitation,
  openJobs,
  archive,
  restore,
}

enum _OrganizationWorkspace { team, customers }

class SettingsScreen extends StatefulWidget {
  final EntitlementSnapshot entitlements;
  final OrganizationAccess organizationAccess;
  final Future<void> Function() onAccessChanged;
  final int initialSection;
  final OrganizationAdministrationService? organizationAdministrationService;
  final CustomerDirectoryService? customerDirectoryService;
  final AccountProfileService? accountProfileService;
  final CloudStorage? cloudStorage;
  final PaymentService? paymentService;

  const SettingsScreen({
    super.key,
    required this.entitlements,
    required this.organizationAccess,
    required this.onAccessChanged,
    this.initialSection = 1,
    this.organizationAdministrationService,
    this.customerDirectoryService,
    this.accountProfileService,
    this.cloudStorage,
    this.paymentService,
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
  CloudConnection _cloudConnection = CloudConnection.disconnected;
  bool _cloudConnectionChecking = false;
  final _organizationNameCtrl = TextEditingController();
  final _accountNicknameCtrl = TextEditingController();
  final _accountDisplayNameCtrl = TextEditingController();
  final _memberEmailCtrl = TextEditingController();
  final _memberNicknameCtrl = TextEditingController();
  final _memberDisplayNameCtrl = TextEditingController();
  final _customerCodeCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _customerRepresentativeEmailCtrl = TextEditingController();
  final _customerRepresentativeNicknameCtrl = TextEditingController();
  final _customerRepresentativeDisplayNameCtrl = TextEditingController();
  final _billingEmailCtrl = TextEditingController();
  final _billingLegalNameCtrl = TextEditingController();
  final _billingCountryCtrl = TextEditingController();
  final _billingTaxIdCtrl = TextEditingController();
  final _billingAddressCtrl = TextEditingController();
  List<OrganizationParticipant> _organizationParticipants = const [];
  List<OrganizationCustomer> _organizationCustomers = const [];
  List<OrganizationCustomerRequest> _customerRequests = const [];
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
  String? _customerDirectoryError;
  String? _customerRequestsError;
  String? _editingCustomerId;
  bool _customerDraftForRepresentative = false;
  String? _customerRequestBeingCreatedId;
  String? _selectedCustomerManagerId;
  String? _selectedCustomerUserId;
  bool _showArchivedCustomers = false;
  _OrganizationWorkspace _organizationWorkspace = _OrganizationWorkspace.team;
  BillingScope _billingScope = BillingScope.personal;
  PlanTier _billingPlan = PlanTier.pro;
  BillingPeriod _billingPeriod = BillingPeriod.month;
  BillingQuote? _billingQuote;
  bool _billingLoading = false;
  bool _billingProfileSaving = false;
  bool _billingActivating = false;
  String? _billingError;

  static const _sections = [
    _SettingsSection('Аккаунт', 'профиль пользователя'),
    _SettingsSection('Доступ', 'план, роль и лимиты'),
    _SettingsSection('Тариф и оплата', 'срок, сумма и реквизиты'),
    _SettingsSection('Организация', 'команда и заказчики'),
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
    if (widget.initialSection >= 0 &&
        widget.initialSection < _sections.length) {
      _section = widget.initialSection;
    }
    _loadCalibrationSettings();
    _loadCompareSettings();
    _loadColorMeasurementSettings();
    _loadCameraCaptureSettings();
    _loadStorageSettings();
    _loadCloudConnection();
    _billingScope = _defaultBillingScope();
    if (_section == 2) _loadBillingData();
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
    _customerRepresentativeEmailCtrl.dispose();
    _customerRepresentativeNicknameCtrl.dispose();
    _customerRepresentativeDisplayNameCtrl.dispose();
    _billingEmailCtrl.dispose();
    _billingLegalNameCtrl.dispose();
    _billingCountryCtrl.dispose();
    _billingTaxIdCtrl.dispose();
    _billingAddressCtrl.dispose();
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
    if (oldWidget.cloudStorage != widget.cloudStorage) {
      _loadCloudConnection();
    }
    if (oldWidget.organizationAccess.organizationId !=
            widget.organizationAccess.organizationId ||
        oldWidget.organizationAccess.role != widget.organizationAccess.role) {
      final nextScope = _defaultBillingScope();
      if (_billingScope != nextScope &&
          !_canUseOrganizationBilling(_billingScope)) {
        _billingScope = nextScope;
        _billingQuote = null;
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

  PaymentService get _paymentService =>
      widget.paymentService ?? SupabasePaymentService(Supabase.instance.client);

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

  Future<void> _loadCloudConnection() async {
    final storage = widget.cloudStorage;
    if (storage == null) {
      if (mounted) {
        setState(() => _cloudConnection = CloudConnection.disconnected);
      }
      return;
    }
    final connection = await storage.connection();
    if (mounted) setState(() => _cloudConnection = connection);
  }

  Future<void> _checkCloudConnection() async {
    final storage = widget.cloudStorage;
    if (storage == null || _cloudConnectionChecking) return;
    setState(() => _cloudConnectionChecking = true);
    final connection = await storage.connect();
    if (!mounted) return;
    setState(() {
      _cloudConnection = connection;
      _cloudConnectionChecking = false;
    });
    if (connection.state == CloudConnectionState.connected) {
      xpDlg(
        context,
        'Облако доступно',
        'Приватное хранилище Supabase подключено для ${connection.accountLabel ?? 'текущего пользователя'}. Автоматическая загрузка изображений пока выключена.',
      );
    } else {
      xpDlg(
        context,
        'Облако недоступно',
        'Не удалось открыть приватное хранилище. Проверьте, что миграция 013 установлена в Supabase.',
      );
    }
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
          _loadBillingData();
        } else if (index == 3) {
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
                if (_section == 2) _billingSection(),
                if (_section == 3) _organizationSection(),
                if (_section == 4) _cameraSection(),
                if (_section == 5) _calibrationSection(),
                if (_section == 6) _colorSection(),
                if (_section == 7) _densitySection(),
                if (_section == 8) _barcodeSection(),
                if (_section == 9) _inspectionSection(),
                if (_section == 10) _storageSection(),
              ],
            ),
          ),
        ),
        if (_section > 3)
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
      ]),
    );
  }

  Widget _accessSection() {
    final checksLimit = widget.entitlements.limit(UsageLimit.checksPerDay);
    final referencesLimit =
        widget.entitlements.limit(UsageLimit.savedReferences);
    final seatsLimit = widget.entitlements.limit(UsageLimit.organizationSeats);
    final customerSeatsLimit =
        widget.entitlements.limit(UsageLimit.customerRepresentativeSeats);
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
          if (widget.entitlements.usesFallbackPlan)
            _infoRow(
              'Тариф по подписке',
              widget.entitlements.configuredPlan.label,
            ),
          _infoRow('Статус', _accessStatusLabel()),
          if (widget.entitlements.usesFallbackPlan) ...[
            const SizedBox(height: 8),
            _notePanel(
              'Платный тариф неактивен. До его продления '
              'применяются возможности бесплатного плана.',
            ),
          ],
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
          if (widget.organizationAccess.organizationId != null) ...[
            _infoRow(
              'Мест в команде',
              seatsLimit == null ? 'без ограничения' : '$seatsLimit',
            ),
            _infoRow(
              'Представителей заказчиков',
              customerSeatsLimit == null
                  ? 'без ограничения'
                  : '$customerSeatsLimit',
            ),
          ] else
            _infoRow(
              'Мест в группе',
              seatsLimit == null ? 'без ограничения' : '$seatsLimit',
            ),
          if (_canManageBilling)
            XpBtn(
              label: 'Открыть тариф и оплату',
              primary: true,
              onPressed: () {
                setState(() => _section = 2);
                _loadBillingData();
              },
            )
          else
            _notePanel(
              'Оплатой рабочего тарифа управляет владелец организации.',
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
    ]);
  }

  BillingScope _defaultBillingScope() {
    return widget.organizationAccess.role == OrganizationRole.owner &&
            widget.organizationAccess.organizationId != null
        ? BillingScope.organization
        : BillingScope.personal;
  }

  bool _canUseOrganizationBilling(BillingScope scope) {
    if (scope == BillingScope.personal) return true;
    return widget.organizationAccess.role == OrganizationRole.owner &&
        widget.organizationAccess.organizationId != null;
  }

  bool get _canManageBilling =>
      widget.organizationAccess.allows(OrganizationPermission.manageBilling);

  String? get _billingOrganizationId =>
      _billingScope == BillingScope.organization
          ? widget.organizationAccess.organizationId
          : null;

  Future<void> _loadBillingData() async {
    if (_billingLoading || !_canManageBilling) return;
    if (!_canUseOrganizationBilling(_billingScope)) {
      _billingScope = BillingScope.personal;
    }
    final requestedScope = _billingScope;
    final requestedOrganization = _billingOrganizationId;
    setState(() {
      _billingLoading = true;
      _billingError = null;
    });
    try {
      final quote = await _paymentService.quote(
        plan: _billingPlan,
        period: _billingPeriod,
      );
      final profile = await _paymentService.loadProfile(
        scope: requestedScope,
        organizationId: requestedOrganization,
      );
      if (!mounted || requestedScope != _billingScope) return;
      setState(() {
        _billingQuote = quote;
        _billingEmailCtrl.text = profile.billingEmail;
        _billingLegalNameCtrl.text = profile.legalName;
        _billingCountryCtrl.text = profile.countryCode;
        _billingTaxIdCtrl.text = profile.taxId;
        _billingAddressCtrl.text = profile.billingAddress;
      });
    } catch (error) {
      if (!mounted || requestedScope != _billingScope) return;
      setState(() {
        _billingQuote = null;
        _billingError = _billingErrorMessage(error);
      });
    } finally {
      if (mounted && requestedScope == _billingScope) {
        setState(() => _billingLoading = false);
      }
    }
  }

  Future<void> _reloadBillingQuote() async {
    final requestedPlan = _billingPlan;
    final requestedPeriod = _billingPeriod;
    setState(() {
      _billingLoading = true;
      _billingQuote = null;
      _billingError = null;
    });
    try {
      final quote = await _paymentService.quote(
        plan: requestedPlan,
        period: requestedPeriod,
      );
      if (!mounted ||
          requestedPlan != _billingPlan ||
          requestedPeriod != _billingPeriod) {
        return;
      }
      setState(() => _billingQuote = quote);
    } catch (error) {
      if (!mounted) return;
      setState(() => _billingError = _billingErrorMessage(error));
    } finally {
      if (mounted &&
          requestedPlan == _billingPlan &&
          requestedPeriod == _billingPeriod) {
        setState(() => _billingLoading = false);
      }
    }
  }

  Future<void> _changeBillingScope(BillingScope scope) async {
    if (!_canUseOrganizationBilling(scope) || scope == _billingScope) return;
    setState(() {
      _billingScope = scope;
      _billingQuote = null;
      _billingError = null;
    });
    await _loadBillingData();
  }

  Future<void> _saveBillingProfile() async {
    final email = _billingEmailCtrl.text.trim().toLowerCase();
    final country = _billingCountryCtrl.text.trim().toUpperCase();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      xpDlg(context, 'Реквизиты', 'Введите корректный email для счетов.');
      return;
    }
    if (country.isNotEmpty && !RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      xpDlg(context, 'Реквизиты',
          'Код страны: две латинские буквы, например DE.');
      return;
    }

    setState(() => _billingProfileSaving = true);
    try {
      await _paymentService.saveProfile(
        scope: _billingScope,
        organizationId: _billingOrganizationId,
        profile: BillingProfile(
          billingEmail: email,
          legalName: _billingLegalNameCtrl.text.trim(),
          countryCode: country,
          taxId: _billingTaxIdCtrl.text.trim(),
          billingAddress: _billingAddressCtrl.text.trim(),
        ),
      );
      if (mounted) {
        xpDlg(
          context,
          'Реквизиты сохранены',
          'Данные для будущих счетов сохранены. Данные банковской карты Trimatrix не хранит.',
        );
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Реквизиты не сохранены', _billingErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _billingProfileSaving = false);
    }
  }

  Future<void> _activateTestSubscription() async {
    final quote = _billingQuote;
    if (quote == null || _billingActivating) return;
    final confirmed = await xpConfirm(
      context,
      'Тестовая активация',
      'Активировать ${quote.plan.label} на ${quote.period.label.toLowerCase()} '
          'за ${quote.formattedAmount}? Реальное списание не выполняется.',
    );
    if (!confirmed || !mounted) return;
    setState(() => _billingActivating = true);
    try {
      final activation = await _paymentService.activateTestSubscription(
        scope: _billingScope,
        organizationId: _billingOrganizationId,
        quote: quote,
      );
      await widget.onAccessChanged();
      if (!mounted) return;
      xpDlg(
        context,
        'Тариф активирован',
        '${activation.plan.label} активен до ${_shortDate(activation.validUntil)}. '
            'Операция тестовая, без списания денег.',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Тариф не активирован', _billingErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _billingActivating = false);
    }
  }

  Widget _billingSection() {
    if (!_canManageBilling) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _settingsPanel(
            title: 'Текущий тариф',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _infoRow('Рабочий тариф', widget.entitlements.plan.label),
                _infoRow('Статус', _accessStatusLabel()),
                if (widget.entitlements.usesOrganizationPlan)
                  _infoRow(
                    'Личный тариф',
                    widget.entitlements.personalPlan.label,
                  ),
                const SizedBox(height: 8),
                _notePanel(
                  'Тарифом и оплатой организации управляет только владелец. '
                  'Для вашей роли этот раздел доступен только для просмотра.',
                ),
              ],
            ),
          ),
        ],
      );
    }
    final organizationBillingAvailable =
        _canUseOrganizationBilling(BillingScope.organization);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Текущий тариф',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow(
            widget.entitlements.usesOrganizationPlan
                ? 'Рабочий тариф'
                : 'Личный тариф',
            widget.entitlements.plan.label,
          ),
          _infoRow('Статус', _accessStatusLabel()),
          if (widget.entitlements.usesOrganizationPlan)
            _infoRow('Личный тариф', widget.entitlements.personalPlan.label),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Выбор подписки',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _notePanel(
            'Сейчас работает тестовый платёжный режим. '
            'Сумма приходит с сервера, деньги не списываются. '
            'Перед подключением реальной оплаты тестовый режим будет отключён.',
          ),
          const SizedBox(height: 12),
          _optionChips(
            label: 'Кому принадлежит тариф',
            value: _billingScope.label,
            values: [
              BillingScope.personal.label,
              if (organizationBillingAvailable) BillingScope.organization.label,
            ],
            onSelect: (value) => _changeBillingScope(
              BillingScope.values.firstWhere((scope) => scope.label == value),
            ),
          ),
          if (widget.organizationAccess.role == OrganizationRole.admin)
            _notePanel(
              'Тарифом организации управляет только владелец. '
              'Здесь администратор может управлять только личной подпиской.',
            ),
          const SizedBox(height: 8),
          _optionChips(
            label: 'Тариф',
            value: _billingPlan.label,
            values: const [PlanTier.pro, PlanTier.enterprise]
                .map((plan) => plan.label)
                .toList(),
            onSelect: (value) {
              setState(() {
                _billingPlan =
                    PlanTier.values.firstWhere((plan) => plan.label == value);
              });
              _reloadBillingQuote();
            },
          ),
          _optionChips(
            label: 'Срок',
            value: _billingPeriod.label,
            values: BillingPeriod.values.map((period) => period.label).toList(),
            onSelect: (value) {
              setState(() {
                _billingPeriod = BillingPeriod.values
                    .firstWhere((period) => period.label == value);
              });
              _reloadBillingQuote();
            },
          ),
          if (_billingLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_billingError != null) ...[
            _notePanel(_billingError!),
            const SizedBox(height: 8),
            XpBtn(label: 'Повторить', onPressed: _loadBillingData),
          ] else if (_billingQuote case final quote?) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FC),
                border: Border.all(color: const Color(0xFF8FC6DF)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${quote.plan.label} · ${quote.period.label}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        quote.testMode
                            ? 'Тестовая активация'
                            : 'Сумма к оплате',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  quote.formattedAmount,
                  key: const ValueKey('billing-quote-amount'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.blueDark,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            XpBtn(
              label: _billingActivating
                  ? 'Активация…'
                  : 'Активировать тестовую подписку',
              primary: true,
              onPressed: _billingActivating ? null : _activateTestSubscription,
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Реквизиты для счетов',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(
            'Здесь хранятся только данные плательщика. '
            'Номер карты, CVV и другие платёжные секреты в приложение не вводятся.',
            style: TextStyle(fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _billingTextField(
                controller: _billingEmailCtrl,
                label: 'Email для счетов',
                keyboardType: TextInputType.emailAddress,
              ),
              _billingTextField(
                controller: _billingLegalNameCtrl,
                label: 'Имя / название организации',
              ),
              _billingTextField(
                controller: _billingCountryCtrl,
                label: 'Код страны',
                width: 180,
              ),
              _billingTextField(
                controller: _billingTaxIdCtrl,
                label: 'Налоговый номер',
              ),
              _billingTextField(
                controller: _billingAddressCtrl,
                label: 'Адрес для счёта',
                width: 470,
              ),
            ],
          ),
          const SizedBox(height: 10),
          XpBtn(
            label:
                _billingProfileSaving ? 'Сохранение…' : 'Сохранить реквизиты',
            onPressed: _billingProfileSaving ? null : _saveBillingProfile,
          ),
        ]),
      ),
    ]);
  }

  Widget _billingTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    double width = 280,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        enabled: !_billingLoading && !_billingProfileSaving,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  String _billingErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('billing_quote_v1') ||
        text.contains('current_billing_profile_v1') ||
        text.contains('PGRST202')) {
      return 'Тестовый платёжный модуль ещё не подключён. '
          'В Supabase нужно выполнить миграцию 019.';
    }
    if (text.contains('Organization billing access required')) {
      return 'Тариф организации может менять только владелец.';
    }
    if (text.contains('Test payments are disabled')) {
      return 'Тестовые платежи отключены на сервере.';
    }
    return text;
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

    final activeTeamParticipants = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.role != OrganizationRole.customer,
        )
        .length;
    final pendingTeamParticipants = _organizationParticipants
        .where(
          (participant) =>
              participant.isPending &&
              participant.role != OrganizationRole.customer,
        )
        .length;
    final activeCustomerParticipants = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.role == OrganizationRole.customer,
        )
        .length;
    final pendingCustomerParticipants = _organizationParticipants
        .where(
          (participant) =>
              participant.isPending &&
              participant.role == OrganizationRole.customer,
        )
        .length;
    final teamSeatLimit =
        widget.entitlements.limit(UsageLimit.organizationSeats);
    final customerSeatLimit =
        widget.entitlements.limit(UsageLimit.customerRepresentativeSeats);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _settingsPanel(
        title: 'Организация',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Название', access.organizationName ?? 'не указано'),
          _infoRow('ID', access.organizationId ?? 'не определён'),
          _infoRow('Моя роль', access.role.label),
          _infoRow(
            'Команда',
            teamSeatLimit == null
                ? '$activeTeamParticipants активно, $pendingTeamParticipants ожидают'
                : '$activeTeamParticipants активно, $pendingTeamParticipants ожидают из $teamSeatLimit',
          ),
          _infoRow(
            'Представители',
            customerSeatLimit == null
                ? '$activeCustomerParticipants активно, $pendingCustomerParticipants ожидают'
                : '$activeCustomerParticipants активно, $pendingCustomerParticipants ожидают из $customerSeatLimit',
          ),
          _notePanel(
            access.role == OrganizationRole.owner
                ? 'Владелец назначает администратора, сотрудников и заказчиков. Передача владения будет отдельной защищённой операцией.'
                : 'Администратор назначает сотрудников и заказчиков, но не может назначать администраторов или менять владельца.',
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _organizationWorkspaceSelector(),
      const SizedBox(height: 10),
      if (_organizationWorkspace == _OrganizationWorkspace.team)
        _teamWorkspace(access)
      else
        _customersWorkspace(access),
    ]);
  }

  Widget _organizationWorkspaceSelector() {
    return SegmentedButton<_OrganizationWorkspace>(
      key: const ValueKey('organization-workspace-selector'),
      segments: const [
        ButtonSegment(
          value: _OrganizationWorkspace.team,
          label: Text('Команда'),
        ),
        ButtonSegment(
          value: _OrganizationWorkspace.customers,
          label: Text('Заказчики'),
        ),
      ],
      selected: {_organizationWorkspace},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() {
          _organizationWorkspace = selection.first;
        });
      },
    );
  }

  Widget _teamWorkspace(OrganizationAccess access) {
    final teamParticipants = _organizationParticipants
        .where((participant) => participant.role != OrganizationRole.customer)
        .toList();
    final assignableRoles = OrganizationAdministrationPolicy.assignableRoles(
      access.role,
    ).where((role) => role != OrganizationRole.customer).toList();
    return _settingsPanel(
      title: 'Команда',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _notePanel(
            'Заполните первую строку и выберите действие в меню ⋮. '
            'Приглашение одновременно создаёт участника команды.',
          ),
          const SizedBox(height: 8),
          _teamTable(teamParticipants, assignableRoles, access.role),
        ],
      ),
    );
  }

  Widget _customersWorkspace(OrganizationAccess access) {
    return _customerDirectoryPanel();
  }

  Widget _teamTable(
    List<OrganizationParticipant> participants,
    List<OrganizationRole> assignableRoles,
    OrganizationRole actorRole,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 980 ? 980.0 : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFC9E2F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFEAF6FC),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFC9E2F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _customerTableCell('Email', flex: 2, header: true),
                        _customerTableCell('Ник', flex: 1, header: true),
                        _customerTableCell('Имя', flex: 2, header: true),
                        _customerTableCell('Роль', flex: 1, header: true),
                        _customerTableCell('Функции', flex: 2, header: true),
                        _customerTableCell('Статус', flex: 1, header: true),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Container(
                    key: const ValueKey('team-draft-row'),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2FAFE),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFC9E2F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _organizationTableInput(
                          controller: _memberEmailCtrl,
                          hint: 'email',
                          flex: 2,
                        ),
                        _organizationTableInput(
                          controller: _memberNicknameCtrl,
                          hint: 'ник',
                          flex: 1,
                        ),
                        _organizationTableInput(
                          controller: _memberDisplayNameCtrl,
                          hint: 'имя',
                          flex: 2,
                        ),
                        _organizationTableRoleDropdown(
                          roles: assignableRoles,
                        ),
                        _organizationTableFunctionSelector(),
                        _customerTableCell('новый', flex: 1, draft: true),
                        SizedBox(
                          width: 48,
                          height: 56,
                          child: PopupMenuButton<_TeamDraftAction>(
                            key: const ValueKey('team-draft-actions'),
                            tooltip: 'Действия с новым сотрудником',
                            enabled: !_organizationBusy,
                            icon: const Icon(Icons.more_vert),
                            onSelected: (action) {
                              switch (action) {
                                case _TeamDraftAction.invite:
                                  _inviteOrganizationMember();
                                case _TeamDraftAction.clear:
                                  _clearMemberDraft();
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: _TeamDraftAction.invite,
                                child: Text('Пригласить сотрудника'),
                              ),
                              PopupMenuItem(
                                value: _TeamDraftAction.clear,
                                child: Text('Очистить строку'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...participants.asMap().entries.map(
                        (entry) => _teamParticipantRow(
                          entry.value,
                          entry.key,
                          assignableRoles,
                          actorRole,
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

  Widget _organizationTableInput({
    required TextEditingController controller,
    required String hint,
    required int flex,
    bool enabled = true,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            enabled: enabled && !_organizationBusy,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 11, height: 1.2),
            decoration: _organizationGridInputDecoration(hintText: hint),
          ),
        ),
      ),
    );
  }

  Widget _organizationTableRoleDropdown({
    required List<OrganizationRole> roles,
  }) {
    final selected =
        roles.contains(_selectedMemberRole) ? _selectedMemberRole : roles.first;
    return Expanded(
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: SizedBox(
          height: 42,
          child: DropdownButtonFormField<OrganizationRole>(
            key: ValueKey('team-draft-role-${selected.name}'),
            initialValue: selected,
            isExpanded: true,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              color: Colors.black,
            ),
            decoration: _organizationGridInputDecoration(),
            items: roles
                .map(
                  (role) => DropdownMenuItem(
                    value: role,
                    child: Text(role.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _organizationBusy
                ? null
                : (role) => setState(() => _selectedMemberRole = role!),
          ),
        ),
      ),
    );
  }

  Widget _organizationTableFunctionSelector() {
    final enabled = _selectedMemberRole == OrganizationRole.employee;
    final label = !enabled
        ? '-'
        : _selectedMemberFunctions.isEmpty
            ? 'не выбраны'
            : _selectedMemberFunctions
                .map((function) => function.label)
                .join(', ');
    return Expanded(
      flex: 2,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: PopupMenuButton<OrganizationMemberFunction>(
          key: const ValueKey('team-draft-functions'),
          enabled: enabled && !_organizationBusy,
          tooltip: 'Функции сотрудника',
          onSelected: (function) {
            setState(() {
              final next = Set<OrganizationMemberFunction>.from(
                _selectedMemberFunctions,
              );
              next.contains(function)
                  ? next.remove(function)
                  : next.add(function);
              _selectedMemberFunctions = next;
            });
          },
          itemBuilder: (_) => OrganizationMemberFunction.values
              .map(
                (function) => CheckedPopupMenuItem(
                  value: function,
                  checked: _selectedMemberFunctions.contains(function),
                  child: Text(function.label),
                ),
              )
              .toList(),
          child: SizedBox(
            height: 42,
            child: InputDecorator(
              decoration: _organizationGridInputDecoration(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, height: 1.2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _organizationGridInputDecoration({String? hintText}) {
    const borderColor = Color(0xFFACC9D9);
    const radius = BorderRadius.all(Radius.circular(6));
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF78909C), fontSize: 11),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Color(0xFF2D8EB9), width: 1.5),
      ),
    );
  }

  Widget _teamParticipantRow(
    OrganizationParticipant participant,
    int index,
    List<OrganizationRole> assignableRoles,
    OrganizationRole actorRole,
  ) {
    final functions = participant.functions.isEmpty
        ? '-'
        : participant.functions.map((function) => function.label).join(', ');
    final status = participant.isPending
        ? participant.emailSent
            ? 'приглашён'
            : 'ошибка email'
        : participant.role == OrganizationRole.owner
            ? 'владелец'
            : 'активен';
    final canManage = participant.role != OrganizationRole.owner &&
        !(actorRole == OrganizationRole.admin &&
            participant.role == OrganizationRole.admin);
    return Container(
      key: ValueKey('team-row-${participant.id}'),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFF8FCFF),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE2EEF4)),
        ),
      ),
      child: Row(
        children: [
          _customerTableCell(participant.email, flex: 2),
          _customerTableCell(participant.nickname, flex: 1, bold: true),
          _customerTableCell(
            participant.displayName.isEmpty
                ? 'не указано'
                : participant.displayName,
            flex: 2,
          ),
          _customerTableCell(participant.role.label, flex: 1),
          _customerTableCell(functions, flex: 2),
          _customerTableCell(status, flex: 1),
          SizedBox(
            width: 48,
            child: PopupMenuButton<_TeamAction>(
              tooltip: 'Действия с участником',
              enabled: canManage && !_organizationBusy,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) => _handleTeamAction(
                action,
                participant,
                assignableRoles,
              ),
              itemBuilder: (_) => participant.isPending
                  ? const [
                      PopupMenuItem(
                        value: _TeamAction.resendInvitation,
                        child: Text('Повторить приглашение'),
                      ),
                      PopupMenuItem(
                        value: _TeamAction.cancelInvitation,
                        child: Text('Отменить приглашение'),
                      ),
                    ]
                  : const [
                      PopupMenuItem(
                        value: _TeamAction.edit,
                        child: Text('Изменить роль и функции'),
                      ),
                      PopupMenuItem(
                        value: _TeamAction.remove,
                        child: Text('Удалить из организации'),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
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
    return _settingsPanel(
      title: 'Заказчики',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_customerDirectoryAvailable)
            _notePanel(
              _customerDirectoryError ??
                  'Справочник заказчиков недоступен на сервере.',
            )
          else ...[
            if (_customerRequestsError != null) ...[
              _notePanel(
                'Справочник работает, но заявки «Заказчик не найден» '
                'временно недоступны: $_customerRequestsError',
              ),
              const SizedBox(height: 8),
            ],
            _notePanel(
              'Первая строка создаёт нового заказчика. Чтобы добавить человека '
              'к существующему заказчику, нажмите «Добавить представителя» в '
              'его строке или выберите это действие в меню ⋮. Код присвоится '
              'автоматически.',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Показать архив'),
                  const SizedBox(width: 6),
                  Switch.adaptive(
                    key: const ValueKey('show-archived-customers'),
                    value: _showArchivedCustomers,
                    onChanged: _customerBusy
                        ? null
                        : (value) {
                            setState(() => _showArchivedCustomers = value);
                            _loadCustomerDirectory();
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _customerDirectoryTable(managerCandidates),
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
    final participantsByUserId = <String, OrganizationParticipant>{};
    for (final participant in participants) {
      final userId = participant.userId;
      if (userId != null && userId.isNotEmpty) {
        participantsByUserId.putIfAbsent(userId, () => participant);
      }
    }
    final selectedValue =
        value != null && participantsByUserId.containsKey(value) ? value : '';

    return DropdownButtonFormField<String>(
      key: label == 'Ответственный'
          ? const ValueKey('customer-responsible-select')
          : ValueKey('$label-$selectedValue'),
      initialValue: selectedValue,
      isExpanded: true,
      style: const TextStyle(fontSize: 11, height: 1.2, color: Colors.black),
      decoration: _organizationGridInputDecoration(hintText: label),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text('Не выбран'),
        ),
        ...participantsByUserId.values.map(
          (participant) => DropdownMenuItem<String>(
            value: participant.userId!,
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

  Widget _customerDirectoryTable(
    List<OrganizationParticipant> managerCandidates,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 1160 ? 1160.0 : constraints.maxWidth;
        final rows = <({
          OrganizationCustomer customer,
          OrganizationCustomerRepresentative? representative,
        })>[];
        for (final customer in _organizationCustomers) {
          final representatives = customer.allRepresentatives;
          if (representatives.isEmpty) {
            rows.add((customer: customer, representative: null));
          } else {
            for (final representative in representatives) {
              rows.add((customer: customer, representative: representative));
            }
          }
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFC9E2F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF6FC),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFC9E2F0)),
                    ),
                  ),
                  child: Row(children: [
                    _customerTableCell('Заказчик', flex: 2, header: true),
                    _customerTableCell(
                      'Ответственный сотрудник',
                      flex: 2,
                      header: true,
                    ),
                    _customerTableCell('Почта', flex: 2, header: true),
                    _customerTableCell('Ник', flex: 1, header: true),
                    _customerTableCell('Имя', flex: 2, header: true),
                    _customerTableCell('Статус', flex: 1, header: true),
                    const SizedBox(width: 48),
                  ]),
                ),
                _customerDraftRow(managerCandidates),
                ...rows.asMap().entries.map(
                      (entry) => _customerDirectoryRow(
                        entry.value.customer,
                        entry.value.representative,
                        entry.key,
                      ),
                    ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _customerDraftRow(
    List<OrganizationParticipant> managerCandidates,
  ) {
    final representativeMode =
        _editingCustomerId != null && _customerDraftForRepresentative;
    final selectedManager = managerCandidates
        .where(
            (participant) => participant.userId == _selectedCustomerManagerId)
        .firstOrNull;
    return Container(
      key: const ValueKey('customer-draft-row'),
      decoration: const BoxDecoration(
        color: Color(0xFFF2FAFE),
        border: Border(bottom: BorderSide(color: Color(0xFFC9E2F0))),
      ),
      child: Row(
        children: [
          if (representativeMode)
            _customerTableCell(
              '${_customerNameCtrl.text}\n${_customerCodeCtrl.text}',
              flex: 2,
              bold: true,
              draft: true,
            )
          else
            _organizationTableInput(
              controller: _customerNameCtrl,
              hint: 'название нового заказчика',
              flex: 2,
              enabled: !_customerBusy,
            ),
          if (representativeMode)
            _customerTableCell(
              selectedManager == null
                  ? 'не назначен'
                  : _participantLabel(selectedManager),
              flex: 2,
              draft: true,
            )
          else
            Expanded(
              flex: 2,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
                ),
                child: _participantDropdown(
                  label: 'Ответственный',
                  value: _selectedCustomerManagerId,
                  participants: managerCandidates,
                  onChanged: (value) =>
                      setState(() => _selectedCustomerManagerId = value),
                ),
              ),
            ),
          _organizationTableInput(
            controller: _customerRepresentativeEmailCtrl,
            hint: 'почта',
            flex: 2,
            enabled: !_customerBusy,
          ),
          _organizationTableInput(
            controller: _customerRepresentativeNicknameCtrl,
            hint: 'ник',
            flex: 1,
            enabled: !_customerBusy,
          ),
          _organizationTableInput(
            controller: _customerRepresentativeDisplayNameCtrl,
            hint: 'имя',
            flex: 2,
            enabled: !_customerBusy,
          ),
          _customerTableCell(
            _editingCustomerId == null
                ? 'новый заказчик'
                : representativeMode
                    ? 'новый представитель'
                    : 'изменение',
            flex: 1,
            draft: true,
          ),
          SizedBox(
            width: 48,
            height: 56,
            child: PopupMenuButton<_CustomerDraftAction>(
              key: const ValueKey('customer-draft-actions'),
              tooltip: 'Действия с новой строкой заказчика',
              enabled: !_customerBusy,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _CustomerDraftAction.save:
                  case _CustomerDraftAction.saveWithoutRepresentative:
                    _saveCustomer(inviteRepresentative: false);
                  case _CustomerDraftAction.invite:
                    _saveCustomer(inviteRepresentative: true);
                  case _CustomerDraftAction.clear:
                    _clearCustomerForm();
                }
              },
              itemBuilder: (_) => [
                if (_editingCustomerId != null &&
                    !_customerDraftForRepresentative)
                  const PopupMenuItem(
                    value: _CustomerDraftAction.save,
                    child: Text('Сохранить изменения'),
                  )
                else ...[
                  const PopupMenuItem(
                    value: _CustomerDraftAction.invite,
                    child: Text('Пригласить представителя'),
                  ),
                  if (_editingCustomerId == null)
                    const PopupMenuItem(
                      value: _CustomerDraftAction.saveWithoutRepresentative,
                      child: Text('Сохранить без представителя'),
                    ),
                ],
                const PopupMenuItem(
                  value: _CustomerDraftAction.clear,
                  child: Text('Очистить строку'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerDirectoryRow(
    OrganizationCustomer customer,
    OrganizationCustomerRepresentative? representative,
    int index,
  ) {
    final status = !customer.active
        ? 'в архиве'
        : representative == null
            ? 'без представителя'
            : representative.pending
                ? representative.emailSent
                    ? 'ожидает регистрации'
                    : 'ошибка email'
                : 'активен';
    final hasExistingCustomerUser = _organizationParticipants.any(
      (participant) =>
          !participant.isPending &&
          participant.userId != null &&
          participant.role == OrganizationRole.customer,
    );
    return Container(
      key: ValueKey(
        'customer-row-${customer.id}-${representative?.id ?? 'empty'}',
      ),
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFF8FCFF),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE2EEF4)),
        ),
      ),
      child: Row(children: [
        _customerTableCell(
          '${customer.name}\n${customer.code}',
          flex: 2,
          bold: true,
        ),
        _customerTableCell(
          customer.primaryManagerNickname.isEmpty
              ? 'не назначен'
              : customer.primaryManagerNickname,
          flex: 2,
        ),
        if (representative == null && customer.active)
          _customerAddRepresentativeCell(customer)
        else
          _customerTableCell(representative?.email ?? '—', flex: 2),
        _customerTableCell(representative?.nickname ?? '—', flex: 1),
        _customerTableCell(representative?.displayName ?? '—', flex: 2),
        _customerTableCell(status, flex: 1),
        SizedBox(
          width: 48,
          child: PopupMenuButton<_CustomerAction>(
            key: ValueKey('customer-actions-${customer.id}'),
            tooltip: 'Действия с заказчиком',
            enabled: !_customerBusy,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) =>
                _handleCustomerAction(action, customer, representative),
            itemBuilder: (_) => [
              if (customer.active) ...[
                const PopupMenuItem(
                  value: _CustomerAction.edit,
                  child: Text('Изменить заказчика'),
                ),
                const PopupMenuItem(
                  value: _CustomerAction.addRepresentative,
                  child: Text('Добавить представителя'),
                ),
                if (hasExistingCustomerUser)
                  const PopupMenuItem(
                    value: _CustomerAction.linkExistingRepresentative,
                    child: Text('Выбрать зарегистрированного'),
                  ),
                if (representative?.pending == true) ...[
                  const PopupMenuItem(
                    value: _CustomerAction.resendInvitation,
                    child: Text('Повторить приглашение'),
                  ),
                  const PopupMenuItem(
                    value: _CustomerAction.cancelInvitation,
                    child: Text('Отменить приглашение'),
                  ),
                ],
              ],
              const PopupMenuItem(
                value: _CustomerAction.openJobs,
                child: Text('Открыть работы'),
              ),
              if (customer.active)
                const PopupMenuItem(
                  value: _CustomerAction.archive,
                  child: Text(
                    'В архив',
                    style: TextStyle(color: Color(0xFFB42318)),
                  ),
                )
              else
                const PopupMenuItem(
                  value: _CustomerAction.restore,
                  child: Text('Восстановить из архива'),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _customerTableCell(
    String text, {
    required int flex,
    bool header = false,
    bool bold = false,
    bool draft = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        height: header ? 40 : (draft ? 56 : 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: header ? 10 : 11,
            height: 1.2,
            fontWeight: header || bold ? FontWeight.w900 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _customerAddRepresentativeCell(OrganizationCustomer customer) {
    return Expanded(
      flex: 2,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFC9E2F0))),
        ),
        child: TextButton.icon(
          key: ValueKey('add-representative-${customer.id}'),
          onPressed: _customerBusy
              ? null
              : () => _prepareCustomerRepresentative(customer),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
          label: const Text('Добавить представителя'),
        ),
      ),
    );
  }

  Widget _customerRequestRow(OrganizationCustomerRequest request) {
    final existingCustomer = _matchingCustomerForRequest(request);
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
          Align(
            alignment: Alignment.centerRight,
            child: XpBtn(
              key: ValueKey('resolve-customer-request-${request.id}'),
              label: existingCustomer == null
                  ? 'Заполнить данные'
                  : 'Связать с созданным',
              primary: true,
              onPressed: _customerBusy
                  ? null
                  : () => _createOrLinkCustomerRequest(
                        request,
                        existingCustomer: existingCustomer,
                      ),
            ),
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
        setState(() => _organizationParticipants = participants);
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
      final customers = await _customerService.listCustomers(
        organizationId,
        includeArchived: _showArchivedCustomers,
      );
      var requests = const <OrganizationCustomerRequest>[];
      String? requestsError;
      try {
        requests = await _customerService.listPendingRequests(organizationId);
      } catch (error) {
        requestsError = _customerError(error);
      }
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _customerRequests = requests;
        _customerDirectoryAvailable = true;
        _customerDirectoryError = null;
        _customerRequestsError = requestsError;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _customerDirectoryAvailable = false;
        _customerDirectoryError =
            'Справочник заказчиков недоступен: ${_customerError(error)}';
      });
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _saveCustomer({required bool inviteRepresentative}) async {
    final organizationId = widget.organizationAccess.organizationId;
    final requestedCode = _customerCodeCtrl.text.trim();
    final name = _customerNameCtrl.text.trim();
    final representativeEmail =
        _customerRepresentativeEmailCtrl.text.trim().toLowerCase();
    final representativeNickname =
        _customerRepresentativeNicknameCtrl.text.trim().toLowerCase();
    final representativeDisplayName =
        _customerRepresentativeDisplayNameCtrl.text.trim();
    if (organizationId == null) return;
    if (name.length < 2) {
      xpDlg(context, 'Заказчик', 'Введите название заказчика.');
      return;
    }
    if (inviteRepresentative) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
          .hasMatch(representativeEmail)) {
        xpDlg(context, 'Представитель', 'Введите корректный email.');
        return;
      }
      if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(representativeNickname)) {
        xpDlg(
          context,
          'Представитель',
          'Ник: 3–24 символа, латиница, цифры и подчёркивание.',
        );
        return;
      }
      if (representativeDisplayName.isEmpty) {
        xpDlg(context, 'Представитель', 'Введите имя представителя.');
        return;
      }
      final seatLimit = widget.entitlements.limit(
        UsageLimit.customerRepresentativeSeats,
      );
      final usedSeats = _organizationParticipants
          .where((participant) => participant.role == OrganizationRole.customer)
          .length;
      if (seatLimit != null && usedSeats >= seatLimit) {
        xpDlg(
          context,
          'Нет свободных мест для представителей',
          'Использовано $usedSeats из $seatLimit мест представителей заказчиков. '
              'Введённые данные оставлены в строке. Освободите место или '
              'измените тариф и повторите приглашение.',
        );
        return;
      }
    }

    final existingCustomer = _existingCustomerForDraft(name);
    final targetCustomerId = existingCustomer?.id ?? _editingCustomerId;
    final managerUserId =
        _selectedCustomerManagerId ?? existingCustomer?.primaryManagerUserId;

    setState(() => _customerBusy = true);
    try {
      Future<String> save(String code) => _customerService.saveCustomer(
            organizationId: organizationId,
            code: code,
            name: name,
            managerUserId: managerUserId,
            customerUserId: _selectedCustomerUserId,
            customerId: targetCustomerId,
          );

      late final String customerId;
      if (inviteRepresentative &&
          (existingCustomer != null ||
              (_customerDraftForRepresentative && targetCustomerId != null))) {
        // Adding another representative must not rewrite the customer. Older
        // server versions replaced customer links during such an update.
        customerId = targetCustomerId!;
      } else {
        try {
          customerId = await save(existingCustomer?.code ?? requestedCode);
        } catch (error) {
          final needsLegacyCode = targetCustomerId == null &&
              requestedCode.isEmpty &&
              error.toString().toLowerCase().contains('customer code');
          if (!needsLegacyCode) rethrow;
          customerId = await save(_nextCustomerCode());
        }
      }
      if (_customerRequestBeingCreatedId != null) {
        await _customerService.resolveRequest(
          requestId: _customerRequestBeingCreatedId!,
          customerId: customerId,
        );
      }
      Object? invitationError;
      if (inviteRepresentative) {
        try {
          await _organizationService.inviteMember(
            organizationId: organizationId,
            email: representativeEmail,
            nickname: representativeNickname,
            displayName: representativeDisplayName,
            role: OrganizationRole.customer,
            functions: const {},
            customerId: customerId,
          );
        } catch (error) {
          invitationError = error;
        }
      }
      final invitationWasSaved = _invitationWasSaved(invitationError);
      if (invitationError == null || invitationWasSaved) {
        _clearCustomerForm(notify: false);
      }
      final customers = await _customerService.listCustomers(
        organizationId,
        includeArchived: _showArchivedCustomers,
      );
      var requests = const <OrganizationCustomerRequest>[];
      String? requestsError;
      try {
        requests = await _customerService.listPendingRequests(organizationId);
      } catch (error) {
        requestsError = _customerError(error);
      }
      if (!mounted) return;
      final retainedCustomer =
          customers.where((customer) => customer.id == customerId).firstOrNull;
      setState(() {
        _organizationCustomers = customers;
        _customerRequests = requests;
        _customerDirectoryAvailable = true;
        _customerDirectoryError = null;
        _customerRequestsError = requestsError;
        if (invitationError != null && !invitationWasSaved) {
          _editingCustomerId = customerId;
          _customerDraftForRepresentative = true;
          _customerRequestBeingCreatedId = null;
          _selectedCustomerUserId = null;
          if (retainedCustomer != null) {
            _customerCodeCtrl.text = retainedCustomer.code;
            _customerNameCtrl.text = retainedCustomer.name;
            _selectedCustomerManagerId = retainedCustomer.primaryManagerUserId;
          }
        }
      });
      if (invitationError != null && mounted) {
        if (invitationWasSaved) {
          xpDlg(
            context,
            'Приглашение сохранено, письмо не отправлено',
            _accessError(invitationError),
          );
        } else {
          xpDlg(
            context,
            'Приглашение не отправлено',
            '${_accessError(invitationError)}\n\n'
                'Введённые данные оставлены в строке. Исправьте причину и повторите приглашение.',
          );
        }
      }
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Заказчик не сохранён', _customerError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  bool _invitationWasSaved(Object? error) =>
      error is OrganizationInvitationException &&
      error.code == 'delivery_failed';

  String _nextCustomerCode() {
    var largest = 0;
    final pattern = RegExp(r'^C-(\d+)$', caseSensitive: false);
    for (final customer in _organizationCustomers) {
      final match = pattern.firstMatch(customer.code.trim());
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > largest) largest = number;
    }
    return 'C-${(largest + 1).toString().padLeft(4, '0')}';
  }

  OrganizationCustomer? _existingCustomerForDraft(String rawName) {
    for (final customer in _organizationCustomers) {
      if (customer.id == _editingCustomerId) return customer;
    }
    if (_editingCustomerId != null) return null;

    final normalized = rawName.trim().toLowerCase();
    final displayPattern = RegExp(
      r'^(c-\d+)\s*[·•—–-]\s*(.+)$',
      caseSensitive: false,
    );
    final displayMatch = displayPattern.firstMatch(normalized);
    for (final customer in _organizationCustomers) {
      if (customer.name.trim().toLowerCase() == normalized ||
          customer.displayLabel.trim().toLowerCase() == normalized) {
        return customer;
      }
      if (displayMatch != null &&
          customer.code.toLowerCase() == displayMatch.group(1) &&
          customer.name.trim().toLowerCase() == displayMatch.group(2)?.trim()) {
        return customer;
      }
    }
    return null;
  }

  void _editCustomer(OrganizationCustomer customer) {
    final managerIds = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.role != OrganizationRole.customer,
        )
        .map((participant) => participant.userId)
        .whereType<String>()
        .toSet();
    setState(() {
      _editingCustomerId = customer.id;
      _customerDraftForRepresentative = false;
      _customerRequestBeingCreatedId = null;
      _customerCodeCtrl.text = customer.code;
      _customerNameCtrl.text = customer.name;
      _customerRepresentativeEmailCtrl.clear();
      _customerRepresentativeNicknameCtrl.clear();
      _customerRepresentativeDisplayNameCtrl.clear();
      _selectedCustomerManagerId =
          managerIds.contains(customer.primaryManagerUserId)
              ? customer.primaryManagerUserId
              : null;
      _selectedCustomerUserId = null;
    });
  }

  void _prepareCustomerRepresentative(OrganizationCustomer customer) {
    setState(() {
      _editingCustomerId = customer.id;
      _customerDraftForRepresentative = true;
      _customerRequestBeingCreatedId = null;
      _customerCodeCtrl.text = customer.code;
      _customerNameCtrl.text = customer.name;
      _customerRepresentativeEmailCtrl.clear();
      _customerRepresentativeNicknameCtrl.clear();
      _customerRepresentativeDisplayNameCtrl.clear();
      _selectedCustomerManagerId = customer.primaryManagerUserId;
      _selectedCustomerUserId = null;
    });
  }

  void _clearCustomerForm({bool notify = true}) {
    void clear() {
      _editingCustomerId = null;
      _customerDraftForRepresentative = false;
      _customerRequestBeingCreatedId = null;
      _customerCodeCtrl.clear();
      _customerNameCtrl.clear();
      _customerRepresentativeEmailCtrl.clear();
      _customerRepresentativeNicknameCtrl.clear();
      _customerRepresentativeDisplayNameCtrl.clear();
      _selectedCustomerManagerId = null;
      _selectedCustomerUserId = null;
    }

    if (notify && mounted) {
      setState(clear);
    } else {
      clear();
    }
  }

  Future<void> _confirmArchiveCustomer(
    OrganizationCustomer customer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переместить заказчика в архив?'),
        content: Text(
          '${customer.code} · ${customer.name}\n\n'
          'Новые работы больше не смогут выбирать этого заказчика.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB42318),
            ),
            child: const Text('В архив'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _archiveCustomer(customer);
    }
  }

  Future<void> _archiveCustomer(OrganizationCustomer customer) async {
    setState(() => _customerBusy = true);
    try {
      await _customerService.archiveCustomer(customer.id);
      final organizationId = widget.organizationAccess.organizationId;
      if (organizationId != null) {
        final customers = await _customerService.listCustomers(
          organizationId,
          includeArchived: _showArchivedCustomers,
        );
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

  OrganizationCustomer? _matchingCustomerForRequest(
    OrganizationCustomerRequest request,
  ) {
    final requestedName = request.requestedName.trim().toLowerCase();
    return _organizationCustomers
        .where(
          (customer) =>
              customer.active &&
              (customer.name.trim().toLowerCase() == requestedName ||
                  customer.code.trim().toLowerCase() == requestedName),
        )
        .firstOrNull;
  }

  Future<void> _createOrLinkCustomerRequest(
    OrganizationCustomerRequest request, {
    required OrganizationCustomer? existingCustomer,
  }) async {
    if (existingCustomer == null) {
      final requesterCanBeResponsible = _organizationParticipants.any(
        (participant) =>
            !participant.isPending &&
            participant.userId == request.requestedByUserId &&
            participant.role != OrganizationRole.customer,
      );
      setState(() {
        _editingCustomerId = null;
        _customerDraftForRepresentative = false;
        _customerRequestBeingCreatedId = request.id;
        _customerCodeCtrl.clear();
        _customerNameCtrl.text = request.requestedName;
        _selectedCustomerManagerId =
            requesterCanBeResponsible ? request.requestedByUserId : null;
        _selectedCustomerUserId = null;
        _customerRepresentativeEmailCtrl.clear();
        _customerRepresentativeNicknameCtrl.clear();
        _customerRepresentativeDisplayNameCtrl.clear();
      });
      xpDlg(
        context,
        'Данные заявки заполнены',
        'При необходимости добавьте почту, ник и имя представителя. Затем '
            'выберите нужное действие в меню ⋮. Работа свяжется автоматически.',
      );
      return;
    }

    setState(() => _customerBusy = true);
    try {
      await _customerService.resolveRequest(
        requestId: request.id,
        customerId: existingCustomer.id,
      );
      if (mounted) {
        setState(() {
          _customerRequests = _customerRequests
              .where((item) => item.id != request.id)
              .toList(growable: false);
        });
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

  void _clearMemberDraft() {
    setState(() {
      _memberEmailCtrl.clear();
      _memberNicknameCtrl.clear();
      _memberDisplayNameCtrl.clear();
      _selectedMemberRole = OrganizationRole.employee;
      _selectedMemberFunctions = {
        OrganizationMemberFunction.inspectionSpecialist,
      };
    });
  }

  Future<void> _handleTeamAction(
    _TeamAction action,
    OrganizationParticipant participant,
    List<OrganizationRole> assignableRoles,
  ) async {
    switch (action) {
      case _TeamAction.edit:
        await _editTeamParticipant(participant, assignableRoles);
      case _TeamAction.resendInvitation:
        await _resendTeamInvitation(participant);
      case _TeamAction.cancelInvitation:
        await _cancelOrganizationInvitation(participant);
      case _TeamAction.remove:
        await _confirmRemoveTeamParticipant(participant);
    }
  }

  Future<void> _resendTeamInvitation(
    OrganizationParticipant participant,
  ) async {
    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return;
    setState(() => _organizationBusy = true);
    try {
      await _organizationService.inviteMember(
        organizationId: organizationId,
        email: participant.email,
        nickname: participant.nickname,
        displayName: participant.displayName,
        role: participant.role,
        functions: participant.functions,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() => _organizationParticipants = participants);
      xpDlg(
        context,
        'Приглашение отправлено',
        'Письмо для ${_participantLabel(participant)} отправлено повторно.',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отправлено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _editTeamParticipant(
    OrganizationParticipant participant,
    List<OrganizationRole> assignableRoles,
  ) async {
    var selectedRole = participant.role;
    var selectedFunctions = Set<OrganizationMemberFunction>.from(
      participant.functions,
    );
    final result = await showDialog<
        ({
          OrganizationRole role,
          Set<OrganizationMemberFunction> functions,
        })>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Изменить ${_participantLabel(participant)}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<OrganizationRole>(
                  key: const ValueKey('team-edit-role'),
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Роль',
                    border: OutlineInputBorder(),
                  ),
                  items: assignableRoles
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(),
                  onChanged: (role) => setDialogState(
                    () => selectedRole = role!,
                  ),
                ),
                if (selectedRole == OrganizationRole.employee) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Функции',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  ...OrganizationMemberFunction.values.map(
                    (function) => CheckboxListTile(
                      value: selectedFunctions.contains(function),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(function.label),
                      onChanged: (checked) => setDialogState(() {
                        final next = Set<OrganizationMemberFunction>.from(
                          selectedFunctions,
                        );
                        checked == true
                            ? next.add(function)
                            : next.remove(function);
                        selectedFunctions = next;
                      }),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отменить'),
            ),
            FilledButton(
              key: const ValueKey('team-edit-save'),
              onPressed: () => Navigator.pop(
                dialogContext,
                (
                  role: selectedRole,
                  functions: selectedRole == OrganizationRole.employee
                      ? selectedFunctions
                      : <OrganizationMemberFunction>{},
                ),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null || participant.userId == null) return;

    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return;
    setState(() => _organizationBusy = true);
    try {
      await _organizationService.updateMember(
        organizationId: organizationId,
        userId: participant.userId!,
        role: result.role,
        functions: result.functions,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() => _organizationParticipants = participants);
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Участник не изменён', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _confirmRemoveTeamParticipant(
    OrganizationParticipant participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить из организации?'),
        content: Text(
          '${_participantLabel(participant)} потеряет рабочие права. '
          'Его личный аккаунт не удаляется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отменить'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || participant.userId == null) return;
    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return;

    setState(() => _organizationBusy = true);
    try {
      await _organizationService.removeMember(
        organizationId: organizationId,
        userId: participant.userId!,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() => _organizationParticipants = participants);
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Участник не удалён', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  Future<void> _handleCustomerAction(
    _CustomerAction action,
    OrganizationCustomer customer,
    OrganizationCustomerRepresentative? representative,
  ) async {
    switch (action) {
      case _CustomerAction.edit:
        _editCustomer(customer);
      case _CustomerAction.addRepresentative:
        _prepareCustomerRepresentative(customer);
      case _CustomerAction.linkExistingRepresentative:
        await _linkExistingCustomerRepresentative(customer);
      case _CustomerAction.resendInvitation:
        if (representative != null) {
          await _resendCustomerInvitation(customer, representative);
        }
      case _CustomerAction.cancelInvitation:
        if (representative != null) {
          await _cancelCustomerInvitation(representative);
        }
      case _CustomerAction.openJobs:
        await _openCustomerJobs(customer);
      case _CustomerAction.archive:
        await _confirmArchiveCustomer(customer);
      case _CustomerAction.restore:
        await _restoreCustomer(customer);
    }
  }

  Future<void> _linkExistingCustomerRepresentative(
    OrganizationCustomer customer,
  ) async {
    final linkedUserIds = customer.allRepresentatives
        .map((representative) => representative.userId)
        .whereType<String>()
        .toSet();
    final candidates = _organizationParticipants
        .where(
          (participant) =>
              !participant.isPending &&
              participant.userId != null &&
              participant.role == OrganizationRole.customer &&
              !linkedUserIds.contains(participant.userId),
        )
        .toList();
    if (candidates.isEmpty) {
      xpDlg(
        context,
        'Представители',
        'Нет других зарегистрированных представителей для подключения.',
      );
      return;
    }

    String? selectedUserId = candidates.first.userId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Представитель: ${customer.name}'),
          content: SizedBox(
            width: 440,
            child: DropdownButtonFormField<String>(
              initialValue: selectedUserId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Зарегистрированный заказчик',
                border: OutlineInputBorder(),
              ),
              items: candidates
                  .map(
                    (participant) => DropdownMenuItem(
                      value: participant.userId,
                      child: Text(
                        participant.nickname.isNotEmpty
                            ? participant.nickname
                            : participant.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setDialogState(() => selectedUserId = value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отменить'),
            ),
            FilledButton(
              onPressed: selectedUserId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Подключить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedUserId == null || !mounted) return;

    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null) return;
    setState(() => _customerBusy = true);
    try {
      await _customerService.saveCustomer(
        organizationId: organizationId,
        code: customer.code,
        name: customer.name,
        managerUserId: customer.primaryManagerUserId,
        customerUserId: selectedUserId,
        customerId: customer.id,
      );
      final customers = await _customerService.listCustomers(
        organizationId,
        includeArchived: _showArchivedCustomers,
      );
      if (mounted) setState(() => _organizationCustomers = customers);
    } catch (error) {
      if (mounted) {
        xpDlg(
          context,
          'Представитель не подключён',
          _customerError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _restoreCustomer(OrganizationCustomer customer) async {
    setState(() => _customerBusy = true);
    try {
      await _customerService.restoreCustomer(customer.id);
      final organizationId = widget.organizationAccess.organizationId;
      if (organizationId != null) {
        final customers = await _customerService.listCustomers(
          organizationId,
          includeArchived: _showArchivedCustomers,
        );
        if (mounted) setState(() => _organizationCustomers = customers);
      }
    } catch (error) {
      if (mounted) {
        xpDlg(
          context,
          'Заказчик не восстановлен',
          _customerError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _resendCustomerInvitation(
    OrganizationCustomer customer,
    OrganizationCustomerRepresentative representative,
  ) async {
    final organizationId = widget.organizationAccess.organizationId;
    if (organizationId == null || !representative.pending) return;
    setState(() => _customerBusy = true);
    try {
      await _organizationService.inviteMember(
        organizationId: organizationId,
        email: representative.email,
        nickname: representative.nickname,
        displayName: representative.displayName,
        role: OrganizationRole.customer,
        functions: const {},
        customerId: customer.id,
      );
      final customers = await _customerService.listCustomers(
        organizationId,
        includeArchived: _showArchivedCustomers,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _organizationParticipants = participants;
      });
      xpDlg(
        context,
        'Приглашение отправлено',
        'Письмо для ${representative.nickname} отправлено повторно.',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отправлено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _cancelCustomerInvitation(
    OrganizationCustomerRepresentative representative,
  ) async {
    final invitationId = representative.invitationId;
    final organizationId = widget.organizationAccess.organizationId;
    if (invitationId == null || organizationId == null) return;
    setState(() => _customerBusy = true);
    try {
      await _organizationService.cancelInvitation(invitationId);
      final customers = await _customerService.listCustomers(
        organizationId,
        includeArchived: _showArchivedCustomers,
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationCustomers = customers;
        _organizationParticipants = participants;
      });
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отменено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  Future<void> _openCustomerJobs(OrganizationCustomer customer) async {
    setState(() => _customerBusy = true);
    try {
      final jobs = await _customerService.listCustomerJobs(customer.id);
      if (!mounted) return;
      if (jobs.isEmpty) {
        xpDlg(
          context,
          'Работы: ${customer.name}',
          'Работы заказчика пока отсутствуют.',
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Работы: ${customer.name}'),
          content: SizedBox(
            width: 560,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final job = jobs[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(job.number),
                  subtitle: Text(
                    '${_customerJobStatusLabel(job.status)} · '
                    '${_shortDate(job.updatedAt)}',
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Работы недоступны', _customerError(error));
      }
    } finally {
      if (mounted) setState(() => _customerBusy = false);
    }
  }

  String _customerJobStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'завершена';
      case 'archived':
        return 'в архиве';
      default:
        return 'активна';
    }
  }

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year}';
  }

  Future<void> _inviteOrganizationMember() async {
    final organizationId = widget.organizationAccess.organizationId;
    final email = _memberEmailCtrl.text.trim().toLowerCase();
    final nickname = _memberNicknameCtrl.text.trim().toLowerCase();
    final displayName = _memberDisplayNameCtrl.text.trim();
    final invitationRole = _selectedMemberRole;
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
        role: invitationRole,
        functions: invitationRole == OrganizationRole.employee
            ? _selectedMemberFunctions
            : const {},
      );
      final participants =
          await _organizationService.listParticipants(organizationId);
      if (!mounted) return;
      setState(() {
        _organizationParticipants = participants;
        _clearMemberDraftWithoutNotify();
      });
      xpDlg(
        context,
        'Приглашение отправлено',
        '${result.email}\nНик: ${result.nickname}\nРоль: ${invitationRole.label}',
      );
    } catch (error) {
      if (mounted) {
        xpDlg(context, 'Приглашение не отправлено', _accessError(error));
      }
    } finally {
      if (mounted) setState(() => _organizationBusy = false);
    }
  }

  void _clearMemberDraftWithoutNotify() {
    _memberEmailCtrl.clear();
    _memberNicknameCtrl.clear();
    _memberDisplayNameCtrl.clear();
    _selectedMemberRole = OrganizationRole.employee;
    _selectedMemberFunctions = {
      OrganizationMemberFunction.inspectionSpecialist,
    };
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
          return 'Достигнут лимит внутренних участников текущего плана.';
        case 'customer_seat_limit':
          return 'Достигнут лимит представителей заказчиков текущего плана.';
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

  String _accessSourceLabel() {
    if (widget.entitlements.legacyFallback) {
      return 'переходный доступ';
    }
    return 'серверные права Supabase';
  }

  String _accessStatusLabel() {
    if (widget.entitlements.legacyFallback) return 'переходный';
    final validUntil = widget.entitlements.validUntil;
    final date = validUntil == null ? null : _shortDate(validUntil);
    if (widget.entitlements.subscriptionExpired) {
      return 'истёк ${date ?? ''}'.trim();
    }
    switch (widget.entitlements.subscriptionStatus) {
      case 'trialing':
        return date == null ? 'пробный период' : 'пробный период до $date';
      case 'grace':
        return date == null ? 'льготный период' : 'льготный период до $date';
      case 'paused':
        return 'приостановлен';
      case 'cancelled':
        return 'отменён';
      case 'active':
      case '':
        return date == null ? 'активен' : 'активен до $date';
      default:
        return 'неактивен';
    }
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
    final cloudAllowed =
        widget.entitlements.allows(ProductCapability.cloudAssets);
    final cloudConnected =
        _cloudConnection.state == CloudConnectionState.connected;
    final appCloudSelected = _storageSettings.primaryLocation ==
        AssetStorageLocation.supabaseStorage;
    final cloudStatus = switch (_cloudConnection.state) {
      CloudConnectionState.connected =>
        'Подключено: ${_cloudConnection.accountLabel ?? 'текущий пользователь'}',
      CloudConnectionState.error =>
        'Не подключено. Требуется миграция хранилища.',
      CloudConnectionState.disconnected => 'Подключение ещё не проверено.',
    };
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
            subtitle: cloudAllowed
                ? '$cloudStatus Оригиналы автоматически не загружаются.'
                : 'Supabase Storage доступен в плане Pro или Enterprise.',
            available: cloudAllowed && cloudConnected,
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
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: XpBtn(
              key: const ValueKey('check-supabase-storage'),
              label: _cloudConnectionChecking
                  ? 'Проверяем подключение...'
                  : 'Проверить Supabase Storage',
              icon: Icons.cloud_done_outlined,
              primary: cloudConnected,
              onPressed: cloudAllowed &&
                      widget.cloudStorage != null &&
                      !_cloudConnectionChecking
                  ? _checkCloudConnection
                  : null,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      _settingsPanel(
        title: 'Политика данных',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _infoRow('Оригиналы', 'не загружаются; остаются у владельца'),
          _infoRow(
            'Протокол',
            appCloudSelected
                ? 'локально + приватная копия в Supabase'
                : 'последняя проверка хранится локально',
          ),
          _infoRow(
            'Превью и карты',
            appCloudSelected
                ? 'карта отличий до 1280 px в Supabase'
                : 'облачная отправка выключена',
          ),
          _infoRow('Права доступа', 'план + роль + доступ к работе'),
          _infoRow('Google OAuth', 'не подключён'),
          _infoRow(
            'Supabase Storage',
            cloudConnected ? 'приватное хранилище доступно' : 'не подключён',
          ),
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
                  final cloudSelected =
                      location == AssetStorageLocation.supabaseStorage;
                  _storageSettings = _storageSettings.copyWith(
                    primaryLocation: location,
                    syncProtocolMetadata: cloudSelected,
                    syncPreviews: cloudSelected,
                    syncOriginals: false,
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
    final cloudSelected = _storageSettings.primaryLocation ==
        AssetStorageLocation.supabaseStorage;
    xpDlg(
      context,
      'Сохранено',
      cloudSelected
          ? 'Протоколы и уменьшенные превью будут сохраняться в Supabase. Оригиналы остаются на устройстве.'
          : 'Настройки применены локально. Изображения и протоколы остаются на устройстве.',
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
