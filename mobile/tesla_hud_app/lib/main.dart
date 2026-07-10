import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

const String dataModeName = String.fromEnvironment(
  'DATA_MODE',
  defaultValue: 'websocket',
);

const String defaultWebSocketUrl = String.fromEnvironment(
  'WS_URL',
  defaultValue: 'ws://127.0.0.1:8000/ws/vehicle',
);

const String defaultApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://127.0.0.1:8000/api/mock/vehicle',
);

void main() {
  runApp(const TeslaHudApp());
}

class TeslaHudApp extends StatelessWidget {
  const TeslaHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tesla HUD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF05070A),
        useMaterial3: true,
      ),
      home: const DashboardScreen(
        dataModeName: dataModeName,
        webSocketUrl: defaultWebSocketUrl,
        apiUrl: defaultApiUrl,
      ),
    );
  }
}

class DashboardData {
  const DashboardData({
    required this.timestamp,
    required this.speedKmh,
    required this.gear,
    required this.batteryPercent,
    required this.rangeKm,
    required this.media,
  });

  final num timestamp;
  final num speedKmh;
  final String gear;
  final num batteryPercent;
  final num rangeKm;
  final MediaInfo media;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      timestamp: json['timestamp'] as num? ?? 0,
      speedKmh: json['speed_kmh'] as num? ?? 0,
      gear: json['gear'] as String? ?? 'P',
      batteryPercent: json['battery_percent'] as num? ?? 0,
      rangeKm: json['range_km'] as num? ?? 0,
      media: MediaInfo.fromJson(
        json['media'] as Map<String, dynamic>? ?? <String, dynamic>{},
      ),
    );
  }
}

class MediaInfo {
  const MediaInfo({
    required this.title,
    required this.artist,
    required this.status,
    required this.source,
  });

  final String title;
  final String artist;
  final String status;
  final String source;

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    return MediaInfo(
      title: json['title'] as String? ?? 'Unknown title',
      artist: json['artist'] as String? ?? 'Unknown artist',
      status: json['status'] as String? ?? 'paused',
      source: json['source'] as String? ?? 'unknown',
    );
  }
}

enum DataMode {
  websocket,
  http,
  demo;

  static DataMode fromName(String name) {
    return switch (name.toLowerCase()) {
      'http' => DataMode.http,
      'demo' => DataMode.demo,
      _ => DataMode.websocket,
    };
  }
}

enum ConnectionStateLabel { loading, connected, disconnected, http, demo }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.dataModeName,
    required this.webSocketUrl,
    required this.apiUrl,
  });

  final String dataModeName;
  final String webSocketUrl;
  final String apiUrl;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _dataTimer;
  DashboardData? _dashboardData;
  ConnectionStateLabel _connectionState = ConnectionStateLabel.loading;
  String? _connectionMessage;

  DataMode get _dataMode => DataMode.fromName(widget.dataModeName);

  @override
  void initState() {
    super.initState();
    _startDataMode();
  }

  @override
  void dispose() {
    _dataTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.sink.close());
    super.dispose();
  }

  Future<void> _startDataMode() async {
    _dataTimer?.cancel();
    await _socketSubscription?.cancel();
    await _socket?.sink.close();
    _socketSubscription = null;
    _socket = null;

    switch (_dataMode) {
      case DataMode.websocket:
        await _connectWebSocket();
        return;
      case DataMode.http:
        _startHttpPolling();
        return;
      case DataMode.demo:
        _startDemoMode();
        return;
    }
  }

  Future<void> _connectWebSocket() async {
    _dataTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _connectionState = ConnectionStateLabel.loading;
      _connectionMessage = 'Connecting to vehicle stream';
    });

    try {
      debugPrint('Tesla HUD connecting to WebSocket: ${widget.webSocketUrl}');
      final socket = WebSocketChannel.connect(Uri.parse(widget.webSocketUrl));
      _socket = socket;
      await socket.ready.timeout(const Duration(seconds: 5));

      if (!mounted) {
        await socket.sink.close();
        return;
      }

      debugPrint('Tesla HUD WebSocket connected');
      setState(() {
        _connectionState = ConnectionStateLabel.connected;
        _connectionMessage = null;
      });

      _socketSubscription = socket.stream.listen(
        _handleSocketMessage,
        onDone: _handleSocketDisconnect,
        onError: (Object error) {
          debugPrint('Tesla HUD WebSocket stream error: $error');
          _handleSocketDisconnect('Connection error: $error');
        },
        cancelOnError: true,
      );
    } catch (error) {
      debugPrint('Tesla HUD WebSocket failed: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = ConnectionStateLabel.disconnected;
        _connectionMessage =
            'Unable to connect to ${widget.webSocketUrl}: $error';
      });
    }
  }

  void _handleSocketMessage(dynamic message) {
    _handleDashboardMessage(message, ConnectionStateLabel.connected);
  }

  void _handleDashboardMessage(dynamic message, ConnectionStateLabel state) {
    if (message is! String) {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(message);
    } catch (error) {
      debugPrint('Tesla HUD failed to decode dashboard payload: $error');
      return;
    }

    if (decoded is! Map<String, dynamic>) {
      debugPrint('Tesla HUD ignored non-object dashboard payload: $message');
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _dashboardData = DashboardData.fromJson(decoded);
      _connectionState = state;
      _connectionMessage = null;
    });
  }

  void _handleSocketDisconnect([String? message]) {
    debugPrint(message ?? 'Tesla HUD WebSocket disconnected');
    if (!mounted) {
      return;
    }

    setState(() {
      _connectionState = ConnectionStateLabel.disconnected;
      _connectionMessage = message ?? 'Vehicle stream disconnected';
    });
  }

  void _startHttpPolling() {
    debugPrint('Tesla HUD polling HTTP API: ${widget.apiUrl}');

    if (!mounted) {
      return;
    }

    setState(() {
      _connectionState = ConnectionStateLabel.loading;
      _connectionMessage = 'Polling ${widget.apiUrl}';
    });

    unawaited(_fetchHttpDashboardData());
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_fetchHttpDashboardData());
    });
  }

  Future<void> _fetchHttpDashboardData() async {
    try {
      final response = await http
          .get(Uri.parse(widget.apiUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('HTTP ${response.statusCode}');
      }

      _handleDashboardMessage(response.body, ConnectionStateLabel.http);
    } catch (error) {
      debugPrint('Tesla HUD HTTP polling failed: $error');
      if (!mounted) {
        return;
      }

      setState(() {
        _connectionState = ConnectionStateLabel.disconnected;
        _connectionMessage = 'HTTP polling failed: $error';
      });
    }
  }

  void _startDemoMode() {
    debugPrint('Tesla HUD running in local demo mode');
    _emitDemoDashboardData();
    _dataTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitDemoDashboardData();
    });
  }

  void _emitDemoDashboardData() {
    if (!mounted) {
      return;
    }

    setState(() {
      _dashboardData = _buildDemoDashboardData();
      _connectionState = ConnectionStateLabel.demo;
      _connectionMessage = null;
    });
  }

  DashboardData _buildDemoDashboardData() {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final tick = now.floor();
    final speed = 54 + (sin(now / 2.5) * 18).round();
    final mediaStatus = tick % 10 < 7 ? 'playing' : 'paused';

    return DashboardData(
      timestamp: now,
      speedKmh: speed,
      gear: speed == 0 ? 'P' : 'D',
      batteryPercent: 78 - ((tick ~/ 20) % 6),
      rangeKm: 332 - ((tick ~/ 3) % 18),
      media: MediaInfo(
        title: 'Local Demo',
        artist: 'Tesla HUD',
        status: mediaStatus,
        source: 'demo',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboardData = _dashboardData;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                state: _connectionState,
                message: _connectionMessage,
                sourceUrl: switch (_dataMode) {
                  DataMode.websocket => widget.webSocketUrl,
                  DataMode.http => widget.apiUrl,
                  DataMode.demo => 'Local demo data',
                },
                onReconnect: _startDataMode,
              ),
              const SizedBox(height: 24),
              Expanded(
                child: dashboardData == null
                    ? _EmptyState(state: _connectionState)
                    : _Dashboard(data: dashboardData),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.message,
    required this.sourceUrl,
    required this.onReconnect,
  });

  final ConnectionStateLabel state;
  final String? message;
  final String sourceUrl;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final isConnected = state == ConnectionStateLabel.connected ||
        state == ConnectionStateLabel.http ||
        state == ConnectionStateLabel.demo;
    final statusColor = isConnected ? const Color(0xFF30F2A0) : Colors.amber;
    final statusText = switch (state) {
      ConnectionStateLabel.loading => 'Connecting',
      ConnectionStateLabel.connected => 'Connected',
      ConnectionStateLabel.disconnected => 'Disconnected',
      ConnectionStateLabel.http => 'http',
      ConnectionStateLabel.demo => 'demo',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tesla HUD',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message ?? sourceUrl,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(label: statusText, color: statusColor),
            if (!isConnected) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onReconnect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 720;

        return Column(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(flex: 3, child: _SpeedGauge(speed: data.speedKmh)),
                  const SizedBox(width: 14),
                  Expanded(child: _GearTile(gear: data.gear)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              flex: 2,
              child: isCompact
                  ? Column(
                      children: [
                        Expanded(child: _BatteryTile(data: data)),
                        const SizedBox(height: 14),
                        Expanded(child: _MediaTile(media: data.media)),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _BatteryTile(data: data)),
                        const SizedBox(width: 14),
                        Expanded(child: _MediaTile(media: data.media)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({required this.speed});

  final num speed;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            speed.round().toString(),
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 96,
              fontWeight: FontWeight.w800,
              height: 0.95,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'km/h',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 18,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _GearTile extends StatelessWidget {
  const _GearTile({required this.gear});

  final String gear;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            gear,
            style: const TextStyle(
              color: Color(0xFF30F2A0),
              fontSize: 64,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          _PanelLabel(label: 'Gear'),
        ],
      ),
    );
  }
}

class _BatteryTile extends StatelessWidget {
  const _BatteryTile({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final battery = data.batteryPercent.clamp(0, 100).toDouble();

    return _HudPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _PanelLabel(label: 'Battery'),
          const SizedBox(height: 12),
          Text(
            '${battery.round()}%',
            style: const TextStyle(
              color: Color(0xFF30F2A0),
              fontSize: 42,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: battery / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF30F2A0)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${data.rangeKm.round()} km range',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});

  final MediaInfo media;

  @override
  Widget build(BuildContext context) {
    final isPlaying = media.status == 'playing';

    return _HudPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: const Color(0xFF00E5FF),
                size: 26,
              ),
              const SizedBox(width: 8),
              const _PanelLabel(label: 'Media'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${media.status} - ${media.source}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});

  final ConnectionStateLabel state;

  @override
  Widget build(BuildContext context) {
    final isLoading = state == ConnectionStateLabel.loading;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(
              Icons.signal_wifi_connected_no_internet_4_rounded,
              color: Colors.amber.shade300,
              size: 40,
            ),
          const SizedBox(height: 18),
          Text(
            isLoading ? 'Waiting for dashboard data' : 'Vehicle stream offline',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1118),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D3440)),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.58),
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}
