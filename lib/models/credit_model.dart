class CreditModel {
  final String id;
  final String userId;
  final String source; // 'quota_gratuit' | 'souscription' | 'pack' | 'admin_manuel'
  final String? orderId;
  final int quantity;
  final int remaining;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isActive;

  CreditModel({
    required this.id,
    required this.userId,
    required this.source,
    this.orderId,
    required this.quantity,
    required this.remaining,
    required this.createdAt,
    this.expiresAt,
    this.isActive = true,
  });

  bool get hasCredits => isActive && remaining > 0 &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  String get sourceLabel {
    switch (source) {
      case 'quota_gratuit': return 'Quota gratuit mensuel';
      case 'souscription': return 'Souscription';
      case 'pack': return 'Pack bulk';
      case 'admin_manuel': return 'Crédit admin';
      case 'promo_admin': return 'Promotion admin';
      case 'parrainage_user': return 'Commission parrainage';
      default: return source;
    }
  }

  CreditModel copyWith({
    String? id, String? userId, String? source, String? orderId,
    int? quantity, int? remaining, DateTime? createdAt,
    DateTime? expiresAt, bool? isActive,
  }) => CreditModel(
    id: id ?? this.id, userId: userId ?? this.userId,
    source: source ?? this.source, orderId: orderId ?? this.orderId,
    quantity: quantity ?? this.quantity, remaining: remaining ?? this.remaining,
    createdAt: createdAt ?? this.createdAt,
    expiresAt: expiresAt ?? this.expiresAt,
    isActive: isActive ?? this.isActive,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'source': source, 'orderId': orderId,
    'quantity': quantity, 'remaining': remaining,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'isActive': isActive,
  };

  factory CreditModel.fromMap(Map<String, dynamic> m) => CreditModel(
    id: m['id'] ?? '', userId: m['userId'] ?? '',
    source: m['source'] ?? 'souscription', orderId: m['orderId'],
    quantity: m['quantity'] ?? 1, remaining: m['remaining'] ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    expiresAt: m['expiresAt'] != null ? DateTime.tryParse(m['expiresAt']) : null,
    isActive: m['isActive'] ?? true,
  );
}
