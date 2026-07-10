class AppConstants {
  // App Info
  static const String appName = 'ImmoZone';
  static const String appVersion = '1.0.0';

  // Web base URL (domaine personnalisé — used for share links & WhatsApp messages)
  static const String webBaseUrl = 'https://www.immozone.pro';
  static const String appTagline = 'Achetez, Vendez, Louez ou mettez un bien immobilier en quelques clics';

  // Storage Keys
  static const String keyUserRole    = 'user_role';
  static const String keyUserId      = 'user_id';
  static const String keyUserName    = 'user_name';
  static const String keyUserEmail   = 'user_email';
  static const String keyUserPhone   = 'user_phone';
  static const String keyUserAvatar  = 'user_avatar';
  static const String keyIsLoggedIn  = 'is_logged_in';
  static const String keyAuthToken   = 'auth_token';
  static const String keyFavorites   = 'favorites';

  // User Roles
  static const String roleAdmin              = 'admin';
  static const String roleAdminFinancier     = 'admin_financier';
  static const String roleAdminServiceClient = 'admin_service_client';
  static const String roleAdminMarketing     = 'admin_marketing';
  static const String roleAnnonceur          = 'annonceur';
  static const String roleDemandeur          = 'demandeur';

  // Sous-roles admin (tous les roles admin)
  static const List<String> allAdminRoles = [
    roleAdmin,
    roleAdminFinancier,
    roleAdminServiceClient,
    roleAdminMarketing,
  ];

  // Catégories d'annonceur (obligatoire à la création du compte)
  static const String categoryAgence          = 'Agence Immobilière';
  static const String categoryCommissionnaire = 'Commissionnaire';
  static const String categoryProprietaire    = 'Propriétaire';
  static const List<String> annonceurCategories = [
    categoryAgence,
    categoryCommissionnaire,
    categoryProprietaire,
  ];

  // ── MODE : filtres par defaut accueil ────────────────────────────────────
  static const String defaultMode        = 'Location';
  static const String defaultCategory   = 'Maison';
  static const String defaultCountry    = 'Congo (RDC)';
  static const String defaultProvince   = 'Kinshasa'; // Province par défaut (filtre strict)

  // ── Pays disponibles dans les filtres (2 principaux) ─────────────────────
  static const List<String> filterCountries = [
    'Congo (RDC)',
    'Congo (Brazzaville)',
  ];

  // Tous les pays (liste complete)
  static const List<String> countries = [
    'Congo (RDC)',
    'Congo (Brazzaville)',
  ];

  // ── Categories par mode ──────────────────────────────────────────────────
  static const List<String> categoriesLocation = [
    'Maison',
    'Villa',
    'Appartement / flat',
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
    'Salle de fêtes',
    'Chambre d\'hôtel',
    'Espace funéraire',
    'Salle polyvalente',
  ];

  static const List<String> categoriesAchat = [
    'Maison',
    'Villa',
    'Appartement / flat',
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
    'Concession',
    'Terrain à bâtir',
    'Salle de fêtes',
    'Espace funéraire',
    'Salle polyvalente',
  ];

  static const List<String> categoriesPublication = [
    'Maison',
    'Villa',
    'Appartement / flat',
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
    'Concession',
    'Terrain à bâtir',
    'Salle de fêtes',
    'Chambre d\'hôtel',
    'Espace funéraire',
    'Salle polyvalente',
  ];

  static const List<String> propertyTypes = [
    'Maison',
    'Villa',
    'Appartement / flat',
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
    'Concession',
    'Terrain à bâtir',
    'Salle de fêtes',
    'Chambre d\'hôtel',
    'Espace funéraire',
    'Salle polyvalente',
  ];

  static const List<String> transactionTypes = [
    'Location',
    'Vente',
  ];

  // ── Filtres avances par categorie ───────────────────────────────────────
  static const List<String> catWithRooms = [
    'Maison',
    'Villa',
    'Appartement / flat',
  ];
  static const List<String> catWithBeds = [
    'Chambre d\'hotel',
  ];
  // Superficie OBLIGATOIRE pour ces types
  static const List<String> catWithSurfaceRequired = [
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
  ];
  // Superficie OPTIONNELLE pour ces types
  static const List<String> catWithSurfaceOptional = [
    'Maison',
    'Villa',
    'Appartement / flat',
    'Chambre d\'hôtel',
    'Espace funéraire',
    'Salle polyvalente',
  ];
  // Garde l'ancien nom pour compatibilité (union des deux)
  static const List<String> catWithSurface = [
    'Bureau',
    'Propriété commerciale',
    'Propriété industrielle',
    'Maison',
    'Villa',
    'Appartement / flat',
    'Chambre d\'hôtel',
    'Espace funéraire',
    'Salle polyvalente',
  ];
  static const List<String> catWithSeats = [
    'Salle de fêtes',
    'Espace funéraire',
    'Salle polyvalente',
  ];
  // Superficie en hectares (ha) pour Concession
  static const List<String> catWithHectares = [
    'Concession',
  ];
  // Dimensions L×l pour Terrain à bâtir
  static const List<String> catWithDimensions = [
    'Terrain à bâtir',
  ];

  // ── Statuts des annonces ────────────────────────────────────────────────
  static const String statusPending   = 'En attente';
  static const String statusActive    = 'Actif';
  static const String statusSold      = 'Vendu';
  static const String statusOccupied  = 'Occupe';
  static const String statusRented    = 'Loue';
  static const String statusRejected  = 'Rejete';
  static const String statusExpired   = 'Expire';
  static const String statusSuspended = 'Suspendu';

  // ── Provinces RDC ───────────────────────────────────────────────────────
  static const List<String> provinces = [
    'Kinshasa',
    'Kongo-Central',
    'Kwango',
    'Kwilu',
    'Mai-Ndombe',
    'Kasai',
    'Kasai-Central',
    'Kasai-Oriental',
    'Lomami',
    'Sankuru',
    'Maniema',
    'Sud-Kivu',
    'Nord-Kivu',
    'Ituri',
    'Haut-Uele',
    'Bas-Uele',
    'Tshopo',
    'Mongala',
    'Nord-Ubangi',
    'Sud-Ubangi',
    'Equateur',
    'Tshuapa',
    'Tanganyika',
    'Haut-Lomami',
    'Lualaba',
    'Haut-Katanga',
  ];

  // ── Provinces Congo Brazzaville ──────────────────────────────────────────
  static const List<String> provincesBrazzaville = [
    'Brazzaville',
    'Pointe-Noire',
    'Pool',
    'Bouenza',
    'Niari',
    'Lekoumou',
    'Kouilou',
    'Plateaux',
    'Cuvette',
    'Cuvette-Ouest',
    'Sangha',
    'Likouala',
  ];

  // ── Villes par province RDC ──────────────────────────────────────────────
  static const Map<String, List<String>> citiesByProvince = {
    'Kinshasa':      ['Kinshasa'],
    'Kongo-Central': ['Matadi', 'Boma', 'Mbanza-Ngungu', 'Tshela'],
    'Kwango':        ['Kenge', 'Kasongo-Lunda'],
    'Kwilu':         ['Bandundu', 'Kikwit', 'Idiofa', 'Gungu'],
    'Mai-Ndombe':    ['Inongo', 'Bolobo'],
    'Kasai':         ['Tshikapa', 'Ilebo'],
    'Kasai-Central': ['Kananga', 'Mweka', 'Dimbelenge'],
    'Kasai-Oriental':['Mbuji-Mayi', 'Kabinda'],
    'Lomami':        ['Kabalo', 'Kabinda', 'Ngandajika'],
    'Sankuru':       ['Lusambo', 'Kole'],
    'Maniema':       ['Kindu', 'Kailo'],
    'Sud-Kivu':      ['Bukavu', 'Uvira', 'Baraka', 'Fizi'],
    'Nord-Kivu':     ['Goma', 'Butembo', 'Beni', 'Lubero'],
    'Ituri':         ['Bunia', 'Mahagi'],
    'Haut-Uele':     ['Isiro', 'Wamba'],
    'Bas-Uele':      ['Buta', 'Aketi'],
    'Tshopo':        ['Kisangani', 'Ubundu'],
    'Mongala':       ['Lisala', 'Bumba'],
    'Nord-Ubangi':   ['Gbadolite', 'Yakoma'],
    'Sud-Ubangi':    ['Gemena', 'Zongo'],
    'Equateur':      ['Mbandaka', 'Bikoro'],
    'Tshuapa':       ['Boende', 'Befale'],
    'Tanganyika':    ['Kalemie', 'Moba', 'Kongolo'],
    'Haut-Lomami':   ['Kamina', 'Bukama'],
    'Lualaba':       ['Kolwezi', 'Dilolo', 'Mutshatsha'],
    'Haut-Katanga':  ['Lubumbashi', 'Likasi', 'Kipushi', 'Kasenga'],
  };

  // ── Villes par province Congo Brazzaville ────────────────────────────────
  static const Map<String, List<String>> citiesByProvinceBrazzaville = {
    'Brazzaville':   ['Brazzaville'],
    'Pointe-Noire':  ['Pointe-Noire'],
    'Pool':          ['Kinkala', 'Boko'],
    'Bouenza':       ['Madingou', 'Nkayi', 'Loudima'],
    'Niari':         ['Dolisie', 'Mossendjo'],
    'Lekoumou':      ['Sibiti', 'Komono'],
    'Kouilou':       ['Pointe-Noire', 'Loango'],
    'Plateaux':      ['Djambala', 'Abala'],
    'Cuvette':       ['Owando', 'Makoua'],
    'Cuvette-Ouest': ['Ewo', 'Kelle'],
    'Sangha':        ['Ouesso', 'Mokeko'],
    'Likouala':      ['Impfondo', 'Epena'],
  };

  // ── Communes par ville (RDC + Congo-Brazzaville) ────────────────────────
  static const Map<String, List<String>> communesByCity = {
    // ── RDC ─────────────────────────────────────────────────────────────────
    'Kinshasa': [
      'Bandalungwa', 'Barumbu', 'Bumbu', 'Gombe', 'Kalamu',
      'Kasa-Vubu', 'Kimbanseke', 'Kinshasa', 'Kintambo', 'Kisenso',
      'Lemba', 'Limete', 'Lingwala', 'Makala', 'Maluku',
      'Masina', 'Matete', 'Mont-Ngafula', 'Ndjili', 'Ngaba',
      'Ngaliema', 'Ngiri-Ngiri', 'Nsele', 'Selembao',
    ],
    'Lubumbashi': [
      'Annexe', 'Kamalondo', 'Kampemba', 'Katuba', 'Kenya',
      'Lubumbashi', 'Rwashi',
    ],
    'Mbuji-Mayi': [
      'Bipemba', 'Dibindi', 'Diulu', 'Kanshi', 'Muya',
    ],
    'Kananga': [
      'Kananga', 'Katoka', 'Lukonga', 'Ndesha', 'Nganza',
    ],
    'Kisangani': [
      'Kisangani', 'Kabondo', 'Lubunga', 'Tshopo', 'Mangobo', 'Makiso',
    ],
    'Bukavu': [
      'Bagira', 'Ibanda', 'Kadutu', 'Kasha',
    ],
    'Goma': [
      'Goma', 'Karisimbi',
    ],
    'Kolwezi': [
      'Dilala', 'Manika',
    ],
    'Likasi': [
      'Kikula', 'Likasi', 'Panda', 'Shituru',
    ],
    'Matadi': [
      'Matadi', 'Mvuzi', 'Nzanza',
    ],
    'Boma': [
      'Nzadi', 'Kabondo', 'Kalamu',
    ],
    'Kikwit': [
      'Kazamba', 'Lukemi', 'Lukolela', 'Nzinda',
    ],
    'Tshikapa': [
      'Dibumba I', 'Dibumba II', 'Kanzala', 'Mabondo', 'Mbumba',
    ],
    'Butembo': [
      'Bulengera', 'Kimemi', 'Mususa', 'Vulamba',
    ],
    'Bunia': [
      'Shari', 'Nyakasanza', 'Mbunya',
    ],
    'Uvira': [
      'Uvira', 'Mulongwe', 'Kalundu',
    ],
    'Mbandaka': [
      'Mbandaka', 'Wangata', 'Bikoro',
    ],
    // ── Congo-Brazzaville ────────────────────────────────────────────────────
    'Brazzaville': [
      'Makelelekele', 'Bacongo', 'Poto-Poto', 'Moungali', 'Ouenze',
      'Talangai', 'Mfilou', 'Madibou', 'Djiri',
    ],
    'Pointe-Noire': [
      'Lumumba', 'Mvoumvou', 'Tie-Tie', 'Loandjili', 'Mongo-Mpoukou', 'Ngoyo',
    ],
    'Dolisie': [
      'Arrondissement 1', 'Arrondissement 2',
    ],
    'Nkayi': [
      'Mouana-nto', 'Soulouka',
    ],
    'Owando':   ['Owando Centre'],
    'Ouesso':   ['Ouesso Centre'],
    'Impfondo': ['Impfondo Centre'],
    'Sibiti':   ['Sibiti Centre'],
    'Djambala': ['Djambala Centre'],
  };

  // Toutes les villes (liste plate – compatibilite)
  static const List<String> cities = [
    // RDC
    'Kinshasa', 'Lubumbashi', 'Mbuji-Mayi', 'Kananga', 'Kisangani',
    'Bukavu', 'Goma', 'Kolwezi', 'Likasi', 'Matadi', 'Boma',
    'Kikwit', 'Tshikapa', 'Butembo', 'Bunia', 'Uvira', 'Mbandaka',
    // Congo-Brazzaville
    'Brazzaville', 'Pointe-Noire', 'Dolisie', 'Nkayi',
  ];

  // Communes de Kinshasa (compatibilite existante)
  static const List<String> communesKinshasa = [
    'Gombe', 'Lingwala', 'Kinshasa', 'Barumbu', 'Ngiri-Ngiri',
    'Kalamu', 'Lemba', 'Makala', 'Bandalungwa', 'Kintambo',
    'Mont-Ngafula', 'Ngaliema', 'Kisenso', 'Matete', 'Ndjili',
    'Masina', 'Nsele', 'Maluku', 'Selembao', 'Bumbu',
    'Kasavubu', 'Limete', 'Quartier Industriel',
  ];

  // ── Helper : retourne les villes selon pays + province ──────────────────
  static List<String> getCitiesForProvince(String country, String province) {
    if (country == 'Congo (Brazzaville)') {
      return citiesByProvinceBrazzaville[province] ?? [];
    }
    return citiesByProvince[province] ?? [];
  }

  // ── Helper : retourne les provinces selon le pays ────────────────────────
  static List<String> getProvincesForCountry(String country) {
    if (country == 'Congo (Brazzaville)') return provincesBrazzaville;
    return provinces;
  }

  // ── Helper : retourne les communes selon la ville ────────────────────────
  static List<String> getCommunesForCity(String city) {
    return communesByCity[city] ?? [];
  }

  // ── Helper : retourne les villes selon le pays ────────────────────────────
  // Retourne toutes les villes qui ont des communes definies dans communesByCity,
  // filtrees par pays (RDC ou Congo-Brazzaville).
  static const List<String> _rdcCities = [
    'Kinshasa', 'Lubumbashi', 'Mbuji-Mayi', 'Kananga', 'Kisangani',
    'Bukavu', 'Goma', 'Kolwezi', 'Likasi', 'Matadi', 'Boma',
    'Kikwit', 'Tshikapa', 'Butembo', 'Bunia',
  ];

  static const List<String> _brvCities = [
    'Brazzaville', 'Pointe-Noire', 'Dolisie', 'Nkayi',
  ];

  static List<String> getCitiesForCountry(String country) {
    if (country == 'Congo (Brazzaville)') return _brvCities;
    if (country == 'Congo (RDC)') return _rdcCities;
    // Pour les autres pays, liste vide (pas encore de donnees)
    return [];
  }

  // ── Equipements ─────────────────────────────────────────────────────────
  static const List<String> amenities = [
    'Piscine', 'Garage', 'Jardin', 'Terrasse', 'Gardiennage',
    'Ascenseur', 'Groupe electrogene', 'Eau courante', 'Climatisation',
    'Internet', 'Cuisine \u00e9quip\u00e9e', 'Parquet', 'Carrelage',
    'Securite 24h/24', 'Parking', 'Cloture', 'Citerne d\'eau',
    'Panneaux solaires', 'Annexe', 'Espace de stockage',
  ];

  // ── Duree auto-suppression annonces vendues (en heures) ─────────────────
  static const int soldAutoDeleteHours = 72;

  // Pagination
  static const int pageSize = 10;

  // Image placeholder
  static const String placeholderProperty =
      'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=800';

  // ── Moyens de paiement par defaut ───────────────────────────────────────
  static const List<Map<String, String>> defaultPaymentMethods = [
    {'name': 'M-Pesa (Vodacom)', 'number': '+243 81 000 0001', 'icon': 'mpesa'},
    {'name': 'Orange Money',     'number': '+243 84 000 0002', 'icon': 'orange'},
    {'name': 'Airtel Money',     'number': '+243 99 000 0003', 'icon': 'airtel'},
  ];

  // ── Indicatifs pays du monde (pour WhatsApp) ────────────────────────────
  static const List<Map<String, String>> countryCodes = [
    {'code': '+243', 'country': 'Congo (RDC)',         'flag': '🇨🇩'},
    {'code': '+242', 'country': 'Congo (Brazzaville)', 'flag': '🇨🇬'},
  ];
}
