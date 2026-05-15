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
    };
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
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      lastLogin: map['lastLogin'] != null ? DateTime.parse(map['lastLogin']) : null,
      totalProperties: map['totalProperties'] ?? 0,
      description: map['description'],
      whatsApp: map['whatsApp'],
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
      case 'annonceur':
        return category ?? 'Annonceur';
      case 'demandeur':
        return 'Demandeur';
      default:
        return role;
    }
  }

  /// Label court de la catégorie annonceur pour affichage badge
  String get categoryLabel => category ?? '';

  /// Couleur associée à la catégorie
  static Map<String, int> get categoryColors => {
    'Agence Immobilière':  0xFF1565C0, // bleu foncé
    'Commissionnaire':     0xFF6A1B9A, // violet
    'Propriétaire':        0xFF2E7D32, // vert foncé
  };
}
