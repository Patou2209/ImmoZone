class SubscriptionModel {
  final String id;
  final String userId;
  final String orderId;
  final String type; // 'mensuelle' | 'annuelle' | 'pack_3' | 'pack_5' | 'pack_10' | 'pack_50'
  final int creditsGranted;
  final double amountPaid;
  final double discount;    // % remise appliquée
  final DateTime startDate;
  final DateTime endDate;
  final String status; // 'active' | 'expired' | 'cancelled'

  SubscriptionModel({
    required this.id,
    required this.userId,
    required this.orderId,
    required this.type,
    required this.creditsGranted,
    required this.amountPaid,
    this.discount = 0,
    required this.startDate,
    required this.endDate,
    this.status = 'active',
  });

  bool get isActive => status == 'active' && endDate.isAfter(DateTime.now());

  String get typeLabel {
    switch (type) {
      case 'mensuelle': return 'Souscription Mensuelle';
      case 'annuelle': return 'Souscription Annuelle';
      case 'pack_3': return 'Pack 3 souscriptions';
      case 'pack_5': return 'Pack 5 souscriptions';
      case 'pack_10': return 'Pack 10 souscriptions';
      case 'pack_50': return 'Pack 50 souscriptions';
      default: return type;
    }
  }

  SubscriptionModel copyWith({
    String? id, String? userId, String? orderId, String? type,
    int? creditsGranted, double? amountPaid, double? discount,
    DateTime? startDate, DateTime? endDate, String? status,
  }) => SubscriptionModel(
    id: id ?? this.id, userId: userId ?? this.userId,
    orderId: orderId ?? this.orderId, type: type ?? this.type,
    creditsGranted: creditsGranted ?? this.creditsGranted,
    amountPaid: amountPaid ?? this.amountPaid,
    discount: discount ?? this.discount,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    status: status ?? this.status,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'orderId': orderId, 'type': type,
    'creditsGranted': creditsGranted, 'amountPaid': amountPaid,
    'discount': discount, 'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(), 'status': status,
  };

  factory SubscriptionModel.fromMap(Map<String, dynamic> m) => SubscriptionModel(
    id: m['id'] ?? '', userId: m['userId'] ?? '',
    orderId: m['orderId'] ?? '', type: m['type'] ?? 'mensuelle',
    creditsGranted: m['creditsGranted'] ?? 1,
    amountPaid: (m['amountPaid'] ?? 0).toDouble(),
    discount: (m['discount'] ?? 0).toDouble(),
    startDate: DateTime.tryParse(m['startDate'] ?? '') ?? DateTime.now(),
    endDate: DateTime.tryParse(m['endDate'] ?? '') ?? DateTime.now().add(const Duration(days: 30)),
    status: m['status'] ?? 'active',
  );
}
