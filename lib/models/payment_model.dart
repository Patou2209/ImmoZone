class PaymentModel {
  final String id;
  final String userId;
  final String userName; // nom de l'utilisateur pour affichage admin
  final String orderId;
  final String operator; // 'mpesa' | 'orange_money' | 'airtel_money' | 'manual'
  final String phoneNumber;
  final double amount;
  final String currency; // USD
  final String status; // 'pending' | 'confirmed' | 'failed' | 'cancelled' | 'awaiting_manual'
  final String? transactionReference; // numéro de référence opérateur
  final String? manualNote; // note admin validation manuelle
  final String? validatedBy; // admin ID si validation manuelle
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String productType; // 'publication_unitaire' | 'souscription_mensuelle' | 'souscription_annuelle' | 'pack_3' | 'pack_5' | 'pack_10' | 'pack_50' | 'boost'
  final int creditsQty;     // nombre exact de crédits à attribuer lors de l'approbation
  final String? propertyId; // si boost d'annonce

  PaymentModel({
    required this.id,
    required this.userId,
    this.userName = '',
    required this.orderId,
    required this.operator,
    required this.phoneNumber,
    required this.amount,
    this.currency = 'USD',
    this.status = 'pending',
    this.transactionReference,
    this.manualNote,
    this.validatedBy,
    required this.createdAt,
    this.confirmedAt,
    required this.productType,
    this.creditsQty = 0,
    this.propertyId,
  });

  bool get isPending => status == 'pending' || status == 'awaiting_manual';
  bool get isConfirmed => status == 'confirmed';
  bool get isFailed => status == 'failed' || status == 'cancelled';

  String get operatorLabel {
    switch (operator) {
      case 'mpesa': return 'M-Pesa';
      case 'orange_money': return 'Orange Money';
      case 'airtel_money': return 'Airtel Money';
      case 'manual': return 'Paiement Manuel';
      default: return operator;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending': return 'En attente';
      case 'confirmed': return 'Confirmé';
      case 'failed': return 'Échoué';
      case 'cancelled': return 'Annulé';
      case 'awaiting_manual': return 'Vérif. manuelle';
      default: return status;
    }
  }

  String get productLabel {
    switch (productType) {
      case 'publication_unitaire': return 'Publication unitaire (2 USD)';
      case 'souscription_mensuelle': return 'Souscription mensuelle';
      case 'souscription_annuelle': return 'Souscription annuelle';
      case 'pack_3': return 'Pack 3 souscriptions';
      case 'pack_5': return 'Pack 5 souscriptions';
      case 'pack_10': return 'Pack 10 souscriptions';
      case 'pack_50': return 'Pack 50 souscriptions';
      case 'boost_semaine': return 'Boost annonce (1 semaine)';
      case 'boost_mois': return 'Boost annonce (1 mois)';
      default: return productType;
    }
  }

  PaymentModel copyWith({
    String? id, String? userId, String? userName, String? orderId, String? operator,
    String? phoneNumber, double? amount, String? currency, String? status,
    String? transactionReference, String? manualNote, String? validatedBy,
    DateTime? createdAt, DateTime? confirmedAt, String? productType,
    int? creditsQty, String? propertyId,
  }) => PaymentModel(
    id: id ?? this.id, userId: userId ?? this.userId,
    userName: userName ?? this.userName,
    orderId: orderId ?? this.orderId, operator: operator ?? this.operator,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    amount: amount ?? this.amount, currency: currency ?? this.currency,
    status: status ?? this.status,
    transactionReference: transactionReference ?? this.transactionReference,
    manualNote: manualNote ?? this.manualNote,
    validatedBy: validatedBy ?? this.validatedBy,
    createdAt: createdAt ?? this.createdAt,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    productType: productType ?? this.productType,
    creditsQty: creditsQty ?? this.creditsQty,
    propertyId: propertyId ?? this.propertyId,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'userId': userId, 'userName': userName, 'orderId': orderId, 'operator': operator,
    'phoneNumber': phoneNumber, 'amount': amount, 'currency': currency,
    'status': status, 'transactionReference': transactionReference,
    'manualNote': manualNote, 'validatedBy': validatedBy,
    'createdAt': createdAt.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'productType': productType, 'creditsQty': creditsQty, 'propertyId': propertyId,
  };

  factory PaymentModel.fromMap(Map<String, dynamic> m) => PaymentModel(
    id: m['id'] ?? '', userId: m['userId'] ?? '',
    userName: m['userName'] ?? '',
    orderId: m['orderId'] ?? '', operator: m['operator'] ?? 'mpesa',
    phoneNumber: m['phoneNumber'] ?? '',
    amount: (m['amount'] ?? 0).toDouble(),
    currency: m['currency'] ?? 'USD',
    status: m['status'] ?? 'pending',
    transactionReference: m['transactionReference'],
    manualNote: m['manualNote'],
    validatedBy: m['validatedBy'],
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    confirmedAt: m['confirmedAt'] != null ? DateTime.tryParse(m['confirmedAt']) : null,
    productType: m['productType'] ?? 'publication_unitaire',
    creditsQty: (m['creditsQty'] as num?)?.toInt() ?? 0,
    propertyId: m['propertyId'],
  );
}
