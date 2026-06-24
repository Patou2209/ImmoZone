class ParrainModel {
  final String id;
  final String name;
  final String code;          // code unique ex: "PATOU2025"
  final String createdById;   // uid admin qui a créé
  final DateTime createdAt;
  final bool isActive;

  ParrainModel({
    required this.id,
    required this.name,
    required this.code,
    required this.createdById,
    required this.createdAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'createdById': createdById,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
      };

  factory ParrainModel.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      try { return (v as dynamic).toDate() as DateTime; } catch (_) {}
      try { return DateTime.parse(v.toString()); } catch (_) { return DateTime.now(); }
    }

    return ParrainModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      code: map['code'] ?? '',
      createdById: map['createdById'] ?? '',
      createdAt: parseDate(map['createdAt']),
      isActive: map['isActive'] ?? true,
    );
  }
}
