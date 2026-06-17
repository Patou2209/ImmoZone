class PropertyModel {
  final String id;
  final String title;
  final String description;
  final String type;
  final String transactionType;
  final double price;
  final String currency;
  final String country;  // pays (ex: 'Congo (RDC)', 'Congo (Brazzaville)')
  final String province;
  final String city;
  final String commune;
  final String quartier;
  final String address;
  final double? surface;
  final int? bedrooms;
  final int? bathrooms;
  final int? floors;
  final bool hasParking;
  final bool hasWater;
  final bool hasElectricity;
  final bool hasAscenseur;        // ascenseur / elevator
  final bool hasCuisineEquipee;   // cuisine équipée
  final List<String> amenities;
  final List<String> images;
  final int mainImageIndex; // index de la photo principale
  final String ownerId;
  final String ownerName;
  final String ownerPhone;
  final String ownerEmail;
  final String ownerWhatsApp; // numéro WhatsApp du vendeur
  final String ownerCategory; // 'Agence Immobilière' | 'Commissionnaire' | 'Propriétaire'
  final String status; // Brouillon | Publié | Actif | Expiré | Suspendu | Supprimé | Vendu | En location
  final bool isSold;         // marqué vendu par le vendeur
  final bool isRented;       // marqué loué par le vendeur
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final int views;
  final bool isFeatured;     // annonce en avant (boost)
  final DateTime? boostEnd;  // fin du boost
  final String? boostType;   // 'semaine' | 'mois'
  final int boostLevel;      // 0=aucun | 1=Standard | 2=Premium | 3=VIP
  final double? latitude;
  final double? longitude;
  // Champs conditionnels
  final double? pricePerNight;   // chambre d'hôtel
  final int? numberOfBeds;       // chambre d'hôtel
  final String? establishmentName; // hôtel, fêtes, funéraire
  final bool? hasAirConditioning;
  final bool? hasBreakfast;
  final double? pricePerDay;     // salle de fête
  final int? capacity;           // salle de fête
  final double? minLeaseDuration; // location
  final int? garantieMois;         // garantie locative en mois (0-12)
  final bool hasCommission;        // commission demandée
  final double? commissionPct;     // taux commission en % (0-100)
  // Terrain à bâtir — dimensions individuelles
  final double? longueurM;         // longueur en mètres
  final double? largeurM;          // largeur en mètres
  // Période de tarification pour Appartement/Flat en location
  // 'mensuel' (défaut) | 'journalier'
  final String pricePeriod;

  PropertyModel({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.transactionType,
    this.pricePeriod = 'mensuel',
    required this.price,
    this.currency = 'USD',
    this.country = 'Congo (RDC)',
    this.province = 'Kinshasa',
    required this.city,
    required this.commune,
    this.quartier = '',
    required this.address,
    this.surface,
    this.bedrooms,
    this.bathrooms,
    this.floors,
    this.hasParking = false,
    this.hasWater = true,
    this.hasElectricity = true,
    this.hasAscenseur = false,
    this.hasCuisineEquipee = false,
    this.amenities = const [],
    this.images = const [],
    this.mainImageIndex = 0,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhone,
    required this.ownerEmail,
    this.ownerWhatsApp = '',
    this.ownerCategory = '',
    this.status = 'Actif',
    this.isSold = false,
    this.isRented = false,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.views = 0,
    this.isFeatured = false,
    this.boostEnd,
    this.boostType,
    this.boostLevel = 0,
    this.latitude,
    this.longitude,
    this.pricePerNight,
    this.numberOfBeds,
    this.establishmentName,
    this.hasAirConditioning,
    this.hasBreakfast,
    this.pricePerDay,
    this.capacity,
    this.minLeaseDuration,
    this.garantieMois,
    this.hasCommission = false,
    this.commissionPct,
    this.longueurM,
    this.largeurM,
  });

  bool get isBoostActive => isFeatured && boostEnd != null && boostEnd!.isAfter(DateTime.now());
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isMarkedClosed => isSold || isRented;
  bool get isVip => isBoostActive && boostLevel == 3;
  bool get isPremium => isBoostActive && boostLevel == 2;
  bool get isStandard => isBoostActive && boostLevel == 1;
  /// Label badge visible sur la PropertyCard
  String? get boostBadge {
    if (!isBoostActive) return null;
    if (boostLevel == 3) return 'Spécial';
    return 'Offre Spéciale';
  }

  // Sentinelles publiques pour autoriser copyWith(boostEnd: null) ou copyWith(boostType: null)
  static final clearDate   = DateTime.fromMillisecondsSinceEpoch(0);
  static const String clearStr = '__clear__';

  PropertyModel copyWith({
    String? id, String? title, String? description, String? type,
    String? transactionType, double? price, String? currency,
    String? country, String? province, String? city, String? commune, String? quartier,
    String? address, double? surface, int? bedrooms, int? bathrooms,
    int? floors, bool? hasParking, bool? hasWater, bool? hasElectricity,
    bool? hasAscenseur, bool? hasCuisineEquipee,
    List<String>? amenities, List<String>? images, int? mainImageIndex,
    String? ownerId, String? ownerName, String? ownerPhone,
    String? ownerEmail, String? ownerWhatsApp, String? ownerCategory, String? status,
    bool? isSold, bool? isRented,
    DateTime? createdAt, DateTime? updatedAt, DateTime? expiresAt,
    int? views, bool? isFeatured, DateTime? boostEnd, String? boostType, int? boostLevel,
    double? latitude, double? longitude,
    double? pricePerNight, int? numberOfBeds, String? establishmentName, bool? hasAirConditioning,
    bool? hasBreakfast, double? pricePerDay, int? capacity,
    double? minLeaseDuration, int? garantieMois, bool? hasCommission, double? commissionPct,
    double? longueurM, double? largeurM,
  }) => PropertyModel(
    id: id ?? this.id, title: title ?? this.title,
    description: description ?? this.description, type: type ?? this.type,
    transactionType: transactionType ?? this.transactionType,
    price: price ?? this.price, currency: currency ?? this.currency,
    country: country ?? this.country,
    province: province ?? this.province, city: city ?? this.city,
    commune: commune ?? this.commune, quartier: quartier ?? this.quartier,
    address: address ?? this.address, surface: surface ?? this.surface,
    bedrooms: bedrooms ?? this.bedrooms, bathrooms: bathrooms ?? this.bathrooms,
    floors: floors ?? this.floors, hasParking: hasParking ?? this.hasParking,
    hasWater: hasWater ?? this.hasWater, hasElectricity: hasElectricity ?? this.hasElectricity,
    hasAscenseur: hasAscenseur ?? this.hasAscenseur,
    hasCuisineEquipee: hasCuisineEquipee ?? this.hasCuisineEquipee,
    amenities: amenities ?? this.amenities, images: images ?? this.images,
    mainImageIndex: mainImageIndex ?? this.mainImageIndex,
    ownerId: ownerId ?? this.ownerId, ownerName: ownerName ?? this.ownerName,
    ownerPhone: ownerPhone ?? this.ownerPhone, ownerEmail: ownerEmail ?? this.ownerEmail,
    ownerWhatsApp: ownerWhatsApp ?? this.ownerWhatsApp,
    ownerCategory: ownerCategory ?? this.ownerCategory,
    status: status ?? this.status, isSold: isSold ?? this.isSold,
    isRented: isRented ?? this.isRented,
    createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    views: views ?? this.views, isFeatured: isFeatured ?? this.isFeatured,
    boostEnd: boostEnd == clearDate ? null : (boostEnd ?? this.boostEnd),
    boostType: boostType == clearStr ? null : (boostType ?? this.boostType),
    boostLevel: boostLevel ?? this.boostLevel,
    latitude: latitude ?? this.latitude, longitude: longitude ?? this.longitude,
    pricePerNight: pricePerNight ?? this.pricePerNight,
    numberOfBeds: numberOfBeds ?? this.numberOfBeds,
    establishmentName: establishmentName ?? this.establishmentName,
    hasAirConditioning: hasAirConditioning ?? this.hasAirConditioning,
    hasBreakfast: hasBreakfast ?? this.hasBreakfast,
    pricePerDay: pricePerDay ?? this.pricePerDay,
    capacity: capacity ?? this.capacity,
    minLeaseDuration: minLeaseDuration ?? this.minLeaseDuration,
    garantieMois: garantieMois ?? this.garantieMois,
    hasCommission: hasCommission ?? this.hasCommission,
    commissionPct: commissionPct ?? this.commissionPct,
    longueurM: longueurM ?? this.longueurM,
    largeurM: largeurM ?? this.largeurM,
    pricePeriod: pricePeriod ?? this.pricePeriod,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'title': title, 'description': description, 'type': type,
    'transactionType': transactionType, 'price': price, 'currency': currency,
    'country': country, 'province': province, 'city': city, 'commune': commune, 'quartier': quartier,
    'address': address, 'surface': surface, 'bedrooms': bedrooms,
    'bathrooms': bathrooms, 'floors': floors, 'hasParking': hasParking,
    'hasWater': hasWater, 'hasElectricity': hasElectricity,
    'hasAscenseur': hasAscenseur, 'hasCuisineEquipee': hasCuisineEquipee,
    'amenities': amenities, 'images': images, 'mainImageIndex': mainImageIndex,
    'ownerId': ownerId, 'ownerName': ownerName, 'ownerPhone': ownerPhone,
    'ownerEmail': ownerEmail, 'ownerWhatsApp': ownerWhatsApp,
    'ownerCategory': ownerCategory,
    'status': status, 'isSold': isSold, 'isRented': isRented,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'views': views, 'isFeatured': isFeatured,
    'boostEnd': boostEnd?.toIso8601String(), 'boostType': boostType,
    'boostLevel': boostLevel,
    'latitude': latitude, 'longitude': longitude,
    'pricePerNight': pricePerNight, 'numberOfBeds': numberOfBeds, 'establishmentName': establishmentName,
    'hasAirConditioning': hasAirConditioning, 'hasBreakfast': hasBreakfast,
    'pricePerDay': pricePerDay, 'capacity': capacity,
    'minLeaseDuration': minLeaseDuration, 'garantieMois': garantieMois,
    'hasCommission': hasCommission, 'commissionPct': commissionPct,
    'longueurM': longueurM, 'largeurM': largeurM,
    'pricePeriod': pricePeriod,
  };

  factory PropertyModel.fromMap(Map<String, dynamic> m) => PropertyModel(
    id: m['id'] ?? '', title: m['title'] ?? '',
    description: m['description'] ?? '', type: m['type'] ?? '',
    transactionType: m['transactionType'] ?? '',
    price: (m['price'] ?? 0).toDouble(), currency: m['currency'] ?? 'USD',
    country: m['country'] ?? 'Congo (RDC)',
    province: m['province'] ?? 'Kinshasa', city: m['city'] ?? '',
    commune: m['commune'] ?? '', quartier: m['quartier'] ?? '',
    address: m['address'] ?? '', surface: m['surface']?.toDouble(),
    bedrooms: m['bedrooms'], bathrooms: m['bathrooms'], floors: m['floors'],
    hasParking: m['hasParking'] ?? false,
    hasWater: m['hasWater'] ?? true, hasElectricity: m['hasElectricity'] ?? true,
    hasAscenseur: m['hasAscenseur'] ?? false,
    hasCuisineEquipee: m['hasCuisineEquipee'] ?? false,
    amenities: List<String>.from(m['amenities'] ?? []),
    images: List<String>.from(m['images'] ?? []),
    mainImageIndex: m['mainImageIndex'] ?? 0,
    ownerId: m['ownerId'] ?? '', ownerName: m['ownerName'] ?? '',
    ownerPhone: m['ownerPhone'] ?? '', ownerEmail: m['ownerEmail'] ?? '',
    ownerWhatsApp: m['ownerWhatsApp'] ?? '',
    ownerCategory: m['ownerCategory'] ?? '',
    status: m['status'] ?? 'Actif',
    isSold: m['isSold'] ?? false, isRented: m['isRented'] ?? false,
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    updatedAt: m['updatedAt'] != null ? DateTime.tryParse(m['updatedAt']) : null,
    expiresAt: m['expiresAt'] != null ? DateTime.tryParse(m['expiresAt']) : null,
    views: (m['views'] as num?)?.toInt() ?? 0, isFeatured: m['isFeatured'] ?? false,
    boostEnd: m['boostEnd'] != null ? DateTime.tryParse(m['boostEnd']) : null,
    boostType: m['boostType'],
    boostLevel: (m['boostLevel'] as num?)?.toInt() ?? 0,
    latitude: m['latitude']?.toDouble(), longitude: m['longitude']?.toDouble(),
    pricePerNight: m['pricePerNight']?.toDouble(),
    numberOfBeds: m['numberOfBeds'],
    establishmentName: m['establishmentName'],
    hasAirConditioning: m['hasAirConditioning'],
    hasBreakfast: m['hasBreakfast'],
    pricePerDay: m['pricePerDay']?.toDouble(),
    capacity: m['capacity'],
    minLeaseDuration: m['minLeaseDuration']?.toDouble(),
    garantieMois: m['garantieMois'] as int?,
    hasCommission: m['hasCommission'] ?? false,
    commissionPct: m['commissionPct']?.toDouble(),
    longueurM: m['longueurM']?.toDouble(),
    largeurM: m['largeurM']?.toDouble(),
    pricePeriod: m['pricePeriod'] ?? 'mensuel',
  );

  // Prix complet sans abréviation (1000 USD, pas 1K USD)
  String get formattedPrice {
    if (price == price.truncateToDouble()) {
      return '${price.toInt()} $currency';
    }
    return '${price.toStringAsFixed(0)} $currency';
  }

  // Libellé de période pour Appartement/Flat en location
  String get pricePeriodLabel {
    if (transactionType == 'Location' && type.contains('Appartement')) {
      return pricePeriod == 'journalier' ? '/ jour' : '/ mois';
    }
    if (transactionType == 'Location') return '/ mois';
    return '';
  }

  String get mainImage {
    if (images.isEmpty) return 'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800';
    final idx = mainImageIndex.clamp(0, images.length - 1);
    return images[idx];
  }

  String get statusBadge {
    if (isSold) return 'Vendu';
    if (isRented) return 'En location';
    return status;
  }
}
