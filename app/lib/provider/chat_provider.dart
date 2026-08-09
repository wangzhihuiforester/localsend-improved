import 'dart:convert';

import 'package:localsend_app/provider/persistence_provider.dart';
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

  /// 序列化为 JSON Map，用于持久化存储。
  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceAlias': deviceAlias,
        'deviceFingerprint': deviceFingerprint,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'isFromMe': isFromMe,
      };

  /// 从 JSON Map 反序列化，用于从持久化存储加载。
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        deviceAlias: json['deviceAlias'] as String,
        deviceFingerprint: json['deviceFingerprint'] as String,
        message: json['message'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isFromMe: json['isFromMe'] as bool,
      );
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
/// 所有消息变更会自动持久化到 SharedPreferences，确保应用重启后聊天记录不丢失。
class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState init() => ChatState.initial();

  /// 从持久化存储加载聊天记录。
  /// 应在应用启动时调用（postInit 阶段），确保之前的聊天记录得以恢复。
  /// 这样即使成员离线，用户依然可以查看历史聊天记录。
  Future<void> loadFromStorage() async {
    final persistence = ref.read(persistenceProvider);
    final raw = persistence.getChatHistoryRaw();
    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final messagesByDevice = <String, List<ChatMessage>>{};
      for (final entry in decoded.entries) {
        final messageList = (entry.value as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
        messagesByDevice[entry.key] = messageList;
      }
      final unreadDevices = (persistence.getChatUnreadDevices() ?? <String>[]).toSet();
      state = ChatState(
        messagesByDevice: messagesByDevice,
        unreadDevices: unreadDevices,
      );
    } catch (e) {
      // 如果反序列化失败，不影响应用正常使用，只是聊天记录为空
      state = ChatState.initial();
    }
  }

  /// 将当前聊天状态持久化到 SharedPreferences。
  /// 在每次状态变更后调用，确保数据不丢失。
  void _saveToStorage() {
    final persistence = ref.read(persistenceProvider);
    final json = jsonEncode({
      for (final entry in state.messagesByDevice.entries)
        entry.key: entry.value.map((m) => m.toJson()).toList(),
    });
    persistence.setChatHistoryRaw(json);
    persistence.setChatUnreadDevices(state.unreadDevices.toList());
  }

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
    _saveToStorage();
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
    _saveToStorage();
  }

  /// 将指定设备的消息标记为已读。
  void markAsRead(String deviceFingerprint) {
    if (!state.unreadDevices.contains(deviceFingerprint)) return;
    final newUnread = Set<String>.from(state.unreadDevices)..remove(deviceFingerprint);
    state = state.copyWith(unreadDevices: newUnread);
    _saveToStorage();
  }

  /// 清除与指定设备的聊天记录。
  void clearChat(String deviceFingerprint) {
    final newMap = Map<String, List<ChatMessage>>.from(state.messagesByDevice);
    newMap.remove(deviceFingerprint);
    final newUnread = Set<String>.from(state.unreadDevices)..remove(deviceFingerprint);
    state = state.copyWith(messagesByDevice: newMap, unreadDevices: newUnread);
    _saveToStorage();
  }

  /// 清除所有聊天记录。
  void clearAllChats() {
    state = ChatState.initial();
    _saveToStorage();
  }

  /// 获取指定设备的聊天消息列表。
  List<ChatMessage> getMessages(String deviceFingerprint) {
    return state.messagesByDevice[deviceFingerprint] ?? [];
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>((ref) => ChatNotifier());
