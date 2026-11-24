import 'dart:math';

/// Jass-Wertung: schätzt die Spielstärke einer Person aus fertigen Partien.
///
/// Verfahren (ausgewählt per Simulation, siehe tool/rating_sim/):
/// ein TrueSkill-artiges Bayes-Verfahren, das nicht nur Sieg/Niederlage,
/// sondern die Punktedifferenz am Ende der Partie nutzt.
///
/// * Jede Person hat eine geschätzte Stärke [SkillEstimate.mu] und eine
///   Unsicherheit [SkillEstimate.variance].
/// * Teamstärke = Summe der beiden Personen.
/// * Erwartete Differenz = [gain] × (Stärke Team A − Stärke Team B),
///   gemessen in «Strichen» (−7 … +7), siehe [marginFromPoints].
/// * Nach der Partie wird die Stärke um einen Teil der Überraschung
///   (tatsächliche − erwartete Differenz) verschoben. Der Teil ist gross, solange
///   die Wertung unsicher ist, und klein, sobald sie gefestigt ist.
/// * Die Unsicherheit wächst mit jeder Partie ein wenig ([drift]), damit sich
///   Fortschritte auch nach vielen Partien noch zeigen.
class JassRating {
  JassRating._();

  /// Umrechnung Stärke → Differenz in Strichen.
  static const gain = 2.0;

  /// Glücksanteil einer Partie, in Strichen (Standardabweichung).
  /// Eingemessen mit tool/rating_kalibrierung.dart.
  static const noise = 2.5;

  /// Zunahme der Unsicherheit pro Partie (Standardabweichung).
  static const drift = 0.03;

  /// Startwert neuer Personen = Stufe «Stammtisch».
  static const prior = SkillEstimate(mu: 0, variance: 0.8 * 0.8);

  /// Sichtbare Zahl: 1000 = Stammtisch-Computer, 200 Punkte = 1 Stärkeeinheit.
  static int display(double mu) => (1000 + 200 * mu).round();

  /// So viele Partien gilt eine Wertung als vorläufig.
  static const provisionalGames = 10;

  /// Punktedifferenz am Ende einer Partie → «Striche» aus Sicht von Team A.
  ///
  /// 10 % des Zielwerts entsprechen einem Strich, begrenzt auf ±7 (wie beim
  /// Jassverband). Das Siegerteam hat immer mindestens +1.
  static double marginFromPoints(
    int own,
    int opp,
    int target, {
    required bool won,
  }) {
    var m = 10.0 * (own - opp) / max(target, 1);
    m = m.clamp(-7.0, 7.0);
    if (won && m < 1) m = 1;
    if (!won && m > -1) m = -1;
    return m;
  }

  /// Wahrscheinlichkeit, dass Team A gewinnt.
  static double winProbability(
    List<SkillEstimate> teamA,
    List<SkillEstimate> teamB,
  ) {
    final d = _sum(teamA) - _sum(teamB);
    final s = sqrt(_var(teamA, teamB) * gain * gain + noise * noise);
    return _phi(gain * d / s);
  }

  /// Neue Schätzung für alle Personen nach einer Partie.
  ///
  /// [margin] aus Sicht von Team A (siehe [marginFromPoints]). Personen mit
  /// fester Wertung (Computergegner) markiert [fixedA] bzw. [fixedB]; sie
  /// bleiben unverändert.
  static (List<SkillEstimate>, List<SkillEstimate>) update(
    List<SkillEstimate> teamA,
    List<SkillEstimate> teamB,
    double margin, {
    List<bool>? fixedA,
    List<bool>? fixedB,
  }) {
    bool isFixed(List<bool>? f, int i) => f != null && f[i];
    List<SkillEstimate> drifted(List<SkillEstimate> t, List<bool>? f) => [
      for (var i = 0; i < t.length; i++)
        isFixed(f, i)
            ? t[i]
            : SkillEstimate(
                mu: t[i].mu,
                variance: t[i].variance + drift * drift,
              ),
    ];
    final a = drifted(teamA, fixedA), b = drifted(teamB, fixedB);
    final s2 = _var(a, b) * gain * gain + noise * noise;
    // Erwartung auf ±7 begrenzt: Wer schon das Maximum holt, verliert nichts,
    // auch wenn er gegen viel Schwächere rechnerisch noch mehr «sollte».
    final expected = (gain * (_sum(a) - _sum(b))).clamp(-7.0, 7.0);
    final surprise = margin - expected;
    List<SkillEstimate> apply(List<SkillEstimate> t, List<bool>? f, int sign) =>
        [
          for (var i = 0; i < t.length; i++)
            if (isFixed(f, i))
              t[i]
            else
              SkillEstimate(
                mu: t[i].mu + sign * gain * t[i].variance / s2 * surprise,
                variance: max(
                  t[i].variance - pow(gain * t[i].variance, 2) / s2,
                  1e-4,
                ),
              ),
        ];
    return (apply(a, fixedA, 1), apply(b, fixedB, -1));
  }

  static double _sum(List<SkillEstimate> t) => t.fold(0.0, (s, p) => s + p.mu);
  static double _var(List<SkillEstimate> a, List<SkillEstimate> b) =>
      [...a, ...b].fold(0.0, (s, p) => s + p.variance);

  static double _phi(double x) => 0.5 * (1 + _erf(x / sqrt2));

  // Abramowitz-Stegun 7.1.26, genau genug für Prognosen.
  static double _erf(double x) {
    final s = x.sign;
    x = x.abs();
    final t = 1 / (1 + 0.3275911 * x);
    final y =
        1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                        0.284496735) *
                    t +
                0.254829592) *
            t *
            exp(-x * x);
    return s * y;
  }
}

/// Geschätzte Stärke einer Person oder eines Computergegners.
class SkillEstimate {
  const SkillEstimate({required this.mu, required this.variance});
  final double mu;
  final double variance;

  double get sd => sqrt(variance);

  Map<String, dynamic> toJson() => {'mu': mu, 'var': variance};
  factory SkillEstimate.fromJson(Map<String, dynamic> j) => SkillEstimate(
    mu: (j['mu'] as num).toDouble(),
    variance: (j['var'] as num).toDouble(),
  );
}

/// Rangliste 1: allein gegen den Computer (nur auf dem Gerät gespeichert).
///
/// Bewertet wird nur die Person. Partner und Gegner sind Computer mit fest
/// eingemessener Stärke ([botSkill]), deshalb ist die Wertung auch ohne Server
/// vergleichbar. Die zweite Rangliste (Online) nutzt dieselbe Rechnung
/// [JassRating.update] für alle vier Personen, aber auf dem Server.
class SoloRating {
  const SoloRating({
    this.skill = JassRating.prior,
    this.games = 0,
    this.best,
    this.lastChange,
  });

  final SkillEstimate skill;
  final int games;

  /// Höchste erreichte Zahl (erst nach den vorläufigen Partien).
  final int? best;

  /// Änderung der sichtbaren Zahl durch die letzte Partie.
  final int? lastChange;

  int get value => JassRating.display(skill.mu);
  bool get provisional => games < JassRating.provisionalGames;

  /// Rangstufe (erst nach den vorläufigen Partien sinnvoll).
  RankTier get tier => RankTier.of(value);

  /// Mindestniederlage für ein aufgegebenes Spiel, in Strichen.
  static const abandonMargin = -3.0;

  /// Eingemessene Stärke der Computerstufen (tool/rating_kalibrierung.dart,
  /// 80 Partien je Paarung bis 2500, Nov. 2026): Anfänger ≈ 760,
  /// Stammtisch = 1000, Profi ≈ 1160. Streuung je Partie ≈ 2.0–2.5 Striche.
  /// Schlüssel = Name der Stufe (BotLevel.name).
  static const botSkill = {
    'anfaenger': SkillEstimate(mu: -1.2, variance: 0.0025),
    'stammtisch': SkillEstimate(mu: 0, variance: 0.0025),
    'profi': SkillEstimate(mu: 0.8, variance: 0.0025),
  };

  /// Neue Wertung nach einer fertigen Partie gegen die Stufe [level].
  SoloRating afterGame({
    required String level,
    required int ownPoints,
    required int oppPoints,
    required int target,
    required bool won,
    bool abandoned = false,
  }) {
    final bot = botSkill[level] ?? botSkill['stammtisch']!;
    var margin = JassRating.marginFromPoints(
      ownPoints,
      oppPoints,
      target,
      won: won && !abandoned,
    );
    // Aufgegeben zählt als Niederlage, mindestens so deutlich wie −3 Striche.
    if (abandoned) margin = min(margin, abandonMargin);
    final (a, _) = JassRating.update(
      [skill, bot],
      [bot, bot],
      margin,
      fixedA: const [false, true],
      fixedB: const [true, true],
    );
    final next = a[0];
    final n = games + 1;
    final v = JassRating.display(next.mu);
    final counts = n >= JassRating.provisionalGames;
    return SoloRating(
      skill: next,
      games: n,
      best: counts ? max(best ?? v, v) : null,
      lastChange: v - value,
    );
  }

  Map<String, dynamic> toJson() => {
    'skill': skill.toJson(),
    'games': games,
    'best': best,
    'last': lastChange,
  };

  factory SoloRating.fromJson(Map<String, dynamic> j) => SoloRating(
    skill: SkillEstimate.fromJson(j['skill'] as Map<String, dynamic>),
    games: j['games'] as int,
    best: j['best'] as int?,
    lastChange: j['last'] as int?,
  );
}

/// Rangstufen der Jass-Wertung: die Kartenleiter des Schweizer Blatts,
/// vom Sächsi bis zum Trumpf-Puur (eigene Namen, nicht von anderen Apps).
///
/// Stammtisch-Computer (1000) = Ober, Profi-Computer (≈1160) = Ass.
class RankTier {
  const RankTier(this.name, this.minValue, this.hint);
  final String name;
  final int minValue;

  /// Kurze Erklärung für die Anzeige.
  final String hint;

  static const all = [
    RankTier('Sächsi', -100000, 'Der Anfang jeder Jasskarriere'),
    RankTier('Sibni', 700, 'Erste Stiche sitzen'),
    RankTier('Achti', 760, 'Auf Augenhöhe mit dem Anfänger-Computer'),
    RankTier('Nüni', 820, 'Die Regeln sitzen'),
    RankTier('Banner', 880, 'Man zählt mit'),
    RankTier('Under', 940, 'Knapp unter dem Stammtisch'),
    RankTier('Ober', 1000, 'Stammtisch-Niveau'),
    RankTier('König', 1060, 'Besser als der Stammtisch'),
    RankTier('Ass', 1120, 'Auf Augenhöhe mit dem Profi-Computer'),
    RankTier('Nell', 1180, 'Schlägt den Profi-Computer'),
    RankTier('Puur', 1260, 'Der höchste Trumpf'),
  ];

  /// Stufe zur sichtbaren Wertung.
  static RankTier of(int value) => all.lastWhere((t) => value >= t.minValue);

  /// Nächste Stufe, oder null ganz oben.
  RankTier? get next {
    final i = all.indexOf(this);
    return i + 1 < all.length ? all[i + 1] : null;
  }
}
