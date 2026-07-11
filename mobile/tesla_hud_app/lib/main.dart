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

const double mobileWidthBreakpoint = 700;

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
    final sourceUrl = switch (_dataMode) {
      DataMode.websocket => widget.webSocketUrl,
      DataMode.http => widget.apiUrl,
      DataMode.demo => 'Local demo data',
    };

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final isPortrait = height > width;
            final isMobileWidth = width < mobileWidthBreakpoint;

            if (isMobileWidth && isPortrait) {
              return const _RotatePhoneScreen();
            }

            return _LandscapeHud(
              data: dashboardData,
              dataMode: _dataMode,
              state: _connectionState,
              message: _connectionMessage,
              sourceUrl: sourceUrl,
              onReconnect: _startDataMode,
            );
          },
        ),
      ),
    );
  }
}

class _RotatePhoneScreen extends StatelessWidget {
  const _RotatePhoneScreen();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.screen_rotation_rounded,
              color: Color(0xFF00E5FF),
              size: 44,
            ),
            const SizedBox(height: 18),
            const Text(
              'Rotate your phone for HUD mode',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Landscape mode keeps the dashboard compact for mobile web.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandscapeHud extends StatelessWidget {
  const _LandscapeHud({
    required this.data,
    required this.dataMode,
    required this.state,
    required this.message,
    required this.sourceUrl,
    required this.onReconnect,
  });

  final DashboardData? data;
  final DataMode dataMode;
  final ConnectionStateLabel state;
  final String? message;
  final String sourceUrl;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashboardData = data;
        final shortSide = min(constraints.maxWidth, constraints.maxHeight);
        final padding = shortSide < 390 ? 8.0 : 14.0;
        final gap = shortSide < 390 ? 8.0 : 12.0;
        final mediaHeight =
            (constraints.maxHeight * 0.17).clamp(48.0, 72.0).toDouble();
        final metricWidth =
            (constraints.maxWidth * 0.24).clamp(132.0, 230.0).toDouble();
        final useCompactStack = constraints.maxWidth < mobileWidthBreakpoint;

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusBar(
                dataMode: dataMode,
                state: state,
                message: message,
                sourceUrl: sourceUrl,
                onReconnect: onReconnect,
              ),
              SizedBox(height: gap),
              Expanded(
                child: dashboardData == null
                    ? _EmptyState(state: state)
                    : useCompactStack
                        ? Column(
                            children: [
                              Expanded(
                                flex: 4,
                                child: _SpeedPanel(data: dashboardData),
                              ),
                              SizedBox(height: gap),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _MetricCard(
                                        label: 'Battery',
                                        value:
                                            '${dashboardData.batteryPercent.round()}%',
                                        icon: Icons
                                            .battery_charging_full_rounded,
                                      ),
                                    ),
                                    SizedBox(width: gap),
                                    Expanded(
                                      child: _MetricCard(
                                        label: 'Range',
                                        value:
                                            '${dashboardData.rangeKm.round()} km',
                                        icon: Icons.route_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _SpeedPanel(data: dashboardData)),
                              SizedBox(width: gap),
                              SizedBox(
                                width: metricWidth,
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: _MetricCard(
                                        label: 'Battery',
                                        value:
                                            '${dashboardData.batteryPercent.round()}%',
                                        icon: Icons
                                            .battery_charging_full_rounded,
                                      ),
                                    ),
                                    SizedBox(height: gap),
                                    Expanded(
                                      child: _MetricCard(
                                        label: 'Range',
                                        value:
                                            '${dashboardData.rangeKm.round()} km',
                                        icon: Icons.route_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: mediaHeight,
                child: dashboardData == null
                    ? const SizedBox.shrink()
                    : _MediaBar(media: dashboardData.media),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.dataMode,
    required this.state,
    required this.message,
    required this.sourceUrl,
    required this.onReconnect,
  });

  final DataMode dataMode;
  final ConnectionStateLabel state;
  final String? message;
  final String sourceUrl;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final isHealthy = state == ConnectionStateLabel.connected ||
        state == ConnectionStateLabel.http ||
        state == ConnectionStateLabel.demo;

    return Row(
      children: [
        const Text(
          'Tesla HUD',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 12),
        _StatusPill(
          label: '${dataMode.name} - ${_statusText(state)}',
          color: isHealthy ? const Color(0xFF30F2A0) : Colors.amber,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message ?? sourceUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 12,
            ),
          ),
        ),
        if (!isHealthy)
          IconButton(
            tooltip: 'Retry',
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 32),
          ),
      ],
    );
  }

  String _statusText(ConnectionStateLabel state) {
    return switch (state) {
      ConnectionStateLabel.loading => 'connecting',
      ConnectionStateLabel.connected => 'connected',
      ConnectionStateLabel.disconnected => 'disconnected',
      ConnectionStateLabel.http => 'http',
      ConnectionStateLabel.demo => 'demo',
    };
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelSize =
              (constraints.maxHeight * 0.12).clamp(14.0, 22.0).toDouble();
          final gearSize =
              (constraints.maxHeight * 0.22).clamp(28.0, 54.0).toDouble();

          return Column(
            children: [
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    children: [
                      Text(
                        data.gear,
                        style: TextStyle(
                          color: const Color(0xFF30F2A0),
                          fontSize: gearSize,
                          fontWeight: FontWeight.w800,
                          height: 0.95,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        'GEAR',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.54),
                          fontSize: labelSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Flexible(
                flex: 5,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(
                    data.speedKmh.round().toString(),
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      height: 0.9,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'km/h',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: labelSize + 2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _HudPanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize =
              (constraints.maxHeight * 0.22).clamp(16.0, 26.0).toDouble();
          final valueSize =
              (constraints.maxHeight * 0.34).clamp(20.0, 38.0).toDouble();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFF30F2A0), size: iconSize),
                  const SizedBox(width: 6),
                  Expanded(child: _PanelLabel(label: label)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(
                        color: const Color(0xFF30F2A0),
                        fontSize: valueSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MediaBar extends StatelessWidget {
  const _MediaBar({required this.media});

  final MediaInfo media;

  @override
  Widget build(BuildContext context) {
    final isPlaying = media.status == 'playing';

    return _HudPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            isPlaying ? Icons.play_arrow_rounded : Icons.pause_rounded,
            color: const Color(0xFF00E5FF),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  media.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${media.status} - ${media.source}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
  const _HudPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
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
