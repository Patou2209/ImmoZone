class AuditLogModel {
  final String id;
  final String action; // 'property_published' | 'property_suspended' | 'property_deleted' | 'payment_confirmed' | etc.
  final String entityType; // 'property' | 'user' | 'payment' | 'subscription' | 'system'
  final String entityId;
  final String? actorId;   // qui a fait l'action (userId ou 'system')
  final String? actorName;
  final String description;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  AuditLogModel({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.actorId,
    this.actorName,
    required this.description,
    this.details,
    required this.createdAt,
  });

  String get actionLabel {
    const labels = {
      'property_published': '📢 Annonce publiée',
      'property_suspended': '⏸️ Annonce suspendue',
      'property_deleted': '🗑️ Annonce supprimée',
      'property_marked_sold': '✅ Annonce marquée vendue',
      'property_boosted': '🚀 Annonce boostée',
      'payment_confirmed': '💳 Paiement confirmé',
      'payment_manual_validated': '✔️ Paiement validé manuellement',
      'payment_failed': '❌ Paiement échoué',
      'credit_granted': '🎁 Crédit accordé',
      'quota_reset': '🔄 Quota réinitialisé',
      'user_suspended': '🚫 Utilisateur suspendu',
      'user_activated': '✅ Utilisateur activé',
      'free_trial_enabled': '🆓 Mode Free Trial activé',
      'free_trial_disabled': '🔒 Mode Free Trial désactivé',
      'settings_updated': '⚙️ Paramètres mis à jour',
      'report_treated': '📋 Signalement traité',
      'sold_properties_cleared': '🧹 Annonces vendues effacées',
    };
    return labels[action] ?? action;
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'action': action, 'entityType': entityType, 'entityId': entityId,
    'actorId': actorId, 'actorName': actorName, 'description': description,
    'details': details, 'createdAt': createdAt.toIso8601String(),
  };

  factory AuditLogModel.fromMap(Map<String, dynamic> m) => AuditLogModel(
    id: m['id'] ?? '', action: m['action'] ?? '',
    entityType: m['entityType'] ?? '', entityId: m['entityId'] ?? '',
    actorId: m['actorId'], actorName: m['actorName'],
    description: m['description'] ?? '',
    details: m['details'] != null ? Map<String, dynamic>.from(m['details']) : null,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
  );
}
