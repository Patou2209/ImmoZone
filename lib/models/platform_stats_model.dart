/// Résultats des statistiques plateforme (9 métriques)
class PlatformStats {
  final double totalDeposits;        // 1. Total dépôts ($)
  final double creditsConsumed;      // 2. Crédits consommés
  final int postedProperties;        // 3. Annonces postées
  final int expiredProperties;       // 4. Annonces expirées
  final Map<String, int> closedByType; // 5. Annonces clôturées par catégorie
  final int newUsersCount;           // 6. Nouveaux utilisateurs
  final int totalUsersCount;         // 7. Total utilisateurs
  final int activeUsersCount;        // 8. Utilisateurs actifs (30j)
  final int inactiveUsersCount;      // 9. Inactifs depuis 90j
  final Map<String, double> chartData; // données bar chart

  const PlatformStats({
    required this.totalDeposits,
    required this.creditsConsumed,
    required this.postedProperties,
    required this.expiredProperties,
    required this.closedByType,
    required this.newUsersCount,
    required this.totalUsersCount,
    required this.activeUsersCount,
    required this.inactiveUsersCount,
    required this.chartData,
  });

  static PlatformStats empty() => const PlatformStats(
    totalDeposits: 0,
    creditsConsumed: 0,
    postedProperties: 0,
    expiredProperties: 0,
    closedByType: {},
    newUsersCount: 0,
    totalUsersCount: 0,
    activeUsersCount: 0,
    inactiveUsersCount: 0,
    chartData: {},
  );
}

/// Statistiques liées à un parrain (5 métriques)
class ParrainStats {
  final String sponsorCode;
  final int associatedCount;   // 10. Comptes associés dans la période
  final int activeCount;       // 11. Comptes actifs dans la période
  final double depositsUsd;    // 12. Dépôts en $ dans la période
  final int propertiesCount;   // 13. Annonces réalisées dans la période
  final int inactiveCount;     // 14. Comptes inactifs depuis 90j

  const ParrainStats({
    required this.sponsorCode,
    required this.associatedCount,
    required this.activeCount,
    required this.depositsUsd,
    required this.propertiesCount,
    required this.inactiveCount,
  });
}
