import 'package:flutter/material.dart';
import 'package:localsend_app/pages/chat_page.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 聊天设备列表页面，显示所有可聊天的设备。
///
/// 列表包含两类设备：
/// - 已有聊天记录的设备（可能在线或离线）
/// - 当前在线的附近设备（尚无聊天记录）
///
/// 点击设备项可进入 [ChatPage] 与该设备进行聊天。
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> with Refena {
  @override
  Widget build(BuildContext context) {
    // nearbyDevicesProvider 的 devices 是 Map<String, Device>，通过 values 获取设备列表
    final nearbyDevices = ref.watch(nearbyDevicesProvider).devices.values.toList();
    final chatState = ref.watch(chatProvider);

    // 构建可聊天设备列表：包含已有聊天记录的设备和附近在线的设备
    final chatDevices = <String, ({String alias, bool isOnline, int messageCount, bool unread})>{};

    // 添加已有聊天记录的设备
    for (final entry in chatState.messagesByDevice.entries) {
      final fingerprint = entry.key;
      final isOnline = nearbyDevices.any((d) => d.fingerprint == fingerprint);
      final unread = chatState.unreadDevices.contains(fingerprint);
      final alias = entry.value.isNotEmpty ? entry.value.last.deviceAlias : fingerprint.substring(0, 8);
      chatDevices[fingerprint] = (
        alias: alias,
        isOnline: isOnline,
        messageCount: entry.value.length,
        unread: unread,
      );
    }

    // 添加附近在线但尚无聊天记录的设备
    for (final device in nearbyDevices) {
      if (!chatDevices.containsKey(device.fingerprint)) {
        chatDevices[device.fingerprint] = (
          alias: device.alias,
          isOnline: true,
          messageCount: 0,
          unread: false,
        );
      }
    }

    // 按在线状态排序（在线设备排在前面）
    final sortedDevices = chatDevices.entries.toList()
      ..sort((a, b) => b.value.isOnline.toString().compareTo(a.value.isOnline.toString()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网聊天'),
        actions: [
          if (chatState.messagesByDevice.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: '清除所有聊天记录',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清除所有聊天记录'),
                    content: const Text('确定要清除所有设备的聊天记录吗？此操作不可撤销。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.notifier(chatProvider).clearAllChats();
                          Navigator.pop(context);
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: sortedDevices.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '暂无可用设备',
                    style: TextStyle(color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '请在发送页面发现设备后开始聊天',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: sortedDevices.length,
              itemBuilder: (context, index) {
                final entry = sortedDevices[index];
                final fingerprint = entry.key;
                final info = entry.value;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: info.isOnline
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.grey.shade300,
                    child: Icon(
                      info.isOnline ? Icons.devices : Icons.devices_other,
                      color: info.isOnline
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Colors.grey,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(info.alias),
                      if (info.isOnline)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: info.messageCount > 0
                      ? Text('${info.messageCount} 条消息')
                      : Text(info.isOnline ? '在线' : '离线'),
                  trailing: info.unread
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '新',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatPage(
                          deviceFingerprint: fingerprint,
                          deviceAlias: info.alias,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
