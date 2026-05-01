import 'package:flutter/material.dart';
import '../config/app_theme.dart';

// ── XP Кнопка ────────────────────────────────────────
class XpBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final IconData? icon;
  final double? width;

  const XpBtn({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = danger
        ? const LinearGradient(colors: [Color(0xFFF56060), Color(0xFFC82020)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter)
        : primary ? AppTheme.blueGrad : AppTheme.btnGrad;

    final textColor = (primary || danger) ? Colors.white : Colors.black;

    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(
          fontSize: 11, color: textColor,
          fontWeight: primary ? FontWeight.bold : FontWeight.normal,
        )),
      ],
    );

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(3),
          border: Border(
            top:    BorderSide(color: (primary||danger) ? AppTheme.blueDark : Colors.white),
            left:   BorderSide(color: (primary||danger) ? AppTheme.blueDark : Colors.white),
            right:  BorderSide(color: (primary||danger) ? AppTheme.blueDark : AppTheme.border),
            bottom: BorderSide(color: (primary||danger) ? AppTheme.blueDark : AppTheme.border),
          ),
        ),
        child: child,
      ),
    );
  }
}

// ── XP Поле ввода ─────────────────────────────────────
class XpInput extends StatelessWidget {
  final String placeholder;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const XpInput({
    super.key,
    required this.placeholder,
    this.obscure = false,
    this.controller,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top:    BorderSide(color: Color(0xFF404040)),
          left:   BorderSide(color: Color(0xFF404040)),
          right:  BorderSide(color: Color(0xFFDFDFDF)),
          bottom: BorderSide(color: Color(0xFFDFDFDF)),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
          contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

// ── XP Группа ────────────────────────────────────────
class XpGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const XpGroup({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.silverDark),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            child: child,
          ),
          Positioned(
            top: -8, left: 8,
            child: Container(
              color: AppTheme.silver,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── XP Диалог ─────────────────────────────────────────
Future<void> xpDlg(BuildContext context, String title, String msg) {
  return showDialog(
    context: context,
    barrierColor: Colors.black45,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.silver,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(gradient: AppTheme.blueGrad),
            child: Row(children: [
              Expanded(child: Text(title,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 12))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text('✕',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(msg,
                style: const TextStyle(fontSize: 11, height: 1.7)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              XpBtn(
                label: 'ОК', primary: true,
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
        ],
      ),
    ),
  );
}

Future<bool> xpConfirm(BuildContext context, String title, String msg) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black45,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.silver,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: const BoxDecoration(gradient: AppTheme.blueGrad),
            child: Row(children: [
              Expanded(child: Text(title,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 12))),
              GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: const Text('✕',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(msg, style: const TextStyle(fontSize: 11, height: 1.7)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              XpBtn(label: 'Отмена',
                  onPressed: () => Navigator.pop(context, false)),
              const SizedBox(width: 6),
              XpBtn(label: 'Да', primary: true,
                  onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

// ── XP Менюбар ───────────────────────────────────────
class XpMenuBar extends StatefulWidget {
  final String icon;
  final List<XpMenu> menus;

  const XpMenuBar({super.key, required this.icon, required this.menus});

  @override
  State<XpMenuBar> createState() => _XpMenuBarState();
}

class _XpMenuBarState extends State<XpMenuBar> {
  int? _open;
  OverlayEntry? _barrier;
  OverlayEntry? _dropdown;
  late final List<LayerLink> _links;

  @override
  void initState() {
    super.initState();
    _links = List.generate(widget.menus.length, (_) => LayerLink());
  }

  void _openMenu(int i) {
    if (_open == i) { _closeMenu(); return; }
    _closeMenu();
    setState(() => _open = i);

    final items = widget.menus[i].items;
    final overlay = Overlay.of(context);

    _barrier = OverlayEntry(
      builder: (_) => GestureDetector(
        onTap: _closeMenu,
        behavior: HitTestBehavior.translucent,
        child: const SizedBox.expand(),
      ),
    );

    _dropdown = OverlayEntry(
      builder: (_) => Positioned(
        width: 210,
        child: CompositedTransformFollower(
          link: _links[i],
          showWhenUnlinked: false,
          offset: const Offset(0, 26),
          child: Material(
            elevation: 8,
            child: Container(
              color: AppTheme.silver,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items.map((item) {
                  if (item.separator) {
                    return const Column(children: [
                      Divider(height: 1, color: Color(0xFFACA899)),
                      Divider(height: 1, color: Colors.white),
                    ]);
                  }
                  return GestureDetector(
                    onTap: item.disabled ? null : () {
                      _closeMenu();
                      item.onTap?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 7, 16, 7),
                      color: Colors.transparent,
                      child: Row(children: [
                        if (item.icon != null) ...[
                          Text(item.icon!, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 6),
                        ],
                        Text(item.label,
                            style: TextStyle(
                                fontSize: 11,
                                color: item.disabled ? Colors.grey : Colors.black)),
                        if (item.shortcut != null) ...[
                          const Spacer(),
                          Text(item.shortcut!,
                              style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_barrier!);
    overlay.insert(_dropdown!);
  }

  void _closeMenu() {
    _barrier?.remove();
    _dropdown?.remove();
    _barrier = null;
    _dropdown = null;
    if (mounted) setState(() => _open = null);
  }

  @override
  void dispose() {
    _barrier?.remove();
    _dropdown?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.silver,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: AppTheme.silverDark)),
                ),
                child: Text(widget.icon, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 4),
              ...widget.menus.asMap().entries.map((e) {
                final i = e.key;
                final menu = e.value;
                return CompositedTransformTarget(
                  link: _links[i],
                  child: GestureDetector(
                    onTap: () => _openMenu(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: _open == i ? AppTheme.blue : Colors.transparent,
                      child: Text(menu.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: _open == i ? Colors.white : Colors.black)),
                    ),
                  ),
                );
              }),
            ],
          ),
          Container(height: 2, color: AppTheme.blue),
        ],
      ),
    );
  }
}

class XpMenu {
  final String label;
  final List<XpMenuItem> items;
  const XpMenu({required this.label, required this.items});
}

class XpMenuItem {
  final String label;
  final String? icon;
  final String? shortcut;
  final bool disabled;
  final bool separator;
  final VoidCallback? onTap;

  const XpMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.disabled = false,
    this.separator = false,
    this.onTap,
  });

  static const XpMenuItem sep = XpMenuItem(label: '', separator: true);
}


// ── Схожесть бейдж ───────────────────────────────────
class SimBadge extends StatelessWidget {
  final double value;
  final double fontSize;

  const SimBadge({super.key, required this.value, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.simColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: fontSize),
      ),
    );
  }
}

// ── Статусбар ────────────────────────────────────────
class XpStatusBar extends StatelessWidget {
  final String left;
  final String? right;

  const XpStatusBar({super.key, required this.left, this.right});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.silver,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(children: [
        Expanded(child: _panel(left)),
        if (right != null) ...[
          const SizedBox(width: 4),
          SizedBox(width: 120, child: _panel(right!)),
        ],
      ]),
    );
  }

  Widget _panel(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: const BoxDecoration(border: Border(
      top:    BorderSide(color: Color(0xFF404040)),
      left:   BorderSide(color: Color(0xFF404040)),
      right:  BorderSide(color: Colors.white),
      bottom: BorderSide(color: Colors.white),
    )),
    child: Text(t, style: const TextStyle(fontSize: 10)),
  );
}
