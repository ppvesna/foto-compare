class CheckProtocol {
  final String id;
  final DateTime createdAt;
  final String jobId;
  final String jobNumber;
  final String customerId;
  final String customerName;
  final bool customerConfirmed;
  final double score;
  final String verdict;
  final String refSize;
  final String cmpSize;
  final String labId;
  final String referenceId;
  final String referenceLabel;
  final String sampleLabel;
  final String sampleImageId;
  final int sampleNo;
  final double? labMatch;
  final String deltaEFormula;
  final String captureLighting;
  final String captureFilter;
  final double apertureMm;
  final List<CheckProtocolStage> stages;

  const CheckProtocol({
    required this.id,
    required this.createdAt,
    this.jobId = '',
    this.jobNumber = '',
    this.customerId = '',
    this.customerName = '',
    this.customerConfirmed = false,
    required this.score,
    required this.verdict,
    required this.refSize,
    required this.cmpSize,
    required this.labId,
    this.referenceId = '',
    this.referenceLabel = 'Эталон',
    this.sampleLabel = 'Образец',
    this.sampleImageId = '',
    this.sampleNo = 1,
    required this.labMatch,
    this.deltaEFormula = 'ΔE*76',
    this.captureLighting = 'D65',
    this.captureFilter = 'Без фильтра',
    this.apertureMm = 2,
    required this.stages,
  });

  factory CheckProtocol.fromJson(Map<String, dynamic> json) => CheckProtocol(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        jobId: json['jobId'] as String? ?? '',
        jobNumber: json['jobNumber'] as String? ?? '',
        customerId: json['customerId'] as String? ?? '',
        customerName: json['customerName'] as String? ?? '',
        customerConfirmed: json['customerConfirmed'] as bool? ?? false,
        score: (json['score'] as num).toDouble(),
        verdict: json['verdict'] as String,
        refSize: json['refSize'] as String,
        cmpSize: json['cmpSize'] as String,
        labId: json['labId'] as String? ?? '-',
        referenceId: json['referenceId'] as String? ?? '',
        referenceLabel: json['referenceLabel'] as String? ?? 'Эталон',
        sampleLabel: json['sampleLabel'] as String? ?? 'Образец',
        sampleImageId: json['sampleImageId'] as String? ?? '',
        sampleNo: (json['sampleNo'] as num?)?.toInt() ?? 1,
        labMatch: (json['labMatch'] as num?)?.toDouble(),
        deltaEFormula: json['deltaEFormula'] as String? ?? 'ΔE*76',
        captureLighting: json['captureLighting'] as String? ??
            json['illuminant'] as String? ??
            'D65',
        captureFilter: json['captureFilter'] as String? ??
            json['measurementCondition'] as String? ??
            'Без фильтра',
        apertureMm: (json['apertureMm'] as num?)?.toDouble() ?? 2,
        stages: (json['stages'] as List)
            .map((e) => CheckProtocolStage.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'jobId': jobId,
        'jobNumber': jobNumber,
        'customerId': customerId,
        'customerName': customerName,
        'customerConfirmed': customerConfirmed,
        'score': score,
        'verdict': verdict,
        'refSize': refSize,
        'cmpSize': cmpSize,
        'labId': labId,
        'referenceId': referenceId,
        'referenceLabel': referenceLabel,
        'sampleLabel': sampleLabel,
        'sampleImageId': sampleImageId,
        'sampleNo': sampleNo,
        'labMatch': labMatch,
        'deltaEFormula': deltaEFormula,
        'captureLighting': captureLighting,
        'captureFilter': captureFilter,
        'apertureMm': apertureMm,
        'stages': stages.map((e) => e.toJson()).toList(),
      };
}

class CheckProtocolStage {
  final String name;
  final String status;
  final String metric;
  final String comment;

  const CheckProtocolStage({
    required this.name,
    required this.status,
    required this.metric,
    required this.comment,
  });

  factory CheckProtocolStage.fromJson(Map<String, dynamic> json) =>
      CheckProtocolStage(
        name: json['name'] as String,
        status: json['status'] as String,
        metric: json['metric'] as String,
        comment: json['comment'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'metric': metric,
        'comment': comment,
      };
}
