import 'dart:io';

import 'package:ffbox_edgelink/core/analytics/clarity_analytics.dart';
import 'package:ffbox_edgelink/presentation/theme/ak_theme.dart';
import 'package:flutter/material.dart';

/// 设备信息页：高密度展示本机所有网络接口及 IP 地址。
///
/// 保留极简架构（无 Riverpod / 持久化），使用 ak-ui 配色与排版保持视觉一致。
/// 接口名自适应宽度，IP 占满剩余空间。
class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  // --- 数据 ---

  final Future<List<NetworkInterface>> _interfaces = NetworkInterface.list(
    includeLinkLocal: true,
  );

  @override
  void initState() {
    super.initState();
    ClarityAnalytics.trackScreen('device_info');
  }

  List<_IpRow> _rows = const [];
  bool _measured = false;
  double _ifaceWidth = 0;

  // --- 测量接口名宽度 ---

  void _measure() {
    if (_measured || _rows.isEmpty) return;
    _measured = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final longest = _rows
          .map((r) => r.iface)
          .fold<String>('', (a, b) => b.length > a.length ? b : a);
      if (longest.isEmpty) return;
      final tp = TextPainter(
        text: TextSpan(
          text: longest,
          style: AkTheme.sans(fontSize: 13, color: AkColors.info),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      setState(() => _ifaceWidth = tp.width);
    });
  }

  // --- 构建 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('接口与IP')),
      body: FutureBuilder<List<NetworkInterface>>(
        future: _interfaces,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AkColors.info),
            );
          }
          if (snapshot.hasError) {
            return _EmptyView(message: '获取 IP 失败：${snapshot.error}');
          }

          final interfaces = snapshot.data ?? const <NetworkInterface>[];
          _rows = [
            for (final iface in interfaces)
              for (final addr in iface.addresses)
                _IpRow(
                  iface: iface.name,
                  address: addr.address,
                  isV6: addr.type == InternetAddressType.IPv6,
                ),
          ];
          _measure();

          if (_rows.isEmpty) {
            return const _EmptyView(message: '未获取到网络接口');
          }

          return CustomScrollView(
            slivers: [
              // --- 表头 ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Divider(height: 1, color: AkColors.border),
                ),
              ),
              // --- 数据行 ---
              SliverList.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Divider(height: 1, color: AkColors.border),
                ),
                itemBuilder: (_, i) =>
                    _DataRow(row: _rows[i], ifaceWidth: _ifaceWidth),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- 数据模型 ---

class _IpRow {
  final String iface;
  final String address;
  final bool isV6;
  const _IpRow({
    required this.iface,
    required this.address,
    required this.isV6,
  });
}

// --- 数据行 ---

class _DataRow extends StatelessWidget {
  final _IpRow row;
  final double ifaceWidth;

  const _DataRow({required this.row, required this.ifaceWidth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // 用 Row 而非 Stack：Row 高度由内容决定，可安全用于 SliverList 的无界高度约束
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ifaceWidth > 0 ? ifaceWidth : null,
            child: Text(
              row.iface,
              style: AkTheme.sans(fontSize: 13, color: AkColors.info),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ifaceWidth > 0) const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.address,
              style: AkTheme.mono(fontSize: 13, color: AkColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// --- 空态 ---

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: AkTheme.sans(fontSize: 14, color: AkColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
