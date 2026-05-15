class ReportModel {
  final String id;
  final String propertyId;
  final String propertyTitle;
  final String reporterId;
  final String reporterName;
  final String reason; // 'arnaque' | 'fausse_annonce' | 'photo_inappropriee' | 'prix_errone' | 'doublon' | 'autre'
  final String? description;
  final String status; // 'pending' | 'treated' | 'dismissed'
  final String? adminNote;
  final String? handledBy;
  final DateTime createdAt;
  final DateTime? handledAt;

  ReportModel({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.reporterId,
    required this.reporterName,
    required this.reason,
    this.description,
    this.status = 'pending',
    this.adminNote,
    this.handledBy,
    required this.createdAt,
    this.handledAt,
  });

  String get reasonLabel {
    switch (reason) {
      case 'arnaque': return 'Arnaque / Fraude';
      case 'fausse_annonce': return 'Fausse annonce';
      case 'photo_inappropriee': return 'Photo inappropriée';
      case 'prix_errone': return 'Prix erroné';
      case 'doublon': return 'Annonce en doublon';
      case 'autre': return 'Autre motif';
      default: return reason;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending': return 'En attente';
      case 'treated': return 'Traité';
      case 'dismissed': return 'Classé sans suite';
      default: return status;
    }
  }

  ReportModel copyWith({
    String? id, String? propertyId, String? propertyTitle,
    String? reporterId, String? reporterName, String? reason,
    String? description, String? status, String? adminNote,
    String? handledBy, DateTime? createdAt, DateTime? handledAt,
  }) => ReportModel(
    id: id ?? this.id, propertyId: propertyId ?? this.propertyId,
    propertyTitle: propertyTitle ?? this.propertyTitle,
    reporterId: reporterId ?? this.reporterId,
    reporterName: reporterName ?? this.reporterName,
    reason: reason ?? this.reason,
    description: description ?? this.description,
    status: status ?? this.status,
    adminNote: adminNote ?? this.adminNote,
    handledBy: handledBy ?? this.handledBy,
    createdAt: createdAt ?? this.createdAt,
    handledAt: handledAt ?? this.handledAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'propertyId': propertyId, 'propertyTitle': propertyTitle,
    'reporterId': reporterId, 'reporterName': reporterName,
    'reason': reason, 'description': description, 'status': status,
    'adminNote': adminNote, 'handledBy': handledBy,
    'createdAt': createdAt.toIso8601String(),
    'handledAt': handledAt?.toIso8601String(),
  };

  factory ReportModel.fromMap(Map<String, dynamic> m) => ReportModel(
    id: m['id'] ?? '', propertyId: m['propertyId'] ?? '',
    propertyTitle: m['propertyTitle'] ?? '',
    reporterId: m['reporterId'] ?? '', reporterName: m['reporterName'] ?? '',
    reason: m['reason'] ?? 'autre', description: m['description'],
    status: m['status'] ?? 'pending', adminNote: m['adminNote'],
    handledBy: m['handledBy'],
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    handledAt: m['handledAt'] != null ? DateTime.tryParse(m['handledAt']) : null,
  );
}
