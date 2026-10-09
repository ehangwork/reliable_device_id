import 'package:reliable_device_id/reliable_device_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ReliableDeviceIdExampleApp());
}

class ReliableDeviceIdExampleApp extends StatelessWidget {
  const ReliableDeviceIdExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'reliable_device_id example',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F6FED)),
      home: const DeviceIdPage(),
    );
  }
}

/// Demonstrates the plugin's single-method API.
///
/// Note the explicit user action before the first read: in a real app the
/// first [ReliableDeviceId.get] must happen only after privacy-policy consent.
class DeviceIdPage extends StatefulWidget {
  const DeviceIdPage({super.key});

  @override
  State<DeviceIdPage> createState() => _DeviceIdPageState();
}

class _DeviceIdPageState extends State<DeviceIdPage> {
  Future<DeviceIdResult>? _future;

  @override
  void initState() {
    super.initState();
    _future = ReliableDeviceId.instance.get();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
  }

  Future<void> _showAndroidId() async {
    final androidId = await ReliableDeviceId.instance.getAndroidId();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Android ID'),
        content: SelectableText(
          androidId ?? '当前平台不可用（iOS 或读取失败）',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备唯一码 Demo')),
      body: FutureBuilder<DeviceIdResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data;
          if (result == null) {
            return const Center(child: Text('获取失败'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _IdCard(
                deviceId: result.deviceId,
                onCopy: () => _copy(result.deviceId),
              ),
              const SizedBox(height: 16),
              _MetaCard(result: result),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _showAndroidId,
                icon: const Icon(Icons.tag),
                label: const Text('直接读取 Android ID'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IdCard extends StatelessWidget {
  const _IdCard({required this.deviceId, required this.onCopy});

  final String deviceId;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('deviceId',
                    style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                IconButton(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制',
                ),
              ],
            ),
            SelectableText(
              deviceId,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.result});

  final DeviceIdResult result;

  @override
  Widget build(BuildContext context) {
    final firstSeen = result.firstSeenAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(result.firstSeenAt)
        : null;
    final rows = <(String, String)>[
      ('degraded', result.degraded ? 'true（会话级随机值）' : 'false'),
      ('firstSeenAt', firstSeen?.toString() ?? '-'),
      ('androidId (SSAID)', result.signals.androidId ?? '-'),
      ('idfv', result.signals.idfv ?? '-'),
      ('mediaDrmId (hashed)', result.signals.mediaDrmId ?? '-'),
      ('seedSource', result.signals.seedSource ?? '-'),
      ('isPhysicalDevice', result.signals.isPhysicalDevice?.toString() ?? '-'),
      ('manufacturer', result.signals.manufacturer ?? '-'),
      ('model', result.signals.model ?? '-'),
      ('osVersion', result.signals.osVersion ?? '-'),
      ('sdkInt', result.signals.sdkInt?.toString() ?? '-'),
      ('migrated', result.signals.migrated?.toString() ?? '-'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('signals / 元信息',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            for (final (key, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(key,
                          style: const TextStyle(fontFamily: 'monospace')),
                    ),
                    Expanded(
                      child: Text(value,
                          style: const TextStyle(fontFamily: 'monospace')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
