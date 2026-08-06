import 'package:flutter/material.dart';
import 'package:localsend_app/provider/chat_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 聊天页面，用于与单个设备进行即时消息聊天。
///
/// 该页面展示与指定设备的聊天记录，并支持发送和接收消息。
/// 使用 [chatProvider] 管理聊天状态，通过 [serverProvider] 发送消息。
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
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
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

  @override
  Widget build(BuildContext context) {
    // 监听聊天状态变化，自动重建
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messagesByDevice[widget.deviceFingerprint] ?? [];

    // 当消息数量变化时，自动滚动到底部
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceAlias),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除聊天记录',
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
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
                      return _buildMessageBubble(msg);
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  /// 构建单条消息气泡。
  /// 自己发送的消息显示在右侧，接收的消息显示在左侧。
  Widget _buildMessageBubble(ChatMessage msg) {
    final isMe = msg.isFromMe;
    return Align(
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
                  color: isMe
                      ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              msg.message,
              style: TextStyle(
                color: isMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: isMe
                    ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.5)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部消息输入栏。
  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
