import 'package:refena_flutter/refena_flutter.dart';

/// 表示一条聊天消息（接收或发送）。
class ChatMessage {
  final String id;
  final String deviceAlias;
  final String deviceFingerprint;
  final String message;
  final DateTime timestamp;
  final bool isFromMe;

  ChatMessage({
    required this.id,
    required this.deviceAlias,
    required this.deviceFingerprint,
    required this.message,
    required this.timestamp,
    required this.isFromMe,
  });
}

/// 聊天状态，按设备指纹分组存储所有聊天消息。
class ChatState {
  final Map<String, List<ChatMessage>> messagesByDevice;
  final Set<String> unreadDevices;

  ChatState({
    required this.messagesByDevice,
    required this.unreadDevices,
  });

  factory ChatState.initial() => ChatState(
        messagesByDevice: {},
        unreadDevices: {},
      );

  ChatState copyWith({
    Map<String, List<ChatMessage>>? messagesByDevice,
    Set<String>? unreadDevices,
  }) {
    return ChatState(
      messagesByDevice: messagesByDevice ?? this.messagesByDevice,
      unreadDevices: unreadDevices ?? this.unreadDevices,
    );
  }
}

/// 聊天状态管理 Notifier。
/// 负责管理所有设备的聊天消息，包括接收、发送、已读标记和清除。
class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => ChatState.initial();

  /// 添加一条接收到的聊天消息。
  void addIncomingMessage({
    required String deviceAlias,
    required String deviceFingerprint,
    required String message,
    required DateTime timestamp,
  }) {
    final msg = ChatMessage(
      id: '${deviceFingerprint}_${timestamp.millisecondsSinceEpoch}',
      deviceAlias: deviceAlias,
      deviceFingerprint: deviceFingerprint,
      message: message,
      timestamp: timestamp,
      isFromMe: false,
    );
    final list = List<ChatMessage>.from(state.messagesByDevice[deviceFingerprint] ?? []);
    list.add(msg);
    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByDevice);
    newMap[deviceFingerprint] = list;
    final newUnread = Set<String>.from(state.unreadDevices)..add(deviceFingerprint);
    state = state.copyWith(messagesByDevice: newMap, unreadDevices: newUnread);
  }

  /// 添加一条发送的聊天消息。
  void addOutgoingMessage({
    required String deviceAlias,
    required String deviceFingerprint,
    required String message,
  }) {
    final timestamp = DateTime.now();
    final msg = ChatMessage(
      id: '${deviceFingerprint}_${timestamp.millisecondsSinceEpoch}',
      deviceAlias: deviceAlias,
      deviceFingerprint: deviceFingerprint,
      message: message,
      timestamp: timestamp,
      isFromMe: true,
    );
    final list = List<ChatMessage>.from(state.messagesByDevice[deviceFingerprint] ?? []);
    list.add(msg);
    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByDevice);
    newMap[deviceFingerprint] = list;
    state = state.copyWith(messagesByDevice: newMap);
  }

  /// 将指定设备的消息标记为已读。
  void markAsRead(String deviceFingerprint) {
    final newUnread = Set<String>.from(state.unreadDevices)..remove(deviceFingerprint);
    state = state.copyWith(unreadDevices: newUnread);
  }

  /// 清除与指定设备的聊天记录。
  void clearChat(String deviceFingerprint) {
    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByDevice);
    newMap.remove(deviceFingerprint);
    final newUnread = Set<String>.from(state.unreadDevices)..remove(deviceFingerprint);
    state = state.copyWith(messagesByDevice: newMap, unreadDevices: newUnread);
  }

  /// 清除所有聊天记录。
  void clearAllChats() {
    state = ChatState.initial();
  }

  /// 获取指定设备的聊天消息列表。
  List<ChatMessage> getMessages(String deviceFingerprint) {
    return state.messagesByDevice[deviceFingerprint] ?? [];
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>((ref) => ChatNotifier());
