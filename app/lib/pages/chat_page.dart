import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 聊天页面，用于与单个设备进行即时消息聊天。
///
/// 该页面展示与指定设备的聊天记录，并支持发送和接收消息。
/// 使用 [chatProvider] 管理聊天状态，通过 [serverProvider] 发送消息。
/// 聊天记录已持久化存储，即使设备离线也能查看历史记录。
///
/// 复制功能：
/// - 消息内容可长按/鼠标选中复制（SelectableText）
/// - 点击右上角菜单可"复制全部聊天记录"
class ChatPage extends StatefulWidget {
  final String deviceFingerprint;
  final String deviceAlias;

  const ChatPage({
    super.key,
    required this.deviceFingerprint,
    required this.deviceAlias,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with Refena {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 上次显示的消息数量，用于判断是否需要自动滚动到底部。
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    // 进入聊天页面时，将该设备的消息标记为已读
    ref.notifier(chatProvider).markAsRead(widget.deviceFingerprint);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 自动滚动到消息列表底部。
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 发送聊天消息。
  /// 先将消息添加到本地聊天状态，然后通过 HTTP 发送到目标设备。
  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    _messageController.clear();

    final settings = ref.read(settingsProvider);
    final alias = settings.alias;
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 立即将消息添加到本地聊天状态
    ref.notifier(chatProvider).addOutgoingMessage(
      deviceAlias: widget.deviceAlias,
      deviceFingerprint: widget.deviceFingerprint,
      message: message,
    );

    // 通过 HTTP 将消息发送到目标设备
    try {
      await ref.notifier(serverProvider).sendChatMessage(
        SendChatMessageAction(
          deviceFingerprint: widget.deviceFingerprint,
          alias: alias,
          message: message,
          timestamp: timestamp,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败（对方可能不在线）: $e')),
        );
      }
    }
  }

  /// 复制单条消息到剪贴板。
  void _copyMessage(ChatMessage msg) {
    Clipboard.setData(
      ClipboardData(text: '[${_formatTime(msg.timestamp)}] ${msg.deviceAlias}: ${msg.message}'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制消息'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// 复制与当前设备的全部聊天记录到剪贴板。
  void _copyAllMessages(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    final sb = StringBuffer();
    for (final msg in messages) {
      final sender = msg.isFromMe ? '我' : msg.deviceAlias;
      sb.writeln('[${_formatTime(msg.timestamp)}] $sender: ${msg.message}');
    }
    Clipboard.setData(ClipboardData(text: sb.toString().trimRight()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制全部聊天记录'), duration: Duration(seconds: 1)),
      );
    }
  }

  /// 将时间格式化为 HH:mm。
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 清除与当前设备的聊天记录（带确认对话框）。
  void _clearChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除聊天记录'),
        content: const Text('确定要清除与该设备的所有聊天记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.notifier(chatProvider).clearChat(widget.deviceFingerprint);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 长按消息气泡时弹出的操作菜单。
  void _showMessageActions(ChatMessage msg, List<ChatMessage> allMessages) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制本条消息'),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: const Text('复制全部聊天记录'),
              onTap: () {
                Navigator.pop(context);
                _copyAllMessages(allMessages);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听聊天状态变化，自动重建
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messagesByDevice[widget.deviceFingerprint] ?? [];

    // 监听附近设备，判断目标设备是否在线
    final nearbyDevices = ref.watch(nearbyDevicesProvider).devices;
    final isOnline = nearbyDevices.containsKey(widget.deviceFingerprint);

    // 当消息数量变化时，自动滚动到底部
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.deviceAlias),
            Text(
              isOnline ? '在线' : '离线',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: isOnline ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'copyAll':
                  _copyAllMessages(messages);
                case 'clear':
                  _clearChat();
              }
            },
            itemBuilder: (context) => [
              if (messages.isNotEmpty)
                const PopupMenuItem(
                  value: 'copyAll',
                  child: Row(
                    children: [
                      Icon(Icons.copy_all, size: 20),
                      SizedBox(width: 12),
                      Text('复制全部聊天记录'),
                    ],
                  ),
                ),
              if (messages.isNotEmpty)
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20),
                      SizedBox(width: 12),
                      Text('清除聊天记录'),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 离线提示横幅：当设备离线但有聊天记录时显示
          if (!isOnline && messages.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '该设备当前离线，您可以查看历史聊天记录',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      '暂无聊天记录\n发送一条消息开始对话',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(msg, messages);
                    },
                  ),
          ),
          _buildInputBar(isOnline),
        ],
      ),
    );
  }

  /// 构建单条消息气泡。
  /// 自己发送的消息显示在右侧，接收的消息显示在左侧。
  /// 消息正文使用 [SelectableText]，支持鼠标/长按选中复制；
  /// 长按气泡会弹出"复制本条/复制全部"菜单。
  Widget _buildMessageBubble(ChatMessage msg, List<ChatMessage> allMessages) {
    final isMe = msg.isFromMe;
    return GestureDetector(
      onLongPress: () => _showMessageActions(msg, allMessages),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Text(
                  msg.deviceAlias,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 4),
              SelectableText(
                msg.message,
                style: TextStyle(
                  color: isMe
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
                selectionColor: Colors.blue.withOpacity(0.3),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(msg.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.5)
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建底部消息输入栏。
  Widget _buildInputBar(bool isOnline) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: isOnline,
                decoration: InputDecoration(
                  hintText: isOnline ? '输入消息...' : '对方离线，无法发送消息',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: isOnline ? (_) => _sendMessage() : null,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: isOnline ? _sendMessage : null,
            ),
          ],
        ),
      ),
    );
  }
}
