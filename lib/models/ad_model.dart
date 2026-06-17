/// Modèle pour une publicité interne (bannière sponsorisée).
/// Stockée dans la collection Firestore `ads`.
class AdModel {
  final String id;
  final String title;         // Titre affiché sur la carte
  final String subtitle;      // Sous-titre / accroche
  final String imageUrl;      // URL image (réseau ou base64)
  final String linkType;      // 'whatsapp' | 'url' | 'phone'
  final String linkValue;     // numéro WA, URL, ou numéro tél
  final String ctaLabel;      // Texte bouton ex: "Contacter", "En savoir plus"
  final String category;      // 'Banque' | 'Notaire' | 'Agence' | 'Construction' | 'Autre'
  final bool isActive;        // Activée par l'admin
  final DateTime startDate;
  final DateTime endDate;
  final int clicks;           // Compteur de clics
  final int impressions;      // Compteur d'affichages
  final int position;         // Toutes les N annonces (ex: 5 = après chaque 5e annonce)
  final String createdBy;     // UID admin créateur
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AdModel({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.imageUrl,
    required this.linkType,
    required this.linkValue,
    this.ctaLabel = 'En savoir plus',
    this.category = 'Autre',
    this.isActive = false,
    required this.startDate,
    required this.endDate,
    this.clicks = 0,
    this.impressions = 0,
    this.position = 5,
    this.createdBy = '',
    required this.createdAt,
    this.updatedAt,
  });

  /// La pub est-elle actuellement valide (active + dans la période) ?
  bool get isLive {
    final now = DateTime.now();
    return isActive && now.isAfter(startDate) && now.isBefore(endDate);
  }

  int get daysLeft {
    final diff = endDate.difference(DateTime.now()).inDays;
    return diff.clamp(0, 9999);
  }

  double get ctr => impressions == 0 ? 0 : (clicks / impressions) * 100;

  // ── Sérialisation ────────────────────────────────────────────────────────
  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'linkType': linkType,
    'linkValue': linkValue,
    'ctaLabel': ctaLabel,
    'category': category,
    'isActive': isActive,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate.toIso8601String(),
    'clicks': clicks,
    'impressions': impressions,
    'position': position,
    'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory AdModel.fromMap(Map<String, dynamic> m, String docId) => AdModel(
    id: docId,
    title: m['title'] ?? '',
    subtitle: m['subtitle'] ?? '',
    imageUrl: m['imageUrl'] ?? '',
    linkType: m['linkType'] ?? 'url',
    linkValue: m['linkValue'] ?? '',
    ctaLabel: m['ctaLabel'] ?? 'En savoir plus',
    category: m['category'] ?? 'Autre',
    isActive: m['isActive'] ?? false,
    startDate: m['startDate'] != null
        ? DateTime.tryParse(m['startDate']) ?? DateTime.now()
        : DateTime.now(),
    endDate: m['endDate'] != null
        ? DateTime.tryParse(m['endDate']) ?? DateTime.now().add(const Duration(days: 30))
        : DateTime.now().add(const Duration(days: 30)),
    clicks: (m['clicks'] as num?)?.toInt() ?? 0,
    impressions: (m['impressions'] as num?)?.toInt() ?? 0,
    position: (m['position'] as num?)?.toInt() ?? 5,
    createdBy: m['createdBy'] ?? '',
    createdAt: m['createdAt'] != null
        ? DateTime.tryParse(m['createdAt']) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: m['updatedAt'] != null ? DateTime.tryParse(m['updatedAt']) : null,
  );

  AdModel copyWith({
    String? title, String? subtitle, String? imageUrl,
    String? linkType, String? linkValue, String? ctaLabel,
    String? category, bool? isActive,
    DateTime? startDate, DateTime? endDate,
    int? clicks, int? impressions, int? position,
  }) => AdModel(
    id: id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    imageUrl: imageUrl ?? this.imageUrl,
    linkType: linkType ?? this.linkType,
    linkValue: linkValue ?? this.linkValue,
    ctaLabel: ctaLabel ?? this.ctaLabel,
    category: category ?? this.category,
    isActive: isActive ?? this.isActive,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    clicks: clicks ?? this.clicks,
    impressions: impressions ?? this.impressions,
    position: position ?? this.position,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  static const List<String> categories = [
    'Banque / Finance',
    'Notaire / Juridique',
    'Agence immobilière',
    'Construction / Matériaux',
    'Décoration / Intérieur',
    'Déménagement / Transport',
    'Assurance',
    'Autre',
  ];
}
