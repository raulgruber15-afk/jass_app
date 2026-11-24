import 'package:flutter/material.dart';

import '../engine/schieber.dart';
import 'game_controller.dart';

/// Jasstafel: alle Runden mit Spielart und Punkten, wie auf der
/// Kreidetafel im Restaurant.
class JasstafelScreen extends StatelessWidget {
  const JasstafelScreen({super.key, required this.ctrl});
  final GameController ctrl;

  static const _board = Color(0xFF22302A);
  static const _frame = Color(0xFF8A6A3F);
  static const _chalk = Color(0xFFEDEBE3);
  static const _chalkDim = Color(0xFFA9ADA4);
  static const _chalkGold = Color(0xFFE2C27A);

  @override
  Widget build(BuildContext context) {
    final g = ctrl.game;
    final target = g.settings.targetPoints;
    final rows = <_Row>[];
    for (var i = 0; i < g.history.length; i++) {
      final r = g.history[i];
      rows.add(_Row(i + 1, r, r.scoreFor(0), r.scoreFor(1)));
    }
    // Laufende Runde: bisher gezählte Weis/Stöck sind schon im Total.
    final running = g.phase == Phase.playing || g.phase == Phase.trickComplete;

    const head = TextStyle(color: _chalkDim, fontSize: 13, letterSpacing: 0.5);
    const cell = TextStyle(
      color: _chalk,
      fontSize: 16,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    const bold = TextStyle(
      color: _chalk,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    Widget line(List<Widget> cs) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 34, child: cs[0]),
          Expanded(child: cs[1]),
          SizedBox(
            width: 78,
            child: Align(alignment: Alignment.centerRight, child: cs[2]),
          ),
          SizedBox(
            width: 78,
            child: Align(alignment: Alignment.centerRight, child: cs[3]),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: _frame,
      appBar: AppBar(
        backgroundColor: _frame,
        foregroundColor: _chalk,
        title: const Text('Jasstafel'),
      ),
      body: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _board,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fortschritt bis zum Ziel
              for (final t in [0, 1])
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ctrl.teamLabel(t),
                              style: const TextStyle(
                                color: _chalk,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '${g.totals[t]} / $target',
                            style: const TextStyle(color: _chalkDim),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (g.totals[t] / target).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.white10,
                          color: t == ctrl.viewer % 2 ? _chalkGold : _chalk,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(color: _chalkDim),
              line([
                const Text('#', style: head),
                const Text('Spiel', style: head),
                Text(
                  _short(ctrl.teamLabel(0)),
                  style: head,
                  textAlign: TextAlign.right,
                ),
                Text(
                  _short(ctrl.teamLabel(1)),
                  style: head,
                  textAlign: TextAlign.right,
                ),
              ]),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text(
                          'Noch keine Runde fertig.',
                          style: TextStyle(color: _chalkDim),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final r in rows)
                            line([
                              Text(
                                '${r.nr}',
                                style: const TextStyle(color: _chalkDim),
                              ),
                              Text(
                                '${r.result.mode.symbol} ${r.result.mode.label}'
                                '${r.result.multiplier > 1 ? ' ×${r.result.multiplier}' : ''}'
                                '${r.result.matchTeam != null ? '  Match!' : ''}',
                                style: const TextStyle(
                                  color: _chalk,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text('${r.a}', style: cell),
                              Text('${r.b}', style: cell),
                            ]),
                        ],
                      ),
              ),
              const Divider(color: _chalkDim),
              if (running &&
                  (g.roundWeis.any((p) => p > 0) ||
                      g.roundStoeck.any((p) => p > 0)))
                line([
                  const SizedBox(),
                  const Text(
                    'Weis/Stöck jetzt',
                    style: TextStyle(color: _chalkDim, fontSize: 13),
                  ),
                  Text('${g.roundWeis[0] + g.roundStoeck[0]}', style: cell),
                  Text('${g.roundWeis[1] + g.roundStoeck[1]}', style: cell),
                ]),
              line([
                const SizedBox(),
                const Text('Total', style: bold),
                Text('${g.totals[0]}', style: bold),
                Text('${g.totals[1]}', style: bold),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  static String _short(String s) => s.length <= 9 ? s : '${s.substring(0, 8)}…';
}

class _Row {
  _Row(this.nr, this.result, this.a, this.b);
  final int nr;
  final RoundResult result;
  final int a;
  final int b;
}
