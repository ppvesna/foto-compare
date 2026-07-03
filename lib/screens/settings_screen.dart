import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';
import '../services/check_history_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _quality = 92;
  bool _aiEnabled = false;
  bool _history = true;
  bool _sync = false;
  bool _darkTheme = false;
  bool _notify = true;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '⚙️', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
              label: 'Сохранить',
              icon: '💾',
              shortcut: 'Ctrl+S',
              onTap: () => xpDlg(context, 'Сохранено', 'Настройки применены')),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'Сбросить до заводских',
              icon: '🔄',
              onTap: () async {
                final ok = await xpConfirm(context, 'Сбросить?',
                    'Сбросить все настройки до заводских?');
                if (ok && mounted) {
                  setState(() {
                    _quality = 92;
                    _aiEnabled = false;
                    _history = true;
                    _sync = false;
                    _darkTheme = false;
                    _notify = true;
                  });
                  xpDlg(context, 'Готово', 'Настройки сброшены');
                }
              }),
          XpMenuItem(
              label: 'Очистить кэш',
              icon: '🗑️',
              onTap: () => xpDlg(context, 'Кэш очищен', 'Освобождено: 48 МБ')),
        ]),
        XpMenu(label: 'Правка', items: [
          XpMenuItem(
              label: 'Экспорт настроек',
              icon: '📤',
              onTap: () => xpDlg(
                  context, 'Экспорт', 'Настройки сохранены в config.json')),
          XpMenuItem(
              label: 'Импорт настроек',
              icon: '📂',
              onTap: () =>
                  xpDlg(context, 'Импорт', 'Выберите файл config.json')),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(
              label: 'Версия',
              icon: '📋',
              onTap: () => xpDlg(context, 'Версия',
                  'Photo Compare v1.0.0\nFlutter + SQLite + PostgreSQL\n© 2026 Photo Compare')),
          XpMenuItem(
              label: 'Поддержка',
              icon: '💬',
              onTap: () =>
                  xpDlg(context, 'Поддержка', 'support@photocompare.app')),
        ]),
      ]),
      Expanded(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Аккаунт
          XpGroup(
              label: 'Аккаунт',
              child: Column(children: [
                Row(children: [
                  const Text('👤', style: TextStyle(fontSize: 36)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          Supabase.instance.client.auth.currentUser?.email ??
                              '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      const Text('Бесплатный план',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  )),
                  XpBtn(label: '⭐ Premium', primary: true, onPressed: () {}),
                ]),
                const Divider(),
                Row(children: [
                  Expanded(
                      child: XpBtn(
                          label: '🔑 Пароль',
                          onPressed: () => xpDlg(context, 'Пароль',
                              'Введите текущий и новый пароль'))),
                  const SizedBox(width: 4),
                  Expanded(
                      child: XpBtn(
                          label: '🔄 Синхр.',
                          onPressed: () => xpDlg(context, 'Синхронизация',
                              'Последняя синхронизация: только что'))),
                  const SizedBox(width: 4),
                  Expanded(
                      child: XpBtn(
                          label: '🚪 Выйти',
                          danger: true,
                          onPressed: () async {
                            final ok = await xpConfirm(context, 'Выйти?',
                                'Вы будете отключены от аккаунта.');
                            if (ok) {
                              await Supabase.instance.client.auth.signOut();
                            }
                          })),
                ]),
              ])),

          // Обработка
          XpGroup(
              label: 'Обработка изображений',
              child: Column(children: [
                Row(children: [
                  const SizedBox(
                      width: 130,
                      child: Text('Качество JPEG:',
                          style: TextStyle(fontSize: 11))),
                  Expanded(
                      child: Slider(
                    value: _quality,
                    min: 50,
                    max: 100,
                    activeColor: AppTheme.blue,
                    onChanged: (v) => setState(() => _quality = v),
                  )),
                  Text('${_quality.round()}%',
                      style: const TextStyle(fontSize: 11)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(
                      width: 130,
                      child: Text('Итераций:', style: TextStyle(fontSize: 11))),
                  SizedBox(width: 60, child: XpInput(placeholder: '3')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(
                      width: 130,
                      child: Text('Макс. размер (px):',
                          style: TextStyle(fontSize: 11))),
                  SizedBox(width: 80, child: XpInput(placeholder: '2048')),
                ]),
              ])),

          // Функции
          XpGroup(
              label: 'Функции',
              child: Column(children: [
                _sw('AI анализ (требует Pro)', _aiEnabled,
                    (v) => setState(() => _aiEnabled = v)),
                _sw('Сохранять историю', _history,
                    (v) => setState(() => _history = v)),
                _sw('Синхронизация с сервером', _sync,
                    (v) => setState(() => _sync = v)),
                _sw('Тёмная тема', _darkTheme,
                    (v) => setState(() => _darkTheme = v)),
                _sw('Уведомления мессенджера', _notify,
                    (v) => setState(() => _notify = v)),
              ])),

          _lastCheckHistoryGroup(),

          // Язык
          XpGroup(
              label: 'Язык',
              child: Row(children: [
                XpBtn(label: '🇷🇺 Русский ✓', onPressed: () {}),
                const SizedBox(width: 6),
                XpBtn(label: '🇬🇧 English', onPressed: () {}),
                const SizedBox(width: 6),
                XpBtn(label: '🇨🇳 中文', onPressed: () {}),
              ])),

          const SizedBox(height: 12),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            XpBtn(label: 'Отмена', onPressed: () {}),
            const SizedBox(width: 6),
            XpBtn(
                label: 'Сохранить',
                primary: true,
                onPressed: () =>
                    xpDlg(context, 'Сохранено', 'Настройки применены')),
          ]),
        ]),
      )),
      XpStatusBar(left: 'Версия 1.0.0', right: '🔄 Синхронизировано'),
    ]);
  }

  Widget _sw(String label, bool val, ValueChanged<bool> onChange) {
    return Row(children: [
      Switch(
          value: val,
          onChanged: onChange,
          activeColor: AppTheme.blue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }

  Widget _lastCheckHistoryGroup() {
    return ValueListenableBuilder<CheckProtocol?>(
      valueListenable: CheckHistoryService.lastCheck,
      builder: (context, protocol, _) {
        return XpGroup(
          label: 'История проверок',
          child: protocol == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Последней проверки пока нет. Выполните сравнение, и здесь появится таблица этапов.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _protocolSummary(protocol),
                    const SizedBox(height: 10),
                    _protocolStageTable(protocol),
                    const SizedBox(height: 8),
                    Row(
                      children: [
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
                      ],
                    ),
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
          _summaryText('Размер', '${p.refSize} → ${p.cmpSize}'),
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
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _protocolStageTable(CheckProtocol p) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppTheme.silver,
            child: Row(
              children: [
                _tableCell('Этап', flex: 3, bold: true),
                _tableCell('Статус', flex: 2, bold: true),
                _tableCell('Метрика', flex: 3, bold: true),
                _tableCell('Комментарий', flex: 5, bold: true),
              ],
            ),
          ),
          ...p.stages.asMap().entries.map((entry) {
            final i = entry.key;
            final stage = entry.value;
            return Container(
              color: i.isEven ? Colors.white : const Color(0xFFF5F3EE),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tableCell(stage.name, flex: 3),
                  _tableCell(stage.status, flex: 2),
                  _tableCell(stage.metric, flex: 3),
                  _tableCell(stage.comment, flex: 5),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _tableCell(String text, {int flex = 1, bool bold = false}) {
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
}
