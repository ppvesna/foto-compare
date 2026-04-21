class ComparisonResult {
  final String   id;
  final String   referencePath;
  final String   comparePath;
  final double   similarity;
  final String?  diffImagePath;
  final String?  aiAnalysis;
  final DateTime createdAt;
  final List<String> iterations;

  const ComparisonResult({
    required this.id,
    required this.referencePath,
    required this.comparePath,
    required this.similarity,
    this.diffImagePath,
    this.aiAnalysis,
    required this.createdAt,
    this.iterations = const [],
  });

  String get similarityLabel {
    if (similarity >= 80) return 'Высокая схожесть';
    if (similarity >= 70) return 'Средняя схожесть';
    return 'Низкая схожесть';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'reference_path': referencePath,
    'compare_path': comparePath,
    'similarity': similarity,
    'diff_path': diffImagePath,
    'ai_analysis': aiAnalysis,
    'created_at': createdAt.toIso8601String(),
    'iterations': iterations.join(','),
    'updated_at': DateTime.now().toIso8601String(),
  };

  factory ComparisonResult.fromMap(Map<String, dynamic> m) => ComparisonResult(
    id: m['id'],
    referencePath: m['reference_path'],
    comparePath: m['compare_path'],
    similarity: (m['similarity'] as num).toDouble(),
    diffImagePath: m['diff_path'],
    aiAnalysis: m['ai_analysis'],
    createdAt: DateTime.parse(m['created_at']),
    iterations: (m['iterations'] as String?)?.split(',').where((s) => s.isNotEmpty).toList() ?? [],
  );
}
