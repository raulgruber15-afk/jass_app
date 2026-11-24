import 'dart:math';

import 'cards.dart';
import 'game_mode.dart';
import 'rules.dart';

/// Einstellungen für den Schieber. Alles, was je nach Stammtisch anders
/// gespielt wird, gehört hierher statt fest in den Code.
class SchieberSettings {
  const SchieberSettings({
    this.targetPoints = 2500,
    this.useMultipliers = true,
  });

  /// Wer zuerst so viele Punkte hat, gewinnt (üblich: 1000, 1500, 2500).
  final int targetPoints;

  /// Zählt das Spiel je nach Trumpf mehrfach?
  /// (Annahme, einstellbar: Herz/Karo ×1, Pik/Kreuz ×2, Obenabe/Undenufe ×3)
  final bool useMultipliers;

  int multiplierFor(GameMode mode) {
    if (!useMultipliers) return 1;
    return switch (mode.type) {
      ModeType.obenabe || ModeType.undenufe => 3,
      ModeType.trump =>
        (mode.trumpSuit == Suit.pik || mode.trumpSuit == Suit.kreuz) ? 2 : 1,
    };
  }

  SchieberSettings copyWith({int? targetPoints, bool? useMultipliers}) =>
      SchieberSettings(
        targetPoints: targetPoints ?? this.targetPoints,
        useMultipliers: useMultipliers ?? this.useMultipliers,
      );
}

/// Phasen einer Runde.
enum Phase {
  /// Jemand muss Trumpf bestimmen oder schieben.
  chooseMode,

  /// Karten werden gespielt.
  playing,

  /// Vier Karten liegen, der Stich wird gleich eingezogen.
  trickComplete,

  /// Alle neun Stiche gespielt, Punkte sind verbucht.
  roundOver,

  /// Ein Team hat das Ziel erreicht.
  gameOver,
}

/// Team eines Sitzplatzes. Sitz 0 und 2 sind Team 0 («Wir»), 1 und 3 Team 1.
int teamOf(int seat) => seat % 2;

/// Nächster Sitz im Gegenuhrzeigersinn (so wird in der Schweiz gespielt).
/// Sitz 0 ist unten, 1 rechts, 2 oben (Partner), 3 links.
int nextSeat(int seat) => (seat + 1) % 4;

int partnerOf(int seat) => (seat + 2) % 4;

class CompletedTrick {
  CompletedTrick(this.cards, this.seats, this.winner, this.points);
  final List<JassCard> cards;
  final List<int> seats;
  final int winner;
  final int points;
}

/// Was eine Person in einer Runde gewiesen hat.
class WeisAnnouncement {
  WeisAnnouncement(this.seat, this.weise);
  final int seat;
  final List<Weis> weise;
  int get total => weise.fold(0, (s, w) => s + w.points);
}

/// Abrechnung einer Runde.
class RoundResult {
  RoundResult({
    required this.mode,
    required this.multiplier,
    required this.cardPoints,
    required this.weisPoints,
    required this.stoeckPoints,
    required this.matchTeam,
  });

  final GameMode mode;
  final int multiplier;

  /// Kartenpunkte ohne Multiplikator (inkl. 5 für den letzten Stich,
  /// bei Match 257).
  final List<int> cardPoints;

  /// Weis- und Stöckpunkte, schon mit Multiplikator.
  final List<int> weisPoints;
  final List<int> stoeckPoints;

  /// Team, das alle Stiche gemacht hat (Match), sonst null.
  final int? matchTeam;

  int scoreFor(int team) =>
      cardPoints[team] * multiplier + weisPoints[team] + stoeckPoints[team];
}

/// Ein komplettes Schieber-Spiel für vier Sitze.
///
/// Wer an einem Sitz spielt (Mensch, Computer, später WLAN), ist dieser
/// Klasse egal: Sie nimmt nur Züge entgegen und prüft sie.
class SchieberGame {
  SchieberGame({this.settings = const SchieberSettings(), Random? random})
    : _rng = random ?? Random();

  final SchieberSettings settings;
  final Random _rng;

  // Spielstand über alle Runden.
  final List<int> totals = [0, 0];
  final List<RoundResult> history = [];
  int roundNumber = 0;
  int? winnerTeam;

  // Zustand der aktuellen Runde.
  Phase phase = Phase.roundOver;
  List<List<JassCard>> hands = List.generate(4, (_) => <JassCard>[]);

  /// Wer diese Runde Trumpf bestimmen muss («Vorhand»). Spielt auch aus.
  int chooser = 0;
  bool geschoben = false;
  GameMode? mode;

  /// Wer gerade am Zug ist (Karte spielen oder Trumpf wählen).
  int toAct = 0;

  final List<JassCard> trick = [];
  final List<int> trickSeats = [];
  final List<CompletedTrick> tricks = [];
  final List<int> roundCardPoints = [0, 0];
  final List<int> roundWeis = [0, 0];
  final List<int> roundStoeck = [0, 0];

  /// Alle Weise dieser Runde (nur von Sitzen, die etwas zu weisen haben).
  List<WeisAnnouncement> announcements = [];

  /// Team, dessen Weise zählen (oder null, wenn niemand weist).
  int? weisWinnerTeam;
  int? stoeckSeat;
  bool stoeckAnnounced = false;
  RoundResult? lastResult;

  int get multiplier => mode == null ? 1 : settings.multiplierFor(mode!);

  /// Startet ein neues Spiel und teilt die erste Runde aus.
  /// Beim ersten Spiel bestimmt, wer die Karo 7 hat.
  void start() {
    totals
      ..[0] = 0
      ..[1] = 0;
    history.clear();
    roundNumber = 0;
    winnerTeam = null;
    _deal();
    chooser = _seatWith(const JassCard(Suit.karo, Rank.seven));
    _beginChoosing();
  }

  /// Nächste Runde: Das Trumpfrecht wandert einen Platz weiter.
  void nextRound() {
    if (phase != Phase.roundOver) {
      throw StateError('Runde ist noch nicht fertig');
    }
    _deal();
    chooser = nextSeat(chooser);
    _beginChoosing();
  }

  /// Für Tests: Runde mit vorgegebenen Händen starten.
  void startWithHands(List<List<JassCard>> fixedHands, {int chooserSeat = 0}) {
    hands = [for (final h in fixedHands) List.of(h)];
    _resetRound();
    chooser = chooserSeat;
    _beginChoosing();
  }

  void _deal() {
    final deck = List.of(fullDeck)..shuffle(_rng);
    hands = [
      for (var i = 0; i < 4; i++) (deck.sublist(i * 9, i * 9 + 9)..sort()),
    ];
    _resetRound();
  }

  void _resetRound() {
    roundNumber++;
    geschoben = false;
    mode = null;
    trick.clear();
    trickSeats.clear();
    tricks.clear();
    for (final l in [roundCardPoints, roundWeis, roundStoeck]) {
      l[0] = 0;
      l[1] = 0;
    }
    announcements = [];
    weisWinnerTeam = null;
    stoeckSeat = null;
    stoeckAnnounced = false;
    lastResult = null;
  }

  void _beginChoosing() {
    phase = Phase.chooseMode;
    toAct = chooser;
  }

  int _seatWith(JassCard card) => hands.indexWhere((h) => h.contains(card));

  /// Darf die Person am Zug noch schieben?
  bool get canSchieben => phase == Phase.chooseMode && !geschoben;

  /// Trumpf an den Partner weitergeben.
  void schieben() {
    if (!canSchieben) throw StateError('Schieben nicht möglich');
    geschoben = true;
    toAct = partnerOf(chooser);
  }

  /// Spielart festlegen. Danach spielt [chooser] aus.
  void chooseMode(GameMode m) {
    if (phase != Phase.chooseMode) throw StateError('Keine Trumpfwahl jetzt');
    mode = m;
    phase = Phase.playing;
    toAct = chooser;
    _evaluateWeis();
    final s = hands.indexWhere((h) => hasStoeck(h, m));
    stoeckSeat = s >= 0 ? s : null;
  }

  void _evaluateWeis() {
    final m = mode!;
    announcements = [];
    Weis? best;
    int? bestSeat;
    // In Spielreihenfolge prüfen: Bei Gleichstand gewinnt, wer früher dran ist.
    var seat = chooser;
    for (var i = 0; i < 4; i++) {
      final weise = findWeis(hands[seat]);
      if (weise.isNotEmpty) {
        announcements.add(WeisAnnouncement(seat, weise));
        for (final w in weise) {
          if (best == null || compareWeis(w, best, m) > 0) {
            best = w;
            bestSeat = seat;
          }
        }
      }
      seat = nextSeat(seat);
    }
    weisWinnerTeam = bestSeat == null ? null : teamOf(bestSeat);
  }

  /// Karten, die der Sitz [seat] jetzt spielen darf.
  List<JassCard> legalFor(int seat) {
    if (phase != Phase.playing || seat != toAct) return const [];
    return legalCards(hands[seat], trick, mode!);
  }

  /// Karte spielen. Wirft einen Fehler bei ungültigem Zug.
  void playCard(int seat, JassCard card) {
    if (phase != Phase.playing) throw StateError('Gerade nicht spielbar');
    if (seat != toAct) throw StateError('Sitz $seat ist nicht am Zug');
    if (!legalFor(seat).contains(card)) {
      throw ArgumentError('$card ist nicht erlaubt');
    }
    hands[seat].remove(card);
    trick.add(card);
    trickSeats.add(seat);

    // Stöck wird gezählt, sobald die zweite der beiden Karten gespielt ist.
    if (seat == stoeckSeat &&
        !stoeckAnnounced &&
        mode!.isTrumpCard(card) &&
        (card.rank == Rank.king || card.rank == Rank.queen)) {
      final other = card.rank == Rank.king ? Rank.queen : Rank.king;
      if (!hands[seat].contains(JassCard(card.suit, other))) {
        stoeckAnnounced = true;
        final pts = 20 * multiplier;
        roundStoeck[teamOf(seat)] += pts;
        if (_addPoints(teamOf(seat), pts)) return;
      }
    }

    if (trick.length == 4) {
      phase = Phase.trickComplete;
      toAct = trickSeats[mode!.winningIndex(trick)];
    } else {
      toAct = nextSeat(seat);
    }
  }

  /// Wer gewinnt den Stich, der gerade liegt?
  int? get currentTrickWinner =>
      trick.isEmpty ? null : trickSeats[mode!.winningIndex(trick)];

  /// Stich einziehen und weiterspielen (oder Runde abrechnen).
  void collectTrick() {
    if (phase != Phase.trickComplete) throw StateError('Kein voller Stich');
    final m = mode!;
    final winner = trickSeats[m.winningIndex(trick)];
    var pts = trick.fold<int>(0, (s, c) => s + m.points(c));
    final isLast = tricks.length == 8;
    if (isLast) pts += 5;
    tricks.add(
      CompletedTrick(List.of(trick), List.of(trickSeats), winner, pts),
    );
    roundCardPoints[teamOf(winner)] += pts;
    trick.clear();
    trickSeats.clear();

    // Weis wird nach dem ersten Stich gutgeschrieben.
    if (tricks.length == 1 && weisWinnerTeam != null) {
      final team = weisWinnerTeam!;
      final raw = announcements
          .where((a) => teamOf(a.seat) == team)
          .fold<int>(0, (s, a) => s + a.total);
      roundWeis[team] = raw * multiplier;
      phase = Phase.playing;
      if (_addPoints(team, roundWeis[team])) return;
    }

    if (isLast) {
      _finishRound();
    } else {
      phase = Phase.playing;
      toAct = winner;
    }
  }

  /// Punkte gutschreiben. Gibt true zurück, wenn das Spiel damit endet.
  bool _addPoints(int team, int pts) {
    totals[team] += pts;
    if (totals[team] >= settings.targetPoints) {
      winnerTeam = team;
      phase = Phase.gameOver;
      lastResult = _buildResult();
      history.add(lastResult!);
      return true;
    }
    return false;
  }

  RoundResult _buildResult() {
    final m = mode!;
    int? matchTeam;
    final cards = List.of(roundCardPoints);
    if (tricks.length == 9) {
      for (final t in [0, 1]) {
        if (tricks.every((tr) => teamOf(tr.winner) == t)) {
          matchTeam = t;
          cards[t] = 257;
          cards[1 - t] = 0;
        }
      }
    }
    return RoundResult(
      mode: m,
      multiplier: settings.multiplierFor(m),
      cardPoints: cards,
      weisPoints: List.of(roundWeis),
      stoeckPoints: List.of(roundStoeck),
      matchTeam: matchTeam,
    );
  }

  void _finishRound() {
    final result = _buildResult();
    lastResult = result;
    history.add(result);
    for (final t in [0, 1]) {
      totals[t] += result.cardPoints[t] * result.multiplier;
    }
    final reached = [0, 1].where((t) => totals[t] >= settings.targetPoints);
    if (reached.isNotEmpty) {
      // Annahme: Erreichen beide Teams das Ziel erst mit den Kartenpunkten,
      // gewinnt das Team mit mehr Punkten.
      winnerTeam = reached.length == 1
          ? reached.first
          : (totals[0] >= totals[1] ? 0 : 1);
      phase = Phase.gameOver;
    } else {
      phase = Phase.roundOver;
    }
  }

  /// Alle Karten, die in dieser Runde schon gespielt wurden
  /// (das darf sich jede Person merken).
  List<JassCard> get playedCards => [
    for (final t in tricks) ...t.cards,
    ...trick,
  ];

  /// Sicht eines Sitzes auf das Spiel: nur die eigenen Karten.
  PlayerView viewFor(int seat) => PlayerView(
    seat: seat,
    hand: List.unmodifiable(hands[seat]),
    trick: List.unmodifiable(trick),
    trickSeats: List.unmodifiable(trickSeats),
    mode: mode,
    chooser: chooser,
    geschoben: geschoben,
    playedCards: List.unmodifiable(playedCards),
    legal: legalFor(seat),
    handSizes: [for (final h in hands) h.length],
    pastTricks: List.unmodifiable(tricks),
  );
}

/// Alles, was ein Sitz wissen darf. Computergegner bekommen nur das.
class PlayerView {
  PlayerView({
    required this.seat,
    required this.hand,
    required this.trick,
    required this.trickSeats,
    required this.mode,
    required this.chooser,
    required this.geschoben,
    required this.playedCards,
    required this.legal,
    required this.handSizes,
    this.pastTricks = const [],
  });

  final int seat;
  final List<JassCard> hand;
  final List<JassCard> trick;
  final List<int> trickSeats;
  final GameMode? mode;
  final int chooser;
  final bool geschoben;
  final List<JassCard> playedCards;
  final List<JassCard> legal;
  final List<int> handSizes;

  /// Fertige Stiche dieser Runde (wer welche Karte gespielt hat).
  final List<CompletedTrick> pastTricks;
}

// ------------------------------------------------------------- Speichern
//
// Der ganze Spielstand als einfache Map (JSON), damit ein angefangenes
// Spiel nach dem Schliessen der App weitergeht.

List<int> _ids(List<JassCard> cs) => [for (final c in cs) c.id];
List<JassCard> _cards(dynamic l) => [
  for (final i in (l as List)) JassCard.fromId(i as int),
];
List<int> _ints(dynamic l) => [for (final i in (l as List)) i as int];

Map<String, dynamic> modeToJson(GameMode m) => {
  't': m.type.index,
  if (m.trumpSuit != null) 's': m.trumpSuit!.index,
};

GameMode modeFromJson(Map<String, dynamic> j) =>
    switch (ModeType.values[j['t'] as int]) {
      ModeType.trump => GameMode.trump(Suit.values[j['s'] as int]),
      ModeType.obenabe => const GameMode.obenabe(),
      ModeType.undenufe => const GameMode.undenufe(),
    };

Map<String, dynamic> _weisToJson(Weis w) => {
  'c': _ids(w.cards),
  'p': w.points,
  'q': w.isSequence,
};
Weis _weisFromJson(Map<String, dynamic> j) =>
    Weis(_cards(j['c']), j['p'] as int, isSequence: j['q'] as bool);

Map<String, dynamic> _resultToJson(RoundResult r) => {
  'm': modeToJson(r.mode),
  'x': r.multiplier,
  'c': r.cardPoints,
  'w': r.weisPoints,
  's': r.stoeckPoints,
  if (r.matchTeam != null) 'mt': r.matchTeam,
};
RoundResult _resultFromJson(Map<String, dynamic> j) => RoundResult(
  mode: modeFromJson(Map<String, dynamic>.from(j['m'] as Map)),
  multiplier: j['x'] as int,
  cardPoints: _ints(j['c']),
  weisPoints: _ints(j['w']),
  stoeckPoints: _ints(j['s']),
  matchTeam: j['mt'] as int?,
);

extension SchieberSave on SchieberGame {
  Map<String, dynamic> toJson() => {
    'v': 1,
    'target': settings.targetPoints,
    'mult': settings.useMultipliers,
    'totals': totals,
    'history': [for (final r in history) _resultToJson(r)],
    'round': roundNumber,
    'winner': winnerTeam,
    'phase': phase.index,
    'hands': [for (final h in hands) _ids(h)],
    'chooser': chooser,
    'geschoben': geschoben,
    if (mode != null) 'mode': modeToJson(mode!),
    'toAct': toAct,
    'trick': _ids(trick),
    'trickSeats': trickSeats,
    'tricks': [
      for (final t in tricks)
        {'c': _ids(t.cards), 's': t.seats, 'w': t.winner, 'p': t.points},
    ],
    'rcp': roundCardPoints,
    'rw': roundWeis,
    'rs': roundStoeck,
    'ann': [
      for (final a in announcements)
        {
          'seat': a.seat,
          'w': [for (final w in a.weise) _weisToJson(w)],
        },
    ],
    'wwt': weisWinnerTeam,
    'ss': stoeckSeat,
    'sa': stoeckAnnounced,
    if (lastResult != null) 'last': _resultToJson(lastResult!),
  };

  static SchieberGame fromJson(Map<String, dynamic> j) {
    final g = SchieberGame(
      settings: SchieberSettings(
        targetPoints: j['target'] as int,
        useMultipliers: j['mult'] as bool,
      ),
    );
    Map<String, dynamic> m(dynamic x) => Map<String, dynamic>.from(x as Map);
    final t = _ints(j['totals']);
    g.totals
      ..[0] = t[0]
      ..[1] = t[1];
    g.history.addAll([
      for (final r in j['history'] as List) _resultFromJson(m(r)),
    ]);
    g.roundNumber = j['round'] as int;
    g.winnerTeam = j['winner'] as int?;
    g.phase = Phase.values[j['phase'] as int];
    g.hands = [for (final h in j['hands'] as List) _cards(h)];
    g.chooser = j['chooser'] as int;
    g.geschoben = j['geschoben'] as bool;
    g.mode = j['mode'] == null ? null : modeFromJson(m(j['mode']));
    g.toAct = j['toAct'] as int;
    g.trick.addAll(_cards(j['trick']));
    g.trickSeats.addAll(_ints(j['trickSeats']));
    for (final tr in j['tricks'] as List) {
      final x = m(tr);
      g.tricks.add(
        CompletedTrick(
          _cards(x['c']),
          _ints(x['s']),
          x['w'] as int,
          x['p'] as int,
        ),
      );
    }
    void copy(List<int> to, dynamic from) {
      final f = _ints(from);
      to[0] = f[0];
      to[1] = f[1];
    }

    copy(g.roundCardPoints, j['rcp']);
    copy(g.roundWeis, j['rw']);
    copy(g.roundStoeck, j['rs']);
    g.announcements = [
      for (final a in j['ann'] as List)
        WeisAnnouncement(m(a)['seat'] as int, [
          for (final w in m(a)['w'] as List) _weisFromJson(m(w)),
        ]),
    ];
    g.weisWinnerTeam = j['wwt'] as int?;
    g.stoeckSeat = j['ss'] as int?;
    g.stoeckAnnounced = j['sa'] as bool;
    g.lastResult = j['last'] == null ? null : _resultFromJson(m(j['last']));
    return g;
  }
}
