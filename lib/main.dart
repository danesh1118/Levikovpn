import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sing_box/sing_box.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const subscriptionUrl =
    'https://raw.githubusercontent.com/danesh1118/SS/refs/heads/main/CC';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SingBox.instance.initialize(const SingBoxOptions(
    android: SingBoxAndroidOptions(
      notificationTitle: 'Leviko VPN',
      showTrafficInNotification: true,
      stopActionTitle: 'قطع اتصال',
    ),
  ));
  runApp(const LevikoApp());
}

class Node {
  final String link;
  final String name;
  String location;
  String flag;
  final String host;
  final int port;
  int? pingMs;
  String city = '';
  String countryCode = '';
  double? latitude;
  double? longitude;
  bool favorite = false;

  Node({
    required this.link,
    required this.name,
    required this.location,
    required this.flag,
    required this.host,
    required this.port,
  });
}

class LevikoApp extends StatefulWidget {
  const LevikoApp({super.key});
  @override
  State<LevikoApp> createState() => _LevikoAppState();
}

class _LevikoAppState extends State<LevikoApp> {
  bool english = false;
  bool loading = true;
  bool busy = false;
  String message = '';
  String stateText = 'قطع';
  List<Node> nodes = [];
  Node? selected;
  StreamSubscription? statusSub;
  StreamSubscription? statsSub;
  double downBps = 0;
  double upBps = 0;
  int downTotal = 0;
  int upTotal = 0;
  final Set<String> favoriteKeys = {};
  late Future<void> favoritesReady;
  DateTime? connectedAt;
  Timer? connectionTimer;
  int connectionSeconds = 0;
  String _nodeKey(Node n) => '${n.host}:${n.port}';

  String tr(String fa, String en) => english ? en : fa;

  @override
  void initState() {
    super.initState();
    favoritesReady = _loadFavorites();
    statusSub = SingBox.instance.watchConnectionStatus().listen((s) {
      if (!mounted) return;
      setState(() => stateText = s == SingBoxConnectionStatus.connected
          ? tr('متصل', 'Connected')
          : s == SingBoxConnectionStatus.connecting
              ? tr('در حال اتصال', 'Connecting')
              : tr('قطع', 'Disconnected'));
      if (s == SingBoxConnectionStatus.connected && connectedAt == null) {
        connectedAt = DateTime.now();
        connectionSeconds = 0;
        connectionTimer?.cancel();
        connectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && connectedAt != null) setState(() => connectionSeconds = DateTime.now().difference(connectedAt!).inSeconds);
        });
      } else if (s != SingBoxConnectionStatus.connected) {
        connectedAt = null;
        connectionTimer?.cancel();
        connectionSeconds = 0;
      }
    });
    statsSub = SingBox.instance.watchConnectionStats().listen((stats) {
      if (!mounted) return;
      setState(() {
        downBps = stats.downloadSpeed.toDouble();
        upBps = stats.uploadSpeed.toDouble();
        downTotal = stats.downloadTotal;
        upTotal = stats.uploadTotal;
      });
    });
    loadSubscription();
  }

  @override
  void dispose() {
    statusSub?.cancel();
    statsSub?.cancel();
    connectionTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      favoriteKeys.addAll(prefs.getStringList('favorite_nodes') ?? const []);
      if (mounted) setState(() { for (final n in nodes) { n.favorite = favoriteKeys.contains(_nodeKey(n)); } });
    } catch (_) {}
  }

  Future<void> _toggleFavorite(Node n) async {
    final key = _nodeKey(n);
    setState(() {
      n.favorite = !n.favorite;
      if (n.favorite) { favoriteKeys.add(key); } else { favoriteKeys.remove(key); }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_nodes', favoriteKeys.toList());
    } catch (_) {}
  }

  String _durationLabel() {
    final h = connectionSeconds ~/ 3600;
    final m = (connectionSeconds % 3600) ~/ 60;
    final sec = connectionSeconds % 60;
    return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  Future<void> loadSubscription() async {
    if (mounted) setState(() { loading = nodes.isEmpty; message = tr('در حال دریافت فهرست سرورها…', 'Fetching server list…'); });
    try {
      await favoritesReady;
      final response = await http.get(Uri.parse(subscriptionUrl)).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final body = _decodeSubscription(response.body);
      final parsed = body.split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.startsWith('#'))
          .where((s) => RegExp(r'^(vless|vmess|trojan|ss)://', caseSensitive: false).hasMatch(s))
          .map(_parseNode).whereType<Node>().toList();
      if (parsed.isEmpty) throw Exception(tr('کانفیگ پشتیبانی‌شده‌ای پیدا نشد', 'No supported server links found'));
      for (final n in parsed) { n.favorite = favoriteKeys.contains(_nodeKey(n)); }
      parsed.sort((a,b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() { nodes = parsed; selected ??= parsed.first; loading = false; message = tr('${parsed.length} سرور دریافت شد؛ در حال بررسی پینگ و موقعیت…', '${parsed.length} servers loaded; checking ping and location…'); });
      // Do not block the first screen on slow geolocation services. Enrich in small parallel batches.
      unawaited(_enrichNodes(parsed));
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; message = tr('خطا در دریافت سرورها: $e', 'Could not load servers: $e'); });
    }
  }

  Future<void> _enrichNodes(List<Node> list) async {
    for (var i = 0; i < list.length; i += 6) {
      final batch = list.skip(i).take(6);
      await Future.wait(batch.map((n) async {
        final pingFuture = _tcpPing(n.host, n.port);
        final locationFuture = _lookupLocation(n);
        await locationFuture;
        n.pingMs = await pingFuture;
      }));
      if (!mounted) return;
      setState(() {
        final sorted = [...nodes]..sort((a,b) => (a.pingMs ?? 999999).compareTo(b.pingMs ?? 999999));
        nodes = sorted;
        if (selected != null) { final match = nodes.where((x) => _nodeKey(x) == _nodeKey(selected!)); if (match.isNotEmpty) selected = match.first; }
        message = tr('سرورها آماده‌اند • پینگ و موقعیت به‌روزرسانی شد', 'Servers ready • ping and locations updated');
      });
    }
  }

  String _decodeSubscription(String raw) {
    final trimmed = raw.trim();
    if (trimmed.contains('://')) return trimmed;
    try {
      var normalized = trimmed.replaceAll(RegExp(r'\s+'), '');
      normalized += '=' * ((4 - normalized.length % 4) % 4);
      return utf8.decode(base64.decode(normalized));
    } catch (_) {
      return trimmed;
    }
  }

  Node? _parseNode(String link) {
    try {
      final uri = Uri.parse(link);
      String remark = Uri.decodeComponent(uri.fragment).trim();
      if (uri.scheme.toLowerCase() == 'vmess') {
        final encoded = uri.path.isNotEmpty ? uri.path : uri.host;
        final jsonText = utf8.decode(base64.decode(base64.normalize(encoded)));
        final data = jsonDecode(jsonText) as Map<String, dynamic>;
        final host = '${data['add'] ?? ''}';
        final port = int.tryParse('${data['port'] ?? ''}') ?? 0;
        remark = '${data['ps'] ?? remark}';
        if (host.isEmpty || port == 0) return null;
        final loc = _location(remark);
        return Node(link: link, name: remark.isEmpty ? loc.$2 : remark,
            location: loc.$1, flag: loc.$2, host: host, port: port);
      }

      String host = uri.host;
      int port = uri.port;
      if (uri.scheme == 'ss' && host.isEmpty) {
        final at = link.lastIndexOf('@');
        if (at >= 0) {
          final serverPart = link.substring(at + 1).split('#').first;
          final parsed = Uri.parse('ss://$serverPart');
          host = parsed.host;
          port = parsed.port;
        }
      }
      if (host.isEmpty || port <= 0) return null;
      final loc = _location(remark);
      return Node(
        link: link,
        name: remark.isEmpty ? loc.$2 : remark,
        location: loc.$1,
        flag: loc.$2,
        host: host,
        port: port,
      );
    } catch (_) {
      return null;
    }
  }

  (String, String) _location(String remark) {
    final s = remark.toLowerCase();
    const countries = <String, (String, String, String)>{
      'germany': ('آلمان', '🇩🇪', 'Germany'),
      'de': ('آلمان', '🇩🇪', 'Germany'),
      'finland': ('فنلاند', '🇫🇮', 'Finland'),
      'fi': ('فنلاند', '🇫🇮', 'Finland'),
      'netherlands': ('هلند', '🇳🇱', 'Netherlands'),
      'nl': ('هلند', '🇳🇱', 'Netherlands'),
      'france': ('فرانسه', '🇫🇷', 'France'),
      'fr': ('فرانسه', '🇫🇷', 'France'),
      'united states': ('آمریکا', '🇺🇸', 'United States'),
      'usa': ('آمریکا', '🇺🇸', 'United States'),
      'us': ('آمریکا', '🇺🇸', 'United States'),
      'iran': ('ایران', '🇮🇷', 'Iran'),
      'ir': ('ایران', '🇮🇷', 'Iran'),
      'turkey': ('ترکیه', '🇹🇷', 'Turkey'),
      'tr': ('ترکیه', '🇹🇷', 'Turkey'),
      'uk': ('انگلستان', '🇬🇧', 'United Kingdom'),
      'united kingdom': ('انگلستان', '🇬🇧', 'United Kingdom'),
    };
    for (final entry in countries.entries) {
      if (RegExp(r'(^|[^a-z])' + RegExp.escape(entry.key) + r'([^a-z]|$)')
          .hasMatch(s)) {
        return (english ? entry.value.$3 : entry.value.$1, entry.value.$2);
      }
    }
    final flagMatch = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}',
            unicode: true)
        .firstMatch(remark);
    return (english ? 'Unknown location' : 'موقعیت نامشخص',
        flagMatch?.group(0) ?? '🌐');
  }

  Future<void> _lookupLocation(Node node) async {
    try {
      final addresses = await InternetAddress.lookup(node.host)
          .timeout(const Duration(seconds: 4));
      if (addresses.isEmpty) return;
      final ip = addresses.first.address;
      final response = await http.get(Uri.parse('https://ipwho.is/$ip'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == false) return;
      node.city = '${data['city'] ?? ''}'.trim();
      node.location = '${data['country'] ?? ''}'.trim().isEmpty
          ? node.location : '${data['country']}';
      node.countryCode = '${data['country_code'] ?? ''}'.toUpperCase();
      node.latitude = (data['latitude'] as num?)?.toDouble();
      node.longitude = (data['longitude'] as num?)?.toDouble();
      node.flag = _flagFromCode(node.countryCode);
    } catch (_) {
      // Keep the location inferred from the subscription remark as fallback.
    }
  }

  String _flagFromCode(String code) {
    if (code.length != 2) return '🌐';
    final upper = code.toUpperCase();
    return String.fromCharCodes(upper.codeUnits.map((c) => 0x1F1E6 + c - 65));
  }

  String _cityLabel(Node n) => n.city.isNotEmpty
      ? n.city
      : (n.location.isNotEmpty ? n.location : tr('موقعیت نامشخص', 'Unknown location'));

  String _formatBytes(int value) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double v = value.toDouble();
    int i = 0;
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
    return '${v.toStringAsFixed(i == 0 ? 0 : 2)} ${units[i]}';
  }

  String _formatSpeed(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)} MB/s';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} KB/s';
    return '${value.toStringAsFixed(0)} B/s';
  }

  void _openLocations() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF15111E),
      barrierColor: Colors.black.withOpacity(.78),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) {
          final currentNodes = [...nodes];
          String query = '';
          // The stateful builder owns the query state below; keep it in the
          // dedicated content widget so each keystroke updates the results.
          return _ServerPickerSheet(
            nodes: currentNodes,
            loading: loading,
            english: english,
            selectedKey: selected == null ? null : _nodeKey(selected!),
            onRefresh: () async {
              await loadSubscription();
              if (sheetContext.mounted) sheetSetState(() {});
            },
            onFavorite: (node) async {
              await _toggleFavorite(node);
              if (sheetContext.mounted) sheetSetState(() {});
            },
            onSelect: (node) {
              setState(() => selected = node);
              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr('سرور انتخاب شد؛ برای اتصال دکمه اتصال را بزن.', 'Server selected. Press Connect to start.')),
                duration: const Duration(seconds: 2),
              ));
            },
            tr: tr,
            cityLabel: _cityLabel,
          );
        },
      ),
    );
  }

  Future<int?> _tcpPing(String host, int port) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      watch.stop();
      return watch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Future<void> connect([Node? target]) async {
    final node = target ?? selected;
    if (node == null || busy) return;
    setState(() {
      busy = true;
      message = tr('در حال اتصال…', 'Connecting…');
    });
    try {
      await SingBox.instance.connect(node.link);
      if (!mounted) return;
      setState(() {
        selected = node;
        message = tr('اتصال برقرار شد', 'Connected successfully');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => message = tr('اتصال ناموفق: $e', 'Connection failed: $e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disconnect() async {
    setState(() => busy = true);
    try {
      await SingBox.instance.disconnect();
    } catch (_) {}
    if (mounted) setState(() {
      busy = false;
      message = tr('اتصال قطع شد', 'Disconnected');
    });
  }

  Future<void> fastest() async {
    if (nodes.isEmpty) return;
    final available = nodes.where((n) => n.pingMs != null).toList()
      ..sort((a, b) => a.pingMs!.compareTo(b.pingMs!));
    await connect(available.isNotEmpty ? available.first : nodes.first);
  }

  @override
  Widget build(BuildContext context) {
    final active = SingBox.instance.status.isActive;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09070F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B5CFF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: Directionality(
        textDirection: english ? TextDirection.ltr : TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF09070F),
            title: const Text('LEVIKO VPN',
                style: TextStyle(fontWeight: FontWeight.w900,
                    letterSpacing: 2, color: Color(0xFFC9A7FF))),
            actions: [
              IconButton(tooltip: tr('تازه‌سازی سرورها','Refresh servers'), onPressed: loading ? null : loadSubscription, icon: const Icon(Icons.refresh, color: Color(0xFFC9A7FF))),
              TextButton(
                onPressed: () => setState(() => english = !english),
                child: Text(english ? 'فارسی' : 'English'),
              ),
            ],
          ),
          body: SafeArea(
            child: loading
                ? Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 18),
                      Text(message),
                    ],
                  ))
                : RefreshIndicator(
                    onRefresh: loadSubscription,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 350,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // The animated world map is a background layer behind the status and connect control.
                              Positioned.fill(
                                child: AnimatedGlobe(
                                  latitude: selected?.latitude,
                                  longitude: selected?.longitude,
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      colors: [const Color(0x00100A1B), const Color(0xCC09070F)],
                                      stops: const [0.48, 1],
                                    ),
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 18),
                                  Container(
                                    width: 82,
                                    height: 82,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xCC1A1028),
                                      border: Border.all(color: const Color(0xFF9B5CFF), width: 2),
                                      boxShadow: const [BoxShadow(color: Color(0x669B5CFF), blurRadius: 30, spreadRadius: 4)],
                                    ),
                                    child: const Icon(Icons.shield_rounded, size: 40, color: Color(0xFFC9A7FF)),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(stateText, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  Text(message, textAlign: TextAlign.center,
                                      style: const TextStyle(color: Colors.white60)),
                                  if (active)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text('⏱ ${_durationLabel()}',
                                          style: const TextStyle(color: Color(0xFF79E6B5))),
                                    ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: 210,
                                    height: 58,
                                    child: FilledButton(
                                      onPressed: busy ? null : (active ? disconnect : () => connect()),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF8B42E8),
                                        elevation: 12,
                                        shadowColor: const Color(0xAA9B5CFF),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                      ),
                                      child: Text(active ? tr('قطع اتصال', 'DISCONNECT') : tr('اتصال', 'CONNECT'),
                                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 16)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 26),
                        _sectionTitle(tr('موقعیت اتصال', 'Connection location')),
                        const SizedBox(height: 10),
                        Card(
                          color: const Color(0xFF171020),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
                            side: const BorderSide(color: Color(0xFF493064))),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            child: Row(children: [
                              const CircleAvatar(backgroundColor: Color(0xFF2A1A3C),
                                child: Icon(Icons.public, color: Color(0xFFC9A7FF))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(selected == null ? tr('هنوز سروری انتخاب نشده', 'No server selected') : (selected!.name.isNotEmpty ? selected!.name : _cityLabel(selected!)),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(selected == null ? tr('از لیست سرورها انتخاب کن', 'Choose from the server list') : _cityLabel(selected!),
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ])),
                              if (selected?.pingMs != null)
                                Text('${selected!.pingMs} ms', style: const TextStyle(color: Color(0xFF79E6B5), fontWeight: FontWeight.bold)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: SizedBox(height: 52, child: FilledButton.icon(
                            onPressed: _openLocations,
                            icon: const Icon(Icons.list_alt_rounded),
                            label: Text(tr('لیست سرورها', 'SERVER LIST'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8B42E8), foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          ))),
                          const SizedBox(width: 10),
                          Expanded(child: SizedBox(height: 52, child: OutlinedButton.icon(
                            onPressed: loading || nodes.isEmpty ? null : fastest,
                            icon: const Icon(Icons.bolt_rounded),
                            label: Text(tr('سریع‌ترین لوکیشن', 'FASTEST'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD9B8FF), side: const BorderSide(color: Color(0xFF9B5CFF), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          ))),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(child: _statCard(Icons.arrow_downward, tr('دریافت', 'Download'),
                            _formatSpeed(downBps), _formatBytes(downTotal))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard(Icons.arrow_upward, tr('ارسال', 'Upload'),
                            _formatSpeed(upBps), _formatBytes(upTotal))),
                        ]),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171020),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF39234F)),
                          ),
                          child: Column(children: [
                            const Text('LEVIKO VPN',
                                style: TextStyle(fontWeight: FontWeight.w900,
                                    color: Color(0xFFC9A7FF), letterSpacing: 1.5)),
                            const SizedBox(height: 6),
                            Text(tr('این برنامه کاملاً رایگان می‌باشد',
                                'This application is completely free')),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse('https://t.me/Leviko_v2ray'),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.telegram),
                              label: Text(tr('کانال تلگرام', 'Telegram channel')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFC9A7FF),
                                side: const BorderSide(color: Color(0xFF8B42E8)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const SelectableText('@Leviko_v2ray',
                                style: TextStyle(color: Colors.white60)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Center(child: Text(
                          tr('برای به‌روزرسانی سرورها صفحه را پایین بکشید',
                              'Pull down to refresh servers'),
                          style: const TextStyle(color: Colors.white38,
                              fontSize: 11),
                        )),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String title, String speed, String total) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFF15121B),
      borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF292331))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 17, color: const Color(0xFFC9A7FF)),
        const SizedBox(width: 7), Text(title, style: const TextStyle(color: Colors.white70))]),
      const SizedBox(height: 9), Text(speed, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF79E6B5))),
      const SizedBox(height: 3), Text(total, style: const TextStyle(fontSize: 11, color: Colors.white54)),
    ]),
  );

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold));

  Widget _serverTile({
    required String flag,
    required String title,
    required String subtitle,
    required int? ping,
    required bool selectedTile,
    required VoidCallback? onTap,
  }) {
    return Card(
      color: selectedTile ? const Color(0xFF28163D) : const Color(0xFF15121B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selectedTile
            ? const Color(0xFF9B5CFF) : const Color(0xFF292331)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Text(flag, style: const TextStyle(fontSize: 25)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(ping == null ? '—' : '$ping ms',
                style: TextStyle(
                  color: ping == null ? Colors.white38 :
                      ping < 180 ? Colors.greenAccent : Colors.orangeAccent,
                  fontWeight: FontWeight.bold, fontSize: 12)),
            if (selectedTile)
              const Icon(Icons.check_circle, color: Color(0xFFC9A7FF), size: 16),
          ],
        ),
      ),
    );
  }
}


class GlobePainter extends CustomPainter {
  final double? latitude;
  final double? longitude;
  final double phase;
  GlobePainter({this.latitude, this.longitude, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width * .39, size.height * .47);
    final globe = Paint()..shader = const RadialGradient(colors: [Color(0xFF30204B), Color(0xFF100D1A), Color(0xFF080710)], stops: [0, .72, 1]).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, globe);
    final outline = Paint()..color = const Color(0xFF9B5CFF)..style = PaintingStyle.stroke..strokeWidth = 1.3;
    canvas.drawCircle(center, radius, outline);
    final grid = Paint()..color = const Color(0x557E56B5)..style = PaintingStyle.stroke..strokeWidth = .7;
    for (int i = -2; i <= 2; i++) {
      final rect = Rect.fromCenter(center: center, width: radius * 2 * (1 - i.abs() * .13), height: radius * 2);
      canvas.drawOval(rect, grid);
      final y = center.dy + i * radius * .32;
      final half = radius * math.sqrt(math.max(0, 1 - math.pow((y-center.dy)/radius, 2)));
      canvas.drawLine(Offset(center.dx-half,y), Offset(center.dx+half,y), grid);
    }
    // Low-detail continent silhouettes provide an offline, lightweight globe backdrop.
    final land = Paint()..color = const Color(0xFF7652A5).withOpacity(.58)..style = PaintingStyle.fill;
    final drift = math.sin(phase * 2 * math.pi) * radius * .035;
    final shapes = <List<Offset>>[
      [Offset(-.78,-.42),Offset(-.55,-.62),Offset(-.30,-.52),Offset(-.23,-.25),Offset(-.42,-.04),Offset(-.50,.28),Offset(-.68,.18),Offset(-.82,-.08)],
      [Offset(-.18,-.62),Offset(.08,-.70),Offset(.34,-.56),Offset(.30,-.30),Offset(.12,-.20),Offset(.04,.12),Offset(-.12,.02),Offset(-.28,-.28)],
      [Offset(.34,-.56),Offset(.70,-.50),Offset(.82,-.22),Offset(.66,-.02),Offset(.44,-.10),Offset(.32,-.32)],
      [Offset(.16,.12),Offset(.42,.04),Offset(.60,.24),Offset(.48,.56),Offset(.26,.66),Offset(.12,.38)],
    ];
    for (final poly in shapes) {
      final path = Path();
      for (int i=0;i<poly.length;i++) { final pt = Offset(center.dx + poly[i].dx*radius + drift, center.dy + poly[i].dy*radius); if(i==0) path.moveTo(pt.dx,pt.dy); else path.lineTo(pt.dx,pt.dy); }
      path.close();
      canvas.save(); canvas.clipPath(Path()..addOval(Rect.fromCircle(center:center,radius:radius))); canvas.drawPath(path,land); canvas.restore();
    }
    if (latitude != null && longitude != null) {
      final lat = latitude!.clamp(-85,85).toDouble() * math.pi / 180;
      final lon = longitude!.clamp(-180,180).toDouble() * math.pi / 180;
      final x = center.dx + radius * .88 * (lon / math.pi) + drift;
      final y = center.dy - radius * .78 * (lat / (math.pi/2));
      if ((Offset(x,y)-center).distance < radius) {
        final pulse = .5 + .5 * math.sin(phase * 2 * math.pi);
        canvas.drawOval(Rect.fromCenter(center: Offset(x,y), width: 24 + pulse*4, height: 16 + pulse*3), Paint()..color = const Color(0x667E4BD2)..style=PaintingStyle.stroke..strokeWidth=1.4);
        canvas.drawCircle(Offset(x,y), 8 + pulse*6, Paint()..color = const Color(0x559D5CFF)..style=PaintingStyle.stroke..strokeWidth=2);
        canvas.drawCircle(Offset(x,y), 4, Paint()..color = const Color(0xFFFFD76A));
        canvas.drawCircle(Offset(x,y), 2, Paint()..color = Colors.white);
      }
    }
    final glow = Paint()..shader = RadialGradient(colors:[const Color(0x009B5CFF),const Color(0x229B5CFF)]).createShader(Rect.fromCircle(center:center,radius:radius*1.25));
    canvas.drawCircle(center,radius*1.22,glow);
  }

  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) => oldDelegate.latitude != latitude || oldDelegate.longitude != longitude || oldDelegate.phase != phase;
}


class _ServerPickerSheet extends StatefulWidget {
  final List<Node> nodes;
  final bool loading;
  final bool english;
  final String? selectedKey;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Node) onFavorite;
  final void Function(Node) onSelect;
  final String Function(String, String) tr;
  final String Function(Node) cityLabel;

  const _ServerPickerSheet({
    required this.nodes, required this.loading, required this.english,
    required this.selectedKey, required this.onRefresh,
    required this.onFavorite, required this.onSelect,
    required this.tr, required this.cityLabel,
  });

  @override
  State<_ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<_ServerPickerSheet> {
  String query = '';
  bool onlyFavorites = false;
  bool refreshing = false;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.nodes.where((n) {
      final q = query.trim().toLowerCase();
      final searchable = '${n.name} ${n.location} ${n.city} ${n.countryCode}'.toLowerCase();
      return searchable.contains(q) && (!onlyFavorites || n.favorite);
    }).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * .88,
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(8))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
          child: Row(children: [
            const Icon(Icons.dns_rounded, color: Color(0xFFC9A7FF), size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.tr('لیست سرورها و کانفیگ‌ها', 'Servers & configurations'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
            Text('${widget.nodes.length}', style: const TextStyle(color: Color(0xFFC9A7FF), fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white70)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: widget.tr('جستجو در نام کانفیگ یا کشور…', 'Search config name or country…'),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFC9A7FF)),
              filled: true, fillColor: const Color(0xFF211A2B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            ChoiceChip(label: Text(widget.tr('همه سرورها', 'All servers')), selected: !onlyFavorites, onSelected: (_) => setState(() => onlyFavorites = false)),
            const SizedBox(width: 8),
            ChoiceChip(avatar: const Icon(Icons.star, size: 15), label: Text(widget.tr('نشان‌شده‌ها', 'Favorites')), selected: onlyFavorites, onSelected: (_) => setState(() => onlyFavorites = true)),
            const Spacer(),
            IconButton(tooltip: widget.tr('دریافت دوباره', 'Reload subscription'), onPressed: refreshing ? null : () async {
              setState(() => refreshing = true);
              await widget.onRefresh();
              if (mounted) setState(() => refreshing = false);
            }, icon: refreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh, color: Color(0xFFC9A7FF))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFF34283F)),
        Expanded(child: filtered.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.loading ? Icons.sync : Icons.cloud_off, size: 42, color: const Color(0xFFC9A7FF)),
              const SizedBox(height: 12),
              Text(widget.loading ? widget.tr('در حال دریافت سرورها…', 'Loading servers…') : widget.tr('سروری در فهرست نیست. دریافت دوباره را بزن.', 'No servers loaded. Tap reload.'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: refreshing ? null : () async { setState(() => refreshing = true); await widget.onRefresh(); if (mounted) setState(() => refreshing = false); }, icon: const Icon(Icons.refresh), label: Text(widget.tr('دریافت سرورها', 'Load servers'))),
            ])))
          : ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 26),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 5),
              itemBuilder: (_, i) {
                final n = filtered[i];
                final chosen = widget.selectedKey == '${n.host}:${n.port}';
                return Card(
                  color: chosen ? const Color(0xFF2A1740) : const Color(0xFF1C1724),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: chosen ? const Color(0xFFB77BFF) : const Color(0xFF34283F))),
                  child: ListTile(
                    onTap: () => widget.onSelect(n),
                    leading: Text(n.flag, style: const TextStyle(fontSize: 26)),
                    title: Text(n.name.isNotEmpty ? n.name : widget.cityLabel(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    subtitle: Text(widget.cityLabel(n), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    trailing: SizedBox(width: 112, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Expanded(child: Text(n.pingMs == null ? '…' : '${n.pingMs} ms', textAlign: TextAlign.end, style: const TextStyle(color: Color(0xFF79E6B5), fontWeight: FontWeight.bold))),
                      IconButton(tooltip: widget.tr('علاقه‌مندی', 'Favorite'), onPressed: () => widget.onFavorite(n), icon: Icon(n.favorite ? Icons.star : Icons.star_border, color: n.favorite ? Colors.amber : Colors.white54)),
                      if (chosen) const Icon(Icons.check_circle, color: Color(0xFFC9A7FF)),
                    ])),
                  ),
                );
              },
            )),
      ]),
    );
  }
}

class AnimatedGlobe extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  const AnimatedGlobe({super.key, this.latitude, this.longitude});
  @override
  State<AnimatedGlobe> createState() => _AnimatedGlobeState();
}

class _AnimatedGlobeState extends State<AnimatedGlobe> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  @override
  void initState() { super.initState(); controller = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(); }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller, builder: (_, __) => CustomPaint(painter: GlobePainter(latitude: widget.latitude, longitude: widget.longitude, phase: controller.value)));
}
