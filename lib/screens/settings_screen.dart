import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../services/check_history_service.dart';
import '../widgets/xp_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 0;
  double _quality = 96;
  bool _aiEnabled = false;
  bool _history = true;
  bool _sync = false;
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

  static const _sections = [
    _SettingsSection('Аккаунт', 'профиль и синхронизация'),
    _SettingsSection('Камера', 'захват с ноутбука или USB'),
    _SettingsSection('Цвет', 'CMYK точки и Delta E'),
    _SettingsSection('Плотности', 'оптические плотности CMYK'),
    _SettingsSection('Штрихкоды', 'EAN, QR, DataMatrix'),
    _SettingsSection('Проверка', 'уровни анализа'),
    _SettingsSection('Хранение', 'история и облако'),
  ];

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
            onTap: _saveSettings,
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
      XpStatusBar(
        left: 'Настройки производства',
        right: 'камера · CMYK · плотности · штрихкоды',
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
      onTap: () => setState(() => _section = index),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_section == 0) _accountSection(),
        if (_section == 1) _cameraSection(),
        if (_section == 2) _colorSection(),
        if (_section == 3) _densitySection(),
        if (_section == 4) _barcodeSection(),
        if (_section == 5) _inspectionSection(),
        if (_section == 6) _storageSection(),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          XpBtn(label: 'Сбросить', onPressed: _resetSettings),
          const SizedBox(width: 8),
          XpBtn(label: 'Сохранить', primary: true, onPressed: _saveSettings),
        ]),
      ]),
    );
  }

  Widget _accountSection() {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return _settingsPanel(
      title: 'Аккаунт и организация',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _infoRow('Email', email.isEmpty ? 'не указан' : email),
        _infoRow('План', 'Бесплатный, 10 проверок в день'),
        _infoRow('Организация', 'будет использоваться для группового чата'),
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
        'Для Chrome надо будет отдельно подключить выбор устройств через getUserMedia: список камер, проверка доступа, live-preview и контроль света.',
      ),
    ]);
  }

  Widget _colorSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
        title: 'Хранение и синхронизация',
        child: Column(children: [
          _toggleRow(
            'Сохранять историю',
            'последний протокол хранится локально',
            _history,
            (v) => setState(() => _history = v),
          ),
          _toggleRow(
            'Синхронизация с сервером',
            'после Supabase-схемы настройки и протоколы уйдут в облако',
            _sync,
            (v) => setState(() => _sync = v),
          ),
          _toggleRow(
            'Уведомления чата',
            'сообщения группы организации',
            _notify,
            (v) => setState(() => _notify = v),
          ),
          const SizedBox(height: 8),
          _infoRow('Оригиналы картинок', 'локально на устройстве пользователя'),
          _infoRow('В облаке', 'протокол, превью, карты, временные ссылки'),
        ]),
      ),
      const SizedBox(height: 10),
      _lastCheckHistoryGroup(),
    ]);
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
          activeColor: AppTheme.blue,
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

  void _saveSettings() {
    xpDlg(
      context,
      'Сохранено',
      'Каркас настроек применен локально. Следующим этапом подключим модель UserInspectionSettings и запись в базу.',
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
      _sync = false;
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
    });
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
