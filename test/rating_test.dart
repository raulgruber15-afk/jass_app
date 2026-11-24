import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jass/engine/rating.dart';

void main() {
  const s = SkillEstimate(mu: 0, variance: 0.01);

  test('Striche aus Punkten: 10 % des Ziels = 1 Strich, begrenzt', () {
    expect(
      JassRating.marginFromPoints(2500, 2000, 2500, won: true),
      closeTo(2, 1e-9),
    );
    expect(
      JassRating.marginFromPoints(2510, 2500, 2500, won: true),
      1,
    ); // mindestens 1
    expect(
      JassRating.marginFromPoints(2600, 0, 2500, won: true),
      7,
    ); // höchstens 7
    expect(JassRating.marginFromPoints(1000, 2500, 2500, won: false), -6);
  });

  test('Sieg hebt die eigene Wertung, Niederlage senkt sie', () {
    final (a, _) = JassRating.update(
      [JassRating.prior, s],
      [s, s],
      3,
      fixedA: [false, true],
      fixedB: [true, true],
    );
    expect(a[0].mu, greaterThan(0));
    expect(a[0].variance, lessThan(JassRating.prior.variance));
    expect(a[1], same(s)); // Computer bleibt fest
    final (c, _) = JassRating.update(
      [JassRating.prior, s],
      [s, s],
      -3,
      fixedA: [false, true],
      fixedB: [true, true],
    );
    expect(c[0].mu, lessThan(0));
  });

  test('Knapper Sieg gegen viel Schwächere kostet Punkte, Maximum nie', () {
    const weak = SkillEstimate(mu: -1.5, variance: 0.01);
    const me = SkillEstimate(mu: 0, variance: 0.2);
    final (a, _) = JassRating.update(
      [me, weak],
      [weak, weak],
      1,
      fixedA: [false, true],
      fixedB: [true, true],
    );
    expect(a[0].mu, lessThan(0));
    const strong = SkillEstimate(mu: 3, variance: 0.2);
    final (b, _) = JassRating.update(
      [strong, weak],
      [weak, weak],
      7,
      fixedA: [false, true],
      fixedB: [true, true],
    );
    expect(b[0].mu, greaterThanOrEqualTo(strong.mu));
  });

  test('Online: Nullsumme bei gleicher Unsicherheit', () {
    const p = SkillEstimate(mu: 0.3, variance: 0.1);
    final (a, b) = JassRating.update([p, p], [p, p], 2);
    final sum =
        a.fold(0.0, (x, e) => x + e.mu) + b.fold(0.0, (x, e) => x + e.mu);
    expect(sum, closeTo(4 * p.mu, 1e-9));
  });

  test('Wertung findet die wahre Stärke gegen Computer', () {
    const bot = SkillEstimate(mu: 0, variance: 0.0025);
    final rng = Random(1);
    for (final truth in [-0.8, 0.0, 0.7]) {
      var me = JassRating.prior;
      for (var i = 0; i < 400; i++) {
        final d = JassRating.gain * truth + JassRating.noise * _gauss(rng);
        final m = d.clamp(-7.0, 7.0).toDouble();
        final won = m > 0;
        final margin = won ? max(m, 1.0) : min(m, -1.0);
        final (a, _) = JassRating.update(
          [me, bot],
          [bot, bot],
          margin,
          fixedA: [false, true],
          fixedB: [true, true],
        );
        me = a[0];
      }
      expect(me.mu, closeTo(truth, 0.35), reason: 'wahr $truth');
    }
  });

  test('Siegchance passt zur Stärke', () {
    const a = SkillEstimate(mu: 1, variance: 0.01);
    expect(JassRating.winProbability([a, s], [s, s]), greaterThan(0.6));
    expect(JassRating.winProbability([s, s], [s, s]), closeTo(0.5, 1e-6));
  });

  test('Speichern und Laden', () {
    const e = SkillEstimate(mu: 0.42, variance: 0.13);
    final r = SkillEstimate.fromJson(e.toJson());
    expect(r.mu, e.mu);
    expect(r.variance, e.variance);
  });

  test('Allein gegen Computer: vorläufig, Bestwert, Änderung', () {
    var r = const SoloRating();
    expect(r.value, 1000);
    for (var i = 0; i < JassRating.provisionalGames; i++) {
      expect(r.provisional, isTrue);
      r = r.afterGame(
        level: 'stammtisch',
        ownPoints: 2500,
        oppPoints: 1800,
        target: 2500,
        won: true,
      );
      expect(r.lastChange, greaterThan(0));
    }
    expect(r.provisional, isFalse);
    expect(r.best, r.value);
    final back = SoloRating.fromJson(r.toJson());
    expect(back.value, r.value);
    expect(back.games, r.games);
  });
}

double _gauss(Random r) {
  final u = 1 - r.nextDouble(), v = r.nextDouble();
  return sqrt(-2 * log(u)) * cos(2 * pi * v);
}
