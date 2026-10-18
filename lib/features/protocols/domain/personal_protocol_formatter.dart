import 'check_protocol.dart';

class PersonalProtocolFormatter {
  const PersonalProtocolFormatter._();

  static String format(CheckProtocol protocol) {
    final local = protocol.createdAt.toLocal();
    final date = '${_two(local.day)}.${_two(local.month)}.${local.year}';
    final time = '${_two(local.hour)}:${_two(local.minute)}';
    final score = protocol.score.toStringAsFixed(1).replaceAll('.', ',');
    final lines = <String>[
      'TRIMATRIX · КРАТКИЙ ПРОТОКОЛ',
      '$date · $time',
      '',
      'Эталон: ${protocol.referenceLabel}',
      'Образец: ${protocol.sampleLabel}',
      'Сходство: $score%',
      'Статус: ${protocol.verdict}',
    ];

    for (final stage in protocol.stages.where(_includeStage)) {
      final metric = stage.metric.trim();
      if (metric.isEmpty || metric == '-') continue;
      lines.add('${_shortStageName(stage.name)}: $metric');
    }

    lines.addAll(const [
      '',
      'Краткая версия для пересылки.',
      'Оценка по изображению не заменяет приборное измерение.',
    ]);
    return lines.join('\n');
  }

  static bool _includeStage(CheckProtocolStage stage) {
    final name = stage.name.toLowerCase();
    return name.startsWith('цветовая карта') ||
        name == 'геометрия чб' ||
        name == 'штрихкоды / qr' ||
        name == 'текст / ocr';
  }

  static String _shortStageName(String name) {
    final normalized = name.toLowerCase();
    if (normalized.startsWith('цветовая карта')) return 'Цвет';
    if (normalized == 'геометрия чб') return 'Геометрия';
    if (normalized == 'штрихкоды / qr') return 'Коды';
    if (normalized == 'текст / ocr') return 'Текст';
    return name;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
