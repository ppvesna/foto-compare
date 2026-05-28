import 'dart:ui';

class LayoutProfile {
  final String id;
  final String name;
  final List<Offset> refAnchors;   // anchor points in ref image (normalized 0..1)
  final List<double> homography;   // 3×3 row-major, 9 values
  final Rect? cropRegion;          // normalized 0..1, null = no crop
  final double widthMm;
  final double heightMm;
  final double reprojError;
  final DateTime createdAt;

  const LayoutProfile({
    required this.id,
    required this.name,
    required this.refAnchors,
    required this.homography,
    this.cropRegion,
    required this.widthMm,
    required this.heightMm,
    required this.reprojError,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'refAnchors': refAnchors.map((o) => {'x': o.dx, 'y': o.dy}).toList(),
    'homography': homography,
    'cropRegion': cropRegion == null ? null : {
      'left': cropRegion!.left,
      'top': cropRegion!.top,
      'right': cropRegion!.right,
      'bottom': cropRegion!.bottom,
    },
    'widthMm': widthMm,
    'heightMm': heightMm,
    'reprojError': reprojError,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LayoutProfile.fromJson(Map<String, dynamic> j) {
    final anchorsRaw = j['refAnchors'] as List;
    final cropRaw = j['cropRegion'] as Map?;
    return LayoutProfile(
      id: j['id'] as String,
      name: j['name'] as String,
      refAnchors: anchorsRaw
          .map((e) => Offset((e['x'] as num).toDouble(), (e['y'] as num).toDouble()))
          .toList(),
      homography: (j['homography'] as List).map((e) => (e as num).toDouble()).toList(),
      cropRegion: cropRaw == null ? null : Rect.fromLTRB(
        (cropRaw['left'] as num).toDouble(),
        (cropRaw['top'] as num).toDouble(),
        (cropRaw['right'] as num).toDouble(),
        (cropRaw['bottom'] as num).toDouble(),
      ),
      widthMm: (j['widthMm'] as num).toDouble(),
      heightMm: (j['heightMm'] as num).toDouble(),
      reprojError: (j['reprojError'] as num).toDouble(),
      createdAt: DateTime.parse(j['createdAt'] as String),
    );
  }

  LayoutProfile copyWith({
    String? id,
    String? name,
    List<Offset>? refAnchors,
    List<double>? homography,
    Rect? cropRegion,
    double? widthMm,
    double? heightMm,
    double? reprojError,
    DateTime? createdAt,
  }) => LayoutProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    refAnchors: refAnchors ?? this.refAnchors,
    homography: homography ?? this.homography,
    cropRegion: cropRegion ?? this.cropRegion,
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    reprojError: reprojError ?? this.reprojError,
    createdAt: createdAt ?? this.createdAt,
  );
}
