class QuotaModel {
  final String id;
  final String userId;
  final int year;
  final int month;
  final int freeQuota;       // quota mensuel gratuit (3 par defaut)
  final int usedFreeQuota;   // 0 ou 1
  final DateTime resetDate;

  QuotaModel({
    required this.id,
    required this.userId,
    required this.year,
    required this.month,
    this.freeQuota = 3,
    this.usedFreeQuota = 0,
    required this.resetDate,
  });

  bool get hasFreeQuotaAvailable => usedFreeQuota < freeQuota;

  QuotaModel copyWith({
    String? id, String? userId, int? year, int? month,
    int? freeQuota, int? usedFreeQuota, DateTime? resetDate,
  }) => QuotaModel(
    id: id ?? this.id, userId: userId ?? this.userId,
    year: year ?? this.year, month: month ?? this.month,
    freeQuota: freeQuota ?? this.freeQuota,
    usedFreeQuota: usedFreeQuota ?? this.usedFreeQuota,
    resetDate: resetDate ?? this.resetDate,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'year': year, 'month': month,
    'freeQuota': freeQuota, 'usedFreeQuota': usedFreeQuota,
    'resetDate': resetDate.toIso8601String(),
  };

  factory QuotaModel.fromMap(Map<String, dynamic> m) => QuotaModel(
    id: m['id'] ?? '', userId: m['userId'] ?? '',
    year: m['year'] ?? DateTime.now().year,
    month: m['month'] ?? DateTime.now().month,
    freeQuota: m['freeQuota'] ?? 3,
    usedFreeQuota: m['usedFreeQuota'] ?? 0,
    resetDate: DateTime.tryParse(m['resetDate'] ?? '') ?? DateTime.now(),
  );
}
