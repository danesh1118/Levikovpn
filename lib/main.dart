import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sing_box/sing_box.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String tr(String fa, String en) => english ? en : fa;

  @override
  void initState() {
    super.initState();
    statusSub = SingBox.instance.watchConnectionStatus().listen((s) {
      if (!mounted) return;
      setState(() => stateText = s == SingBoxConnectionStatus.connected
          ? tr('متصل', 'Connected')
          : s == SingBoxConnectionStatus.connecting
              ? tr('در حال اتصال', 'Connecting')
              : tr('قطع', 'Disconnected'));
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
    super.dispose();
  }

  Future<void> loadSubscription() async {
    setState(() {
      loading = true;
      message = tr('در حال دریافت سرورها…', 'Loading servers…');
    });
    try {
      final response = await http.get(Uri.parse(subscriptionUrl))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final body = _decodeSubscription(response.body);
      final parsed = body
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.startsWith('#'))
          .where((s) => RegExp(r'^(vless|vmess|trojan|ss)://',
                  caseSensitive: false)
              .hasMatch(s))
          .map(_parseNode)
          .whereType<Node>()
          .toList();

      if (parsed.isEmpty) {
        throw Exception(tr('کانفیگ پشتیبانی‌شده‌ای پیدا نشد',
            'No supported server links found'));
      }
      for (final node in parsed) {
        node.pingMs = await _tcpPing(node.host, node.port);
        await _lookupLocation(node);
      }
      parsed.sort((a, b) =>
          (a.pingMs ?? 999999).compareTo(b.pingMs ?? 999999));
      if (!mounted) return;
      setState(() {
        nodes = parsed;
        selected = parsed.first;
        loading = false;
        message = tr('${parsed.length} سرور آماده است',
            '${parsed.length} servers ready');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        message = tr('خطا در دریافت سرورها: $e',
            'Could not load servers: $e');
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
      backgroundColor: const Color(0xFF15111E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(children: [
            const SizedBox(height: 12),
            Container(width: 42, height: 4, decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(8))),
            Padding(padding: const EdgeInsets.all(18), child: Row(children: [
              const Icon(Icons.public, color: Color(0xFFC9A7FF)),
              const SizedBox(width: 10),
              Text(tr('انتخاب سرور', 'Select server'), style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${nodes.length}', style: const TextStyle(color: Colors.white54)),
            ])),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _serverTile(flag: '⚡', title: tr('سریع‌ترین سرور', 'Fastest server'),
                  subtitle: tr('انتخاب بر اساس کمترین پینگ', 'Lowest measured latency'),
                  ping: nodes.map((e) => e.pingMs).whereType<int>().fold<int?>(null,
                    (a,b) => a == null || b < a ? b : a), selectedTile: false,
                  onTap: () { Navigator.pop(context); fastest(); }),
                const SizedBox(height: 8),
                ...nodes.map((n) => _serverTile(flag: n.flag,
                  title: _cityLabel(n), subtitle: n.location,
                  ping: n.pingMs, selectedTile: selected == n,
                  onTap: () { setState(() => selected = n); Navigator.pop(context); })),
              ])),
          ]),
        ),
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
                        const SizedBox(height: 12),
                        Center(child: Container(
                          width: 116, height: 116,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF1A1028),
                            border: Border.all(
                                color: const Color(0xFF9B5CFF), width: 2),
                            boxShadow: const [
                              BoxShadow(color: Color(0x669B5CFF),
                                  blurRadius: 35, spreadRadius: 5),
                            ],
                          ),
                          child: const Icon(Icons.shield_rounded,
                              size: 58, color: Color(0xFFC9A7FF)),
                        )),
                        const SizedBox(height: 18),
                        Center(child: Text(stateText,
                            style: const TextStyle(fontSize: 20,
                                fontWeight: FontWeight.bold))),
                        const SizedBox(height: 6),
                        Center(child: Text(message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60))),
                        const SizedBox(height: 22),
                        Center(
                          child: SizedBox(
                            width: 190, height: 58,
                            child: FilledButton(
                              onPressed: busy ? null :
                                  (active ? disconnect : () => connect()),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF8B42E8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                              ),
                              child: Text(active
                                  ? tr('قطع اتصال', 'DISCONNECT')
                                  : tr('اتصال', 'CONNECT'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2, fontSize: 16)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        _sectionTitle(tr('موقعیت اتصال', 'Connection location')),
                        const SizedBox(height: 10),
                        Card(
                          color: const Color(0xFF171020),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
                            side: const BorderSide(color: Color(0xFF493064))),
                          child: ListTile(
                            onTap: _openLocations,
                            leading: const CircleAvatar(backgroundColor: Color(0xFF2A1A3C),
                              child: Icon(Icons.public, color: Color(0xFFC9A7FF))),
                            title: Text(selected == null ? tr('انتخاب سرور', 'Choose server') : _cityLabel(selected!),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(tr('برای دیدن همه سرورها لمس کنید', 'Tap to view all servers'),
                              style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            trailing: const Icon(Icons.keyboard_arrow_down, color: Color(0xFFC9A7FF)),
                          ),
                        ),
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
