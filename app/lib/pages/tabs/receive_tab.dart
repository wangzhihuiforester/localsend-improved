import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/chat_page.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/web_share_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/widget/animations/initial_fade_transition.dart';
import 'package:localsend_app/widget/column_list_view.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class ReceiveTab extends StatefulWidget {
  const ReceiveTab();

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> {
  /// Whether the advanced network info is shown
  bool _showAdvanced = false;

  /// Whether the history button is shown
  /// This extra boolean is needed to delay the animation
  bool _showHistoryButton = true;

  Future<void> _toggleAdvanced() async {
    if (_showAdvanced) {
      setState(() => _showAdvanced = false);
      await sleepAsync(200);
      if (mounted) {
        setState(() => _showHistoryButton = true);
      }
    } else {
      setState(() {
        _showAdvanced = true;
        _showHistoryButton = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alias = context.watch(settingsProvider.select((s) => s.alias));
    final serverState = context.watch(serverProvider);
    final localIps = context.watch(localIpProvider.select((s) => s.localIps));
    final nearbyDevices = context.watch(nearbyDevicesProvider).devices.values.toList();
    final chatState = context.watch(chatProvider);

    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ResponsiveListView.defaultMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: ColumnListView(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 设备状态区域（原有功能不变）
                  Expanded(
                    flex: 0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InitialFadeTransition(
                          duration: const Duration(milliseconds: 300),
                          delay: const Duration(milliseconds: 200),
                          child: Consumer(
                            builder: (context, ref) {
                              final animations = ref.watch(animationProvider);
                              final activeTab = ref.watch(homePageControllerProvider.select((state) => state.currentTab));
                              return RotatingWidget(
                                duration: const Duration(seconds: 15),
                                spinning: serverState != null && animations && activeTab == HomeTab.receive,
                                child: const LocalSendLogo(withText: false),
                              );
                            },
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(serverState?.alias ?? alias, style: const TextStyle(fontSize: 48)),
                        ),
                        InitialFadeTransition(
                          duration: const Duration(milliseconds: 300),
                          delay: const Duration(milliseconds: 500),
                          child: Text(
                            serverState == null ? t.general.offline : t.general.online,
                            style: const TextStyle(fontSize: 24),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 局域网成员列表
                  Expanded(
                    child: nearbyDevices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wifi_find, size: 48, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 12),
                                Text(
                                  '正在搜索局域网设备...',
                                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                child: Row(
                                  children: [
                                    Text(
                                      '局域网成员 (${nearbyDevices.length})',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Spacer(),
                                    Icon(Icons.people_outline, size: 20, color: Theme.of(context).colorScheme.outline),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: nearbyDevices.length,
                                  itemBuilder: (context, index) {
                                    final device = nearbyDevices[index];
                                    final unread = chatState.unreadDevices.contains(device.fingerprint);
                                    final msgCount = chatState.messagesByDevice[device.fingerprint]?.length ?? 0;
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                                      child: ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                          child: Icon(
                                            _deviceTypeIcon(device.deviceType),
                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                            size: 20,
                                          ),
                                        ),
                                        title: Text(
                                          device.alias,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        subtitle: Text(
                                          msgCount > 0 ? '$msgCount 条消息' : (device.deviceModel ?? device.ip ?? ''),
                                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (unread)
                                              Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context).colorScheme.error,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Text('新', style: TextStyle(color: Colors.white, fontSize: 10)),
                                              ),
                                            IconButton(
                                              icon: const Icon(Icons.chat_bubble_outline, size: 20),
                                              tooltip: '聊天',
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ChatPage(
                                                      deviceFingerprint: device.fingerprint,
                                                      deviceAlias: device.alias,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await context.global.dispatchAsync(NavigateAction.push(const WebSharePage()));
                        },
                        icon: Icon(Icons.language),
                        label: Text(t.receiveTab.link),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ),
        _InfoBox(
          serverState: serverState,
          localIps: localIps,
          showAdvanced: _showAdvanced,
        ),
        _CornerButtons(
          showAdvanced: _showAdvanced,
          showHistoryButton: _showHistoryButton,
          toggleAdvanced: _toggleAdvanced,
        ),
      ],
    );
  }
}

/// 根据设备类型返回对应图标
IconData _deviceTypeIcon(DeviceType type) {
  switch (type) {
    case DeviceType.mobile:
      return Icons.phone_android;
    case DeviceType.desktop:
      return Icons.computer;
    case DeviceType.web:
      return Icons.language;
    case DeviceType.headless:
      return Icons.terminal;
    case DeviceType.server:
      return Icons.dns;
  }
}

class _CornerButtons extends StatelessWidget {
  final bool showAdvanced;
  final bool showHistoryButton;
  final Future<void> Function() toggleAdvanced;

  const _CornerButtons({
    required this.showAdvanced,
    required this.showHistoryButton,
    required this.toggleAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!showAdvanced)
              AnimatedOpacity(
                opacity: showHistoryButton ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: CustomIconButton(
                  onPressed: () async {
                    await context.push(() => const ReceiveHistoryPage());
                  },
                  child: const Icon(Icons.history),
                ),
              ),
            CustomIconButton(
              key: const ValueKey('info-btn'),
              onPressed: toggleAdvanced,
              child: const Icon(Icons.info),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final ServerState? serverState;
  final List<String> localIps;
  final bool showAdvanced;

  const _InfoBox({
    required this.serverState,
    required this.localIps,
    required this.showAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      crossFadeState: showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
      firstChild: Container(),
      secondChild: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.alias),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
                        child: SelectableText(serverState?.alias ?? '-'),
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.ip),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (localIps.isEmpty) Text(t.general.unknown),
                          ...localIps.map((ip) => SelectableText(ip)),
                        ],
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.receiveTab.infoBox.port),
                      const SizedBox(width: 10),
                      SelectableText(serverState?.port.toString() ?? '-'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
