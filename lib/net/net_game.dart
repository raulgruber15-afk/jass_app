import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/schieber.dart';
import '../ui/game_controller.dart';

/// Spiel über mehrere Handys im selben WLAN oder Hotspot.
///
/// Ein Handy ist Gastgeber: Es rechnet das ganze Spiel (wie allein) und
/// schickt jedem Mitspieler nur, was dieser sehen darf. Die Mitspieler
/// schicken nur ihre Züge zurück. Es braucht weder Internet noch Server.
///
/// Nachrichten sind JSON, eine pro Zeile, über eine TCP-Verbindung.
const int jassPort = 47474;
const int protocolVersion = 1;

/// Was das Spielfeld vom Netz wissen muss (Gastgeber oder Mitspieler).
abstract class NetSession implements Listenable {
  /// Problem mit der Verbindung (dann Hinweis zeigen), sonst null.
  String? get problem;
  bool get isHost;
  Future<void> close();
}

/// Inhalt des QR-Codes: «jass1|192.168.1.5,172.20.10.1|47474».
String joinCode(List<String> addresses, int port) =>
    'jass$protocolVersion|${addresses.join(',')}|$port';

/// QR-Code oder eingetippte Adresse lesen. Gibt (Adressen, Port) zurück.
(List<String>, int)? parseJoinCode(String raw) {
  final t = raw.trim();
  if (t.startsWith('jass')) {
    final parts = t.split('|');
    if (parts.length != 3) return null;
    final port = int.tryParse(parts[2]);
    final ips = parts[1].split(',').where((s) => s.isNotEmpty).toList();
    if (port == null || ips.isEmpty) return null;
    return (ips, port);
  }
  // Von Hand eingetippt: «192.168.1.5» oder «192.168.1.5:47474».
  final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d+))?$').firstMatch(t);
  if (m == null) return null;
  return ([m.group(1)!], int.tryParse(m.group(2) ?? '') ?? jassPort);
}

/// IPv4-Adressen dieses Handys im lokalen Netz (WLAN, Hotspot).
Future<List<String>> localAddresses() async {
  try {
    final list = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final ips = [
      for (final i in list)
        for (final a in i.addresses)
          if (!a.address.startsWith('169.254.')) a.address,
    ];
    int rank(String ip) {
      if (ip.startsWith('192.168.')) return 0;
      if (ip.startsWith('172.20.10.')) return 1; // iPhone-Hotspot
      if (ip.startsWith('10.')) return 2;
      return 3;
    }

    ips.sort((a, b) => rank(a).compareTo(rank(b)));
    return ips.toSet().toList();
  } catch (_) {
    return [];
  }
}

/// Eine Leitung mit Zeilen-JSON in beide Richtungen.
class NetLine {
  NetLine(this.socket, {required this.onMessage, required this.onClosed}) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) {
            lastHeard = DateTime.now();
            try {
              final msg = jsonDecode(line);
              if (msg is Map) onMessage(Map<String, dynamic>.from(msg));
            } catch (_) {
              // Unlesbare Zeile: ignorieren.
            }
          },
          onDone: _closed,
          onError: (_) => _closed(),
          cancelOnError: true,
        );
  }

  final Socket socket;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function() onClosed;
  late final StreamSubscription<String> _sub;
  DateTime lastHeard = DateTime.now();
  bool _open = true;

  bool get isOpen => _open;

  void send(Map<String, dynamic> msg) {
    if (!_open) return;
    try {
      socket.write('${jsonEncode(msg)}\n');
    } catch (_) {
      _closed();
    }
  }

  void _closed() {
    if (!_open) return;
    _open = false;
    onClosed();
  }

  Future<void> close() async {
    _open = false;
    await _sub.cancel();
    try {
      await socket.close();
    } catch (_) {}
    socket.destroy();
  }
}

// ======================================================================
// Gastgeber
// ======================================================================

class GuestSlot {
  GuestSlot(this.seat, this.name);
  final int seat;
  final String name;
  NetLine? line;
  bool get connected => line?.isOpen ?? false;
}

/// Das Handy, das das Spiel eröffnet.
class JassHost extends ChangeNotifier implements NetSession {
  JassHost({required this.hostName, this.port = jassPort});

  final String hostName;
  final int port;

  /// Reihenfolge, in der Mitspieler Plätze bekommen: zuerst der Partner.
  static const seatOrder = [2, 1, 3];

  ServerSocket? _server;
  List<String> addresses = [];
  int boundPort = 0;
  final Map<int, GuestSlot> guests = {};
  final List<NetLine> _pending = [];
  GameController? ctrl;
  Timer? _ticker;
  bool _closed = false;

  @override
  bool get isHost => true;

  @override
  String? problem;

  String get code => joinCode(addresses, boundPort);

  /// Server öffnen. Gibt false zurück, wenn es nicht geht.
  Future<bool> open() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (e) {
        problem = 'Das Spiel konnte nicht eröffnet werden.';
        notifyListeners();
        return false;
      }
    }
    boundPort = _server!.port;
    addresses = await localAddresses();
    if (addresses.isEmpty) {
      problem =
          'Kein WLAN gefunden. Verbinde dich mit einem WLAN oder schalte den '
          'Hotspot ein.';
    }
    _server!.listen(_accept, onError: (_) {});
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    notifyListeners();
    return true;
  }

  /// Adressen neu suchen (z. B. nachdem der Hotspot eingeschaltet wurde).
  Future<void> refreshAddresses() async {
    addresses = await localAddresses();
    problem = addresses.isEmpty
        ? 'Kein WLAN gefunden. Verbinde dich mit einem WLAN oder schalte den '
              'Hotspot ein.'
        : null;
    notifyListeners();
  }

  /// Namen an den vier Plätzen für die Wartehalle (null = frei).
  List<String?> get lobbyNames => [
    hostName,
    for (var s = 1; s < 4; s++) guests[s]?.name,
  ];

  bool get started => ctrl != null;

  void _accept(Socket socket) {
    late NetLine line;
    line = NetLine(
      socket,
      onMessage: (m) => _onMessage(line, m),
      onClosed: () => _onClosed(line),
    );
    _pending.add(line);
  }

  void _onMessage(NetLine line, Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hello':
        _hello(line, m);
      case 'act':
        final g = _guestOf(line);
        if (g != null && ctrl != null) {
          ctrl!.remoteAction(
            g.seat,
            Map<String, dynamic>.from(m['act'] as Map),
          );
        }
      case 'leave':
        line.close();
        _onClosed(line);
    }
  }

  GuestSlot? _guestOf(NetLine line) {
    for (final g in guests.values) {
      if (identical(g.line, line)) return g;
    }
    return null;
  }

  void _hello(NetLine line, Map<String, dynamic> m) {
    _pending.remove(line);
    if ((m['v'] as int?) != protocolVersion) {
      line.send({
        't': 'bye',
        'reason':
            'Die App-Versionen passen nicht zusammen. Bitte beide '
            'Handys aktualisieren.',
      });
      line.close();
      return;
    }
    var name = (m['name'] as String? ?? '').trim();
    if (name.isEmpty) name = 'Gast';
    if (name.length > 14) name = name.substring(0, 14);

    // Wieder da nach Verbindungsabbruch? Dann den alten Platz zurück.
    GuestSlot? g;
    for (final x in guests.values) {
      if (!x.connected && x.name.toLowerCase() == name.toLowerCase()) g = x;
    }
    if (g == null) {
      if (started) {
        line.send({'t': 'bye', 'reason': 'Das Spiel läuft schon.'});
        line.close();
        return;
      }
      final free = seatOrder.where((s) => !guests.containsKey(s));
      if (free.isEmpty) {
        line.send({'t': 'bye', 'reason': 'Der Tisch ist schon voll.'});
        line.close();
        return;
      }
      // Gleicher Name wie jemand anderes: Nummer anhängen.
      final taken = lobbyNames.whereType<String>().map((n) => n.toLowerCase());
      var unique = name;
      for (var i = 2; taken.contains(unique.toLowerCase()); i++) {
        unique = '$name $i';
      }
      g = GuestSlot(free.first, unique);
      guests[g.seat] = g;
    }
    g.line = line;
    line.send({'t': 'welcome', 'seat': g.seat, 'name': g.name});
    if (started) {
      ctrl!.seatToRemote(g.seat); // sendet auch gleich den Stand
    }
    _sendLobby();
    notifyListeners();
  }

  void _onClosed(NetLine line) {
    _pending.remove(line);
    final g = _guestOf(line);
    if (g == null || _closed) return;
    g.line = null;
    if (started) {
      ctrl!.seatToBot(g.seat);
    } else {
      guests.remove(g.seat);
      _sendLobby();
    }
    notifyListeners();
  }

  void _sendLobby() {
    final msg = {'t': 'lobby', 'names': lobbyNames};
    for (final g in guests.values) {
      g.line?.send(msg);
    }
  }

  /// Mitspieler entfernen (vor dem Start).
  void kick(int seat) {
    final g = guests.remove(seat);
    g?.line?.send({'t': 'bye', 'reason': 'Der Gastgeber hat dich entfernt.'});
    g?.line?.close();
    _sendLobby();
    notifyListeners();
  }

  /// Spiel starten. Freie Plätze übernimmt der Computer.
  GameController start({
    required SchieberSettings settings,
    required BotLevel level,
    required bool fast,
  }) {
    final seats = <SeatSetup>[
      SeatSetup(name: hostName, human: true),
      for (var s = 1; s < 4; s++)
        guests[s]?.connected ?? false
            ? SeatSetup(name: guests[s]!.name, human: true, remote: true)
            : SeatSetup(name: defaultSeats[s].name, human: false),
    ];
    // Wer nicht mehr verbunden ist, fliegt aus der Liste.
    guests.removeWhere((_, g) => !g.connected);
    ctrl = GameController(
      settings: settings,
      level: level,
      fast: fast,
      seats: seats,
      onBroadcast: _broadcast,
    );
    for (final g in guests.values) {
      g.line?.send({'t': 'start'});
    }
    ctrl!.start();
    notifyListeners();
    return ctrl!;
  }

  void _broadcast() {
    final c = ctrl;
    if (c == null) return;
    for (final g in guests.values) {
      if (g.connected) g.line!.send({'t': 'state', ...c.stateFor(g.seat)});
    }
  }

  void _tick() {
    final now = DateTime.now();
    for (final g in guests.values.toList()) {
      final l = g.line;
      if (l == null) continue;
      l.send({'t': 'ping'});
      // 15 Sekunden nichts gehört: Verbindung gilt als weg.
      if (now.difference(l.lastHeard) > const Duration(seconds: 15)) {
        l.close();
        _onClosed(l);
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ticker?.cancel();
    for (final g in guests.values) {
      g.line?.send({
        't': 'bye',
        'reason': 'Der Gastgeber hat das Spiel beendet.',
      });
      await g.line?.close();
    }
    for (final l in _pending) {
      await l.close();
    }
    await _server?.close();
    ctrl?.dispose();
  }
}

// ======================================================================
// Mitspieler
// ======================================================================

/// Ein Handy, das einem Spiel beitritt.
class JassGuest extends ChangeNotifier implements NetSession {
  JassGuest({required this.name});

  final String name;
  NetLine? _line;
  Timer? _ticker;
  bool _closed = false;

  /// Zum Wiederverbinden.
  List<String> _hosts = [];
  int _port = jassPort;

  int? seat;
  String? myName;
  List<String?> lobbyNames = [null, null, null, null];
  bool started = false;
  GameController? ctrl;

  @override
  bool get isHost => false;

  @override
  String? problem;

  /// Verbindung aufbauen. Probiert alle Adressen aus dem QR-Code.
  Future<bool> connect(List<String> hosts, int port) async {
    _hosts = hosts;
    _port = port;
    problem = null;
    _closed = false;
    notifyListeners();
    Socket? socket;
    for (final h in hosts) {
      try {
        socket = await Socket.connect(
          h,
          port,
          timeout: const Duration(seconds: 4),
        );
        break;
      } catch (_) {}
    }
    if (socket == null) {
      problem =
          'Keine Verbindung zum Gastgeber. Seid ihr im gleichen WLAN oder '
          'Hotspot?';
      notifyListeners();
      return false;
    }
    _line = NetLine(socket, onMessage: _onMessage, onClosed: _onClosed);
    _line!.send({'t': 'hello', 'v': protocolVersion, 'name': myName ?? name});
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    return true;
  }

  /// Nach Abbruch neu verbinden; der Platz bleibt erhalten.
  Future<bool> reconnect() => connect(_hosts, _port);

  void _onMessage(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'welcome':
        seat = m['seat'] as int;
        myName = m['name'] as String;
        problem = null;
      case 'lobby':
        lobbyNames = [for (final n in m['names'] as List) n as String?];
      case 'start':
        started = true;
      case 'state':
        started = true;
        _applyState(m);
      case 'bye':
        problem = m['reason'] as String? ?? 'Das Spiel wurde beendet.';
        _closed = true;
        _line?.close();
        _ticker?.cancel();
      case 'ping':
        _line?.send({'t': 'pong'});
        return; // nichts Neues zu zeigen
    }
    notifyListeners();
  }

  void _applyState(Map<String, dynamic> m) {
    final mySeat = seat;
    if (mySeat == null) return;
    var c = ctrl;
    if (c == null) {
      final game = SchieberSave.fromJson(
        Map<String, dynamic>.from(m['game'] as Map),
      );
      final names = m['seats'] as List;
      c = GameController(
        settings: game.settings,
        resumeFrom: game,
        seats: [
          for (var s = 0; s < 4; s++)
            SeatSetup(
              name: (names[s] as Map)['name'] as String,
              human: (names[s] as Map)['human'] as bool,
              remote: s != mySeat && (names[s] as Map)['human'] as bool,
            ),
        ],
        sendAction: (a) => _line?.send({'t': 'act', 'act': a}),
      );
      // Eigenen Platz zeigen, auch wenn er gerade nicht «Mensch» heisst.
      c.viewer = mySeat;
      c.handHidden = false;
      ctrl = c;
    }
    c.applyRemoteState(m);
  }

  void _onClosed() {
    _ticker?.cancel();
    if (_closed) return;
    problem ??= 'Verbindung zum Gastgeber unterbrochen.';
    notifyListeners();
  }

  void _tick() {
    final l = _line;
    if (l == null) return;
    l.send({'t': 'ping'});
    if (DateTime.now().difference(l.lastHeard) > const Duration(seconds: 15)) {
      l.close();
      _onClosed();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _ticker?.cancel();
    _line?.send({'t': 'leave'});
    await _line?.close();
    ctrl?.dispose();
  }
}
