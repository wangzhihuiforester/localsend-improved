import 'dart:async';

import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/web/web_send_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_app/provider/network/server/controller/send_controller.dart';
import 'package:localsend_app/provider/network/server/server_utils.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/alias_generator.dart';
import 'package:localsend_isolates/constants.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/dto/multicast_dto.dart';
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/rust/api/server.dart' show WebI18n, WebParams, WebSendParams;
import 'package:localsend_isolates/util/rust.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('Server');

/// This provider runs the server and provides the current server state.
/// It is a singleton provider, so only one server can be running at a time.
/// The server state is null if the server is not running.
/// The server can receive files (since v1) and send files (since v2).
///
/// The HTTP server itself runs in Rust (inside the server isolate); this
/// provider starts it, listens to its events and holds the resulting state.
final serverProvider = NotifierProvider<ServerService, ServerState?>(
  (ref) {
    return ServerService();
  },
  onChanged: (_, next, ref) {
    final settings = ref.read(settingsProvider);
    final syncState = ref.read(parentIsolateProvider).syncState;
    final syncStatePrev = (syncState.alias, syncState.port, syncState.protocol, syncState.serverRunning, syncState.download);
    final syncStateNext = (
      next?.alias ?? settings.alias,
      next?.port ?? settings.port,
      (next?.https ?? settings.https) ? ProtocolType.https : ProtocolType.http,
      next != null,
      next?.webSendState != null,
    );

    if (syncStatePrev == syncStateNext) {
      return;
    }

    ref
        .redux(parentIsolateProvider)
        .dispatch(
          IsolateSyncServerStateAction(
            alias: syncStateNext.$1,
            port: syncStateNext.$2,
            protocol: syncStateNext.$3,
            serverRunning: syncStateNext.$4,
            download: syncStateNext.$5,
          ),
        );
  },
);

class ServerService extends Notifier<ServerState?> {
  late final _serverUtils = ServerUtils(
    refFunc: () => ref,
    getState: () => state!,
    getStateOrNull: () => state,
    setState: (builder) => state = builder(state),
  );

  late final _receiveController = ReceiveController(_serverUtils);
  late final _sendController = SendController(_serverUtils);

  StreamSubscription<HttpServerEvent>? _subscription;

  ServerService();

  @override
  ServerState? init() {
    return null;
  }

  /// The default (equality) strategy runs the dart_mappable deep equality which
  /// walks the whole files map on every change, making state updates O(n) per received file.
  @override
  bool updateShouldNotify(ServerState? prev, ServerState? next) => !identical(prev, next);

  /// The debug observer stringifies the state on every change,
  /// so large file maps must be summarized to keep transfers responsive in debug mode.
  @override
  String describeState(ServerState? state) {
    final session = state?.session;
    if (session == null || session.files.length <= 10) {
      return state.toString();
    }
    return state!.copyWith(session: session.copyWith(files: {})).toString().replaceFirst('files: {}', 'files: <${session.files.length} files>');
  }

  /// Starts the server from user settings.
  Future<ServerState?> startServerFromSettings() async {
    final settings = ref.read(settingsProvider);
    return startServer(
      alias: settings.alias,
      port: settings.port,
      https: settings.https,
    );
  }

  /// Starts the server.
  /// Passing a [webSendState] additionally serves the web send (download) API.
  /// Passing [webUpload] serves the upload page so web browsers can upload files.
  /// [webPin] protects the active web share mode: the download page in send mode;
  /// in upload mode, it replaces the receive pin from settings.
  Future<ServerState?> startServer({
    required String alias,
    required int port,
    required bool https,
    WebSendState? webSendState,
    bool webUpload = false,
    String? webPin,
  }) async {
    if (state != null) {
      _logger.info('Server already running.');
      return null;
    }

    alias = alias.trim();
    if (alias.isEmpty) {
      alias = generateRandomAlias();
    }

    if (port < 0 || port > 65535) {
      port = defaultPort;
    }

    _logger.info('Starting server...');

    // The server isolate derives its configuration from the sync state,
    // so it must be published before the start task.
    _syncServerState(alias: alias, port: port, https: https, serverRunning: true, download: webSendState != null);

    final settings = ref.read(settingsProvider);
    final events = ref
        .redux(parentIsolateProvider)
        .dispatchTakeResult(
          IsolateHttpServerStartAction(
            pin: webUpload ? webPin : settings.receivePin,
            verifyChecksums: settings.verifyChecksums,
            web: webSendState != null || webUpload
                ? WebParams(
                    send: webSendState != null
                        ? WebSendParams(
                            files: {
                              for (final entry in webSendState.files.entries) entry.key: entry.value.file.toRust(),
                            },
                            pin: webPin,
                          )
                        : null,
                    upload: webUpload,
                    i18N: WebI18n(
                      waiting: t.web.waiting,
                      enterPin: t.web.enterPin,
                      invalidPin: t.web.invalidPin,
                      tooManyAttempts: t.web.tooManyAttempts,
                      rejected: t.web.rejected,
                      uploadRejected: t.sendPage.rejected,
                      busy: t.sendPage.busy,
                      files: t.web.files,
                      fileName: t.web.fileName,
                      size: t.web.size,
                    ),
                  )
                : null,
            showToken: settings.showToken,
          ),
        );

    final started = Completer<void>();
    final subscription = events.listen(
      (event) {
        if (event is HttpServerStartedEvent) {
          if (!started.isCompleted) {
            started.complete();
          }
          return;
        }
        _handleEvent(event);
      },
      onError: (Object error) {
        if (!started.isCompleted) {
          started.completeError(error);
        } else {
          _logger.severe('HTTP server error: $error');
        }
      },
    );

    try {
      await started.future;
    } catch (e) {
      await subscription.cancel();
      _syncServerState(alias: alias, port: port, https: https, serverRunning: false, download: false);
      _logger.warning('Failed to start server', e);
      rethrow;
    }

    _subscription = subscription;

    final newServerState = ServerState(
      alias: alias,
      port: port,
      https: https,
      session: null,
      webSendState: webSendState,
      webUpload: webUpload,
      webPin: webSendState != null || webUpload ? webPin : null,
    );

    state = newServerState;
    _logger.info('Server started. (Port: $port, ${https ? 'HTTPS' : 'HTTP'} only)');
    return newServerState;
  }

  Future<void> stopServer() async {
    _logger.info('Stopping server...');
    await _subscription?.cancel();
    _subscription = null;
    await ref.redux(parentIsolateProvider).dispatchAsync(IsolateHttpServerStopAction());
    state = null;
    _logger.info('Server stopped.');
  }

  Future<ServerState?> restartServerFromSettings() async {
    await stopServer();
    return await startServerFromSettings();
  }

  Future<ServerState?> restartServer({
    required String alias,
    required int port,
    required bool https,
    WebSendState? webSendState,
    bool webUpload = false,
    String? webPin,
  }) async {
    await stopServer();
    return await startServer(alias: alias, port: port, https: https, webSendState: webSendState, webUpload: webUpload, webPin: webPin);
  }

  Future<void> acceptFileRequest(Map<String, String> fileNameMap) async {
    await _receiveController.acceptFileRequest(fileNameMap);
  }

  void declineFileRequest() {
    _receiveController.declineFileRequest();
  }

  /// Updates the destination directory for the current session.
  void setSessionDestinationDir(String destinationDirectory) {
    _receiveController.setSessionDestinationDir(destinationDirectory);
  }

  /// Updates the save to gallery setting for the current session.
  void setSessionSaveToGallery(bool saveToGallery) {
    _receiveController.setSessionSaveToGallery(saveToGallery);
  }

  /// In addition to [closeSession], this method also cancels incoming requests.
  void cancelSession() {
    _receiveController.cancelSession();
  }

  /// Clears the session.
  void closeSession() {
    _receiveController.closeSession();
  }

  /// Restarts the server with web send (the download API) enabled for [files].
  /// The auto accept setting of a previous web send state is kept.
  Future<void> restartServerWithWebSend({
    required String alias,
    required int port,
    required bool https,
    required List<CrossFile> files,
    String? webPin,
  }) async {
    final webSendState = await _sendController.buildWebSendState(files: files);
    await restartServer(alias: alias, port: port, https: https, webSendState: webSendState, webPin: webPin);
  }

  /// Updates the pin of the active web share mode (download or upload page).
  /// The pin is enforced by the Rust server, so the server is restarted.
  Future<void> setWebPin(String? pin) async {
    final current = state;
    if (current == null || (current.webSendState == null && !current.webUpload) || current.webPin == pin) {
      return;
    }

    await restartServer(
      alias: current.alias,
      port: current.port,
      https: current.https,
      webSendState: current.webSendState?.copyWith(sessions: {}),
      webUpload: current.webUpload,
      webPin: pin,
    );
  }

  /// Updates the auto accept setting for web send.
  void setWebSendAutoAccept(bool autoAccept) {
    state = state?.copyWith(
      webSendState: state?.webSendState?.copyWith(
        autoAccept: autoAccept,
      ),
    );
  }

  /// Accepts the web send request.
  void acceptWebSendRequest(String sessionId) {
    _sendController.acceptRequest(sessionId);
  }

  /// Declines the web send request.
  void declineWebSendRequest(String sessionId) {
    _sendController.declineRequest(sessionId);
  }

  void _handleEvent(HttpServerEvent event) {
    switch (event) {
      case HttpServerStartedEvent():
        break;
      case HttpServerRegisterEvent():
        // ignore: discarded_futures
        _receiveController.onRegister(event);
      case HttpServerPrepareUploadEvent():
        // ignore: discarded_futures
        _receiveController.onPrepareUpload(event);
      case HttpServerFileUploadEvent():
        _receiveController.onFileUpload(event);
      case HttpServerFileUploadProgressEvent():
        _receiveController.onFileUploadProgress(event);
      case HttpServerFileUploadResultEvent():
        // ignore: discarded_futures
        _receiveController.onFileUploadResult(event);
      case HttpServerSessionEndEvent():
        _receiveController.onSessionEnd(event);
      case HttpServerPrepareUploadAbortedEvent():
        _receiveController.onPrepareUploadAborted(event);
      case HttpServerCancelReceivedEvent():
        _receiveController.onCancelReceived(event);
      case HttpServerShowEvent():
        _receiveController.onShow(event);
      case HttpServerWebPrepareDownloadEvent():
        _sendController.onPrepareDownload(event);
      case HttpServerWebFileDownloadEvent():
        // ignore: discarded_futures
        _sendController.onFileDownload(event);
    }
  }

  void _syncServerState({
    required String alias,
    required int port,
    required bool https,
    required bool serverRunning,
    required bool download,
  }) {
    ref
        .redux(parentIsolateProvider)
        .dispatch(
          IsolateSyncServerStateAction(
            alias: alias,
            port: port,
            protocol: https ? ProtocolType.https : ProtocolType.http,
            serverRunning: serverRunning,
            download: download,
          ),
        );
  }

  /// 发送聊天消息到目标设备。
  ///
  /// 通过 HTTP register 请求将聊天消息发送到局域网内的目标设备。
  /// 消息内容使用 `LS_CHAT:` 前缀编码在 alias 字段中传输，
  /// 接收端可通过此前缀识别并解析聊天消息。
  ///
  /// 由于 serverProvider 使用 NotifierProvider 模式（而非 ReduxProvider），
  /// 此方法直接在 [ServerService] 上调用，而非通过 ReduxAction 派发。
  /// [SendChatMessageAction] 作为参数对象传递。
  Future<void> sendChatMessage(SendChatMessageAction action) async {
    // 从附近设备列表中查找目标设备
    final devices = ref.read(nearbyDevicesProvider).devices;
    final device = devices[action.deviceFingerprint];

    if (device == null || device.ip == null) {
      throw '设备不在线';
    }

    _logger.info('Sending chat message to ${device.alias} (${device.ip})');

    // 获取本机设备信息，用于构建 HTTP 请求
    final originDevice = ref.read(deviceFullInfoProvider);

    // 使用 pinned HTTP 客户端发送请求到目标设备
    // 客户端已绑定目标设备的证书指纹，确保 TLS 安全
    final client = ref.read(httpProvider).pinnedTo(action.deviceFingerprint);

    // 构建 RegisterDto，将聊天消息编码在 alias 字段中
    // 使用 LS_CHAT: 前缀标识这是一条聊天消息而非普通注册请求
    final payload = rust_model.RegisterDto(
      alias: 'LS_CHAT:${action.message}',
      version: originDevice.version,
      deviceModel: originDevice.deviceModel,
      deviceType: originDevice.deviceType.toRust(),
      token: originDevice.fingerprint,
      port: originDevice.port,
      protocol: originDevice.getProtocolType(),
      hasWebInterface: originDevice.download,
    );

    await client.register(
      protocol: device.getProtocolType(),
      ip: device.ip!,
      port: device.port,
      payload: payload,
    );
  }
}

/// 聊天消息发送参数类。
///
/// 由于 serverProvider 使用 NotifierProvider 模式（而非 ReduxProvider），
/// 无法使用传统 ReduxAction 的 dispatch 机制。
/// 此类作为参数对象，传递给 [ServerService.sendChatMessage] 方法，
/// 封装了发送聊天消息所需的全部参数。
///
/// 示例用法：
/// ```dart
/// await ref.notifier(serverProvider).sendChatMessage(
///   SendChatMessageAction(
///     deviceFingerprint: '...',
///     alias: 'My Device',
///     message: 'Hello!',
///     timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
///   ),
/// );
/// ```
class SendChatMessageAction {
  /// 目标设备的指纹（唯一标识）
  final String deviceFingerprint;

  /// 发送方的设备别名
  final String alias;

  /// 聊天消息内容
  final String message;

  /// 消息时间戳（Unix 秒）
  final int timestamp;

  SendChatMessageAction({
    required this.deviceFingerprint,
    required this.alias,
    required this.message,
    required this.timestamp,
  });
}
