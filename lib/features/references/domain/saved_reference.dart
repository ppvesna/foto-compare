import 'dart:convert';
import 'dart:typed_data';

import 'layout_profile.dart';

class SavedReferenceProfile {
  final String id;
  final String label;
  final Uint8List bytes;
  final LayoutProfile? layoutProfile;
  final DateTime createdAt;

  const SavedReferenceProfile({
    required this.id,
    required this.label,
    required this.bytes,
    required this.layoutProfile,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'bytes': base64Encode(bytes),
        'layoutProfile': layoutProfile?.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedReferenceProfile.fromJson(Map<String, dynamic> json) {
    return SavedReferenceProfile(
      id: json['id'] as String,
      label: json['label'] as String? ?? 'Эталон',
      bytes: base64Decode(json['bytes'] as String),
      layoutProfile: json['layoutProfile'] == null
          ? null
          : LayoutProfile.fromJson(
              Map<String, dynamic>.from(json['layoutProfile'] as Map),
            ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
