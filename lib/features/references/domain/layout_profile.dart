/// Якорная точка — нормализованные координаты (0..1)
class AnchorPoint {
  final String id;
  final double x;
  final double y;
  final String type;       // "corner" | "cross" | "custom"
  final double confidence; // 0..1

  const AnchorPoint({
    required this.id,
    required this.x,
    required this.y,
    this.type = 'corner',
    this.confidence = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    'type': type,
    'confidence': confidence,
  };

  factory AnchorPoint.fromJson(Map<String, dynamic> j) => AnchorPoint(
    id: j['id'] as String? ?? '',
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    type: j['type'] as String? ?? 'corner',
    confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
  );

  AnchorPoint copyWith({String? id, double? x, double? y, String? type, double? confidence}) =>
      AnchorPoint(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        type: type ?? this.type,
        confidence: confidence ?? this.confidence,
      );
}

/// Результаты выравнивания, сохранённые в профиле
class AlignmentInfo {
  final double reprojectionError; // px
  final double eccScore;          // 0..1
  final double confidence;        // 0..1

  const AlignmentInfo({
    required this.reprojectionError,
    required this.eccScore,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'reprojectionError': reprojectionError,
    'eccScore': eccScore,
    'confidence': confidence,
  };

  factory AlignmentInfo.fromJson(Map<String, dynamic> j) => AlignmentInfo(
    reprojectionError: (j['reprojectionError'] as num).toDouble(),
    eccScore: (j['eccScore'] as num?)?.toDouble() ?? 0.0,
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
  );
}

class LayoutProfile {
  final String id;
  final String name;
  final List<AnchorPoint> refAnchors; // нормализованные 0..1
  final List<double> homography;      // 3×3 row-major, 9 значений
  final CropRegion? cropRegion;       // нормализованная 0..1
  final double widthMm;
  final double heightMm;
  final int refImageWidth;
  final int refImageHeight;
  final AlignmentInfo? alignment;
  final DateTime createdAt;

  const LayoutProfile({
    required this.id,
    required this.name,
    required this.refAnchors,
    required this.homography,
    this.cropRegion,
    required this.widthMm,
    required this.heightMm,
    this.refImageWidth = 0,
    this.refImageHeight = 0,
    this.alignment,
    required this.createdAt,
  });

  // Обратная совместимость: reprojError из старого формата
  double get reprojError => alignment?.reprojectionError ?? 0.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'referenceImage': {'width': refImageWidth, 'height': refImageHeight},
    'refAnchors': refAnchors.map((a) => a.toJson()).toList(),
    'homography': homography,
    'cropRegion': cropRegion?.toJson(),
    'printSize': {'widthMm': widthMm, 'heightMm': heightMm},
    'alignment': alignment?.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory LayoutProfile.fromJson(Map<String, dynamic> j) {
    final anchorsRaw = j['refAnchors'] as List;
    final cropRaw = j['cropRegion'] as Map?;
    final printSize = j['printSize'] as Map?;
    final refImg = j['referenceImage'] as Map?;
    final alignRaw = j['alignment'] as Map?;

    // Обратная совместимость со старым форматом (Offset x/y без id)
    List<AnchorPoint> anchors;
    if (anchorsRaw.isNotEmpty && (anchorsRaw.first as Map).containsKey('id')) {
      anchors = anchorsRaw
          .map((e) => AnchorPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      anchors = anchorsRaw.asMap().entries.map((e) => AnchorPoint(
        id: 'pt_${e.key}',
        x: (e.value['x'] as num).toDouble(),
        y: (e.value['y'] as num).toDouble(),
      )).toList();
    }

    // cropRegion: поддерживаем оба формата (старый: left/top/right/bottom; новый: x/y/w/h)
    CropRegion? crop;
    if (cropRaw != null) {
      if (cropRaw.containsKey('x')) {
        crop = CropRegion.fromJson(Map<String, dynamic>.from(cropRaw));
      } else {
        final l = (cropRaw['left'] as num).toDouble();
        final t = (cropRaw['top'] as num).toDouble();
        final r = (cropRaw['right'] as num).toDouble();
        final b = (cropRaw['bottom'] as num).toDouble();
        crop = CropRegion(x: l, y: t, w: r - l, h: b - t);
      }
    }

    // alignment: поддерживаем старый ключ reprojError
    AlignmentInfo? align;
    if (alignRaw != null) {
      align = AlignmentInfo.fromJson(Map<String, dynamic>.from(alignRaw));
    } else if (j.containsKey('reprojError')) {
      align = AlignmentInfo(
        reprojectionError: (j['reprojError'] as num).toDouble(),
        eccScore: 0.0,
        confidence: 0.0,
      );
    }

    return LayoutProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      refAnchors: anchors,
      homography: (j['homography'] as List).map((e) => (e as num).toDouble()).toList(),
      cropRegion: crop,
      widthMm: (printSize?['widthMm'] as num?)?.toDouble() ?? (j['widthMm'] as num?)?.toDouble() ?? 100.0,
      heightMm: (printSize?['heightMm'] as num?)?.toDouble() ?? (j['heightMm'] as num?)?.toDouble() ?? 100.0,
      refImageWidth: (refImg?['width'] as num?)?.toInt() ?? 0,
      refImageHeight: (refImg?['height'] as num?)?.toInt() ?? 0,
      alignment: align,
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  LayoutProfile copyWith({
    String? id,
    String? name,
    List<AnchorPoint>? refAnchors,
    List<double>? homography,
    CropRegion? cropRegion,
    double? widthMm,
    double? heightMm,
    int? refImageWidth,
    int? refImageHeight,
    AlignmentInfo? alignment,
    DateTime? createdAt,
  }) => LayoutProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    refAnchors: refAnchors ?? this.refAnchors,
    homography: homography ?? this.homography,
    cropRegion: cropRegion ?? this.cropRegion,
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    refImageWidth: refImageWidth ?? this.refImageWidth,
    refImageHeight: refImageHeight ?? this.refImageHeight,
    alignment: alignment ?? this.alignment,
    createdAt: createdAt ?? this.createdAt,
  );
}

/// Область кропа — нормализованная (0..1), формат x/y/w/h
class CropRegion {
  final double x;
  final double y;
  final double w;
  final double h;

  const CropRegion({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  static const CropRegion defaultCrop = CropRegion(x: 0.05, y: 0.05, w: 0.90, h: 0.90);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  factory CropRegion.fromJson(Map<String, dynamic> j) => CropRegion(
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    w: (j['w'] as num).toDouble(),
    h: (j['h'] as num).toDouble(),
  );
}
