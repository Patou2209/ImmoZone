class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? category; // 'Agence Immobilière' | 'Commissionnaire' | 'Propriétaire'
  final String? avatar;
  final String? city;
  final String? commune;
  final String? address;
  final bool isActive;
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? lastLogin;
  final int totalProperties;
  final String? description;
  final String? whatsApp;
  final String? sponsorCode;      // code parrainage SAISI à l'inscription (code du parrain qui l'a recruté)
  final String? myReferralCode;   // son PROPRE code parrain (généré à la création du compte)
  final String? country;          // pays de l'utilisateur
  final String? province;         // province

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.category,
    this.avatar,
    this.city,
    this.commune,
    this.address,
    this.isActive = true,
    this.isVerified = false,
    required this.createdAt,
    this.lastLogin,
    this.totalProperties = 0,
    this.description,
    this.whatsApp,
    this.sponsorCode,
    this.myReferralCode,
    this.country,
    this.province,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? category,
    String? avatar,
    String? city,
    String? commune,
    String? address,
    bool? isActive,
    bool? isVerified,
    DateTime? createdAt,
    DateTime? lastLogin,
    int? totalProperties,
    String? description,
    String? whatsApp,
    String? sponsorCode,
    String? myReferralCode,
    String? country,
    String? province,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      category: category ?? this.category,
      avatar: avatar ?? this.avatar,
      city: city ?? this.city,
      commune: commune ?? this.commune,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
      totalProperties: totalProperties ?? this.totalProperties,
      description: description ?? this.description,
      whatsApp: whatsApp ?? this.whatsApp,
      sponsorCode: sponsorCode ?? this.sponsorCode,
      myReferralCode: myReferralCode ?? this.myReferralCode,
      country: country ?? this.country,
      province: province ?? this.province,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'category': category,
      'avatar': avatar,
      'city': city,
      'commune': commune,
      'address': address,
      'isActive': isActive,
      'isVerified': isVerified,
      'createdAt': createdAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'totalProperties': totalProperties,
      'description': description,
      'whatsApp': whatsApp,
      'sponsorCode': sponsorCode,
      'myReferralCode': myReferralCode,
      'country': country,
      'province': province,
    };
  }

  /// Convertit une valeur Firestore (Timestamp OU String ISO8601 OU null) en DateTime
  static DateTime _parseDate(dynamic value, {DateTime? fallback}) {
    if (value == null) return fallback ?? DateTime.now();
    // Firestore Timestamp (cloud_firestore renvoie un objet avec .toDate())
    if (value is DateTime) return value;
    try {
      // Utilise la réflexion duck-typing : Timestamp a une méthode toDate()
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    // Sinon c'est une String ISO8601
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return fallback ?? DateTime.now();
    }
  }

  static DateTime? _parseDateNullable(dynamic value) {
    if (value == null) return null;
    return _parseDate(value);
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'demandeur',
      category: map['category'],
      avatar: map['avatar'],
      city: map['city'],
      commune: map['commune'],
      address: map['address'],
      isActive: map['isActive'] ?? true,
      isVerified: map['isVerified'] ?? false,
      createdAt: _parseDate(map['createdAt']),
      lastLogin: _parseDateNullable(map['lastLogin']),
      totalProperties: map['totalProperties'] ?? 0,
      description: map['description'],
      whatsApp: map['whatsApp'],
      sponsorCode: map['sponsorCode'],
      myReferralCode: map['myReferralCode'],
      country: map['country'],
      province: map['province'],
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String get roleLabel {
    switch (role) {
      case 'admin':
        return 'Administrateur';
      case 'admin_financier':
        return 'Admin Financier';
      case 'admin_service_client':
        return 'Admin Service Client';
      case 'admin_marketing':
        return 'Resp. Mktg & Commercial';
      case 'annonceur':
        return category ?? 'Annonceur';
      case 'demandeur':
        return 'Demandeur';
      default:
        return role;
    }
  }

  bool get isAdminRole =>
      role == 'admin' ||
      role == 'admin_financier' ||
      role == 'admin_service_client' ||
      role == 'admin_marketing';

  /// Label court de la catégorie annonceur pour affichage badge
  String get categoryLabel => category ?? '';

  /// Couleur associée à la catégorie
  static Map<String, int> get categoryColors => {
    'Agence Immobilière':  0xFF1565C0, // bleu foncé
    'Commissionnaire':     0xFF6A1B9A, // violet
    'Propriétaire':        0xFF2E7D32, // vert foncé
  };
}
