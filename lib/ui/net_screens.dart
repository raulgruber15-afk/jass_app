import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../engine/schieber.dart';
import '../net/net_game.dart';
import 'game_controller.dart';
import 'game_screen.dart';
import 'theme.dart';

const _seatLabels = ['Du', 'Rechts', 'Partner (gegenüber)', 'Links'];

/// Gemeinsamer Hintergrund wie auf der Startseite.
class _Felt extends StatelessWidget {
  const _Felt({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: JassColors.feltDark),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF2A6350), JassColors.felt, JassColors.feltDark],
            stops: [0, 0.6, 1],
            radius: 1.1,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Plätze am Tisch mit Namen (oder «wartet …» / «Computer»).
class _SeatList extends StatelessWidget {
  const _SeatList({required this.names, required this.mySeat, this.onKick});
  final List<String?> names;
  final int mySeat;
  final void Function(int seat)? onKick;

  @override
  Widget build(BuildContext context) {
    // Plätze aus Sicht dieses Handys benennen.
    String label(int seat) {
      final rel = (seat - mySeat + 4) % 4;
      return _seatLabels[rel];
    }

    return Column(
      children: [
        for (final seat in [
          mySeat,
          (mySeat + 2) % 4,
          (mySeat + 1) % 4,
          (mySeat + 3) % 4,
        ])
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  names[seat] == null ? Icons.smart_toy_outlined : Icons.person,
                  color: names[seat] == null ? Colors.white38 : JassColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: Text(
                    label(seat),
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    names[seat] ?? 'frei – Computer',
                    style: TextStyle(
                      color: names[seat] == null
                          ? Colors.white38
                          : JassColors.cream,
                      fontSize: 15,
                      fontWeight: names[seat] == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (onKick != null && seat != mySeat && names[seat] != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => onKick!(seat),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ======================================================================
// Spiel eröffnen
// ======================================================================

class HostLobbyScreen extends StatefulWidget {
  const HostLobbyScreen({
    super.key,
    required this.name,
    required this.settings,
    required this.level,
    required this.fast,
  });

  final String name;
  final SchieberSettings settings;
  final BotLevel level;
  final bool fast;

  @override
  State<HostLobbyScreen> createState() => _HostLobbyScreenState();
}

class _HostLobbyScreenState extends State<HostLobbyScreen> {
  late final JassHost host = JassHost(hostName: widget.name);
  bool _handedOver = false;

  @override
  void initState() {
    super.initState();
    host.open();
  }

  @override
  void dispose() {
    if (!_handedOver) host.close();
    super.dispose();
  }

  void _start() {
    final ctrl = host.start(
      settings: widget.settings,
      level: widget.level,
      fast: widget.fast,
    );
    _handedOver = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GameScreen.network(controller: ctrl, session: host),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Felt(
      title: 'Spiel eröffnen',
      child: ListenableBuilder(
        listenable: host,
        builder: (context, _) {
          final joined = host.guests.length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Die anderen tippen auf «Beitreten» und scannen diesen Code. '
                'Alle Handys müssen im gleichen WLAN sein oder im Hotspot '
                'dieses Handys.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (host.addresses.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: host.code,
                      size: 210,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              if (host.addresses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Ohne Kamera: Adresse ${host.addresses.first}'
                  '${host.boundPort == jassPort ? '' : ':${host.boundPort}'} eintippen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
              if (host.problem != null) ...[
                const SizedBox(height: 8),
                Text(
                  host.problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JassColors.gold, fontSize: 14),
                ),
                TextButton(
                  onPressed: host.refreshAddresses,
                  child: const Text(
                    'Nochmals suchen',
                    style: TextStyle(color: JassColors.cream),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _SeatList(names: host.lobbyNames, mySeat: 0, onKick: host.kick),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  joined == 0
                      ? 'Ohne Mitspieler starten'
                      : 'Spiel starten ($joined dabei)',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ======================================================================
// Beitreten
// ======================================================================

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.name});
  final String name;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final JassGuest guest = JassGuest(name: widget.name);
  final _address = TextEditingController();
  bool _connecting = false;
  bool _scanning = true;
  bool _handedOver = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    guest.addListener(_onGuest);
  }

  @override
  void dispose() {
    guest.removeListener(_onGuest);
    if (!_handedOver) guest.close();
    _address.dispose();
    super.dispose();
  }

  void _onGuest() {
    final c = guest.ctrl;
    if (c != null && !_handedOver && mounted) {
      _handedOver = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameScreen.network(controller: c, session: guest),
        ),
      );
    }
  }

  Future<void> _connectTo(String raw) async {
    if (_connecting || guest.seat != null) return;
    final parsed = parseJoinCode(raw);
    if (parsed == null) {
      setState(() => _hint = 'Das ist kein Jass-Code und keine Adresse.');
      return;
    }
    setState(() {
      _connecting = true;
      _scanning = false;
      _hint = null;
    });
    final ok = await guest.connect(parsed.$1, parsed.$2);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      if (!ok) _scanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Felt(
      title: 'Beitreten',
      child: ListenableBuilder(
        listenable: guest,
        builder: (context, _) {
          final seat = guest.seat;
          if (seat != null && guest.problem == null) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Du bist dabei als ${guest.myName}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: JassColors.cream,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Warte, bis der Gastgeber das Spiel startet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                const Center(
                  child: CircularProgressIndicator(color: JassColors.gold),
                ),
                const SizedBox(height: 18),
                _SeatList(names: guest.lobbyNames, mySeat: seat),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Scanne den QR-Code auf dem Handy, das das Spiel eröffnet hat. '
                'Beide Handys müssen im gleichen WLAN oder Hotspot sein.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 14),
              if (_scanning && !_connecting)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 260,
                    child: MobileScanner(
                      onDetect: (capture) {
                        for (final b in capture.barcodes) {
                          final v = b.rawValue;
                          if (v != null && v.startsWith('jass')) {
                            _connectTo(v);
                            return;
                          }
                        }
                      },
                      errorBuilder: (context, error) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Kamera nicht verfügbar. Tippe die Adresse unten ein.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_connecting)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: JassColors.gold),
                        SizedBox(height: 10),
                        Text(
                          'Verbinde …',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              if (guest.problem != null || _hint != null) ...[
                const SizedBox(height: 10),
                Text(
                  _hint ?? guest.problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JassColors.gold),
                ),
              ],
              const SizedBox(height: 18),
              const Text(
                'Oder Adresse eintippen (steht unter dem QR-Code):',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _address,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: JassColors.cream),
                      decoration: const InputDecoration(
                        hintText: 'z. B. 192.168.1.23',
                        hintStyle: TextStyle(color: Colors.white38),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: JassColors.gold),
                        ),
                      ),
                      onSubmitted: _connectTo,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _connectTo(_address.text),
                    child: const Text('Los'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
