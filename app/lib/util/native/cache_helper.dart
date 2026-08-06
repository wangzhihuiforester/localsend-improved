// ignore_for_file: discarded_futures, unawaited_futures

import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/util/file_path_helper.dart';
import 'package:localsend_isolates/util/logger.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_foundation/path_provider_foundation.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

final _logger = Logger('ClearCacheAction');

/// Clears the cache.
/// It runs on a separate isolate to avoid blocking the UI.
class ClearCacheAction extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    // The token statement must be outside the lambda because it must be executed on the root isolate.
    final token = ServicesBinding.rootIsolateToken!;
    await Isolate.run(() => _clear(token));
  }
}

Future<void> _clear(RootIsolateToken token) async {
  initLogger(Level.ALL);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  // 每个子任务都自行捕获异常，确保单个清理步骤失败不会中断其他步骤，
  // 同时保证所有删除操作都被 await 完成。
  final futures = (
    FilePicker.clearTemporaryFiles(),
    PhotoManager.clearFileCache(),
    // 递归清理临时目录（包括子目录中的文件），并删除清空后的空目录
    () async {
      if (!checkPlatform([TargetPlatform.iOS, TargetPlatform.android])) return;
      try {
        final cacheDir = await getTemporaryDirectory();
        await _clearDirectoryRecursive(cacheDir);
      } catch (e) {
        _logger.warning('Failed to clear temp directory: $e');
      }
    }(),
    // 清理 web-send-* 临时文件（web 发送场景写入缓存的内存文件），全平台生效
    () async {
      try {
        final cacheDir = await getTemporaryDirectory();
        await _clearWebSendTempFiles(cacheDir);
      } catch (e) {
        _logger.warning('Failed to clear web-send temp files: $e');
      }
    }(),
    // iOS App Group 目录清理：仅删除非隐藏文件（保留目录与隐藏文件）
    () async {
      if (!checkPlatform([TargetPlatform.iOS])) return;
      try {
        final directoryPath = await PathProviderFoundation().getContainerPath(
          appGroupIdentifier: 'group.org.localsend.localsendApp',
        );
        if (directoryPath == null) {
          _logger.warning('Failed to get app group directory');
          return;
        }

        final directory = Directory(directoryPath);

        // delete contents of the directory (only files, not directories)
        await for (final entry in directory.list(recursive: false, followLinks: false)) {
          if (entry is File && !entry.path.fileName.startsWith('.')) {
            _logger.info('Deleting ${entry.path}');
            await entry.delete();
          }
        }
      } catch (e) {
        _logger.warning('Failed to clear app group directory: $e');
      }
    }(),
  ).wait;

  try {
    await futures;
  } catch (e) {
    _logger.warning('Failed to clear cache: $e');
  }
}

/// 递归清理目录：删除其中所有文件，递归清理子目录后删除已清空的空目录。
/// 所有删除操作均被 await，单个实体删除失败会被忽略以继续清理其余内容。
Future<void> _clearDirectoryRecursive(Directory dir) async {
  if (!await dir.exists()) return;
  await for (final entity in dir.list(recursive: false)) {
    try {
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await _clearDirectoryRecursive(entity);
        await entity.delete();
      }
    } catch (e) {
      // 忽略删除失败，继续清理其他文件
    }
  }
}

/// 清理 web-send-* 临时文件。
/// 这些文件由 web 发送功能将内存中的内容（如文本消息）物化到缓存目录后产生。
Future<void> _clearWebSendTempFiles(Directory cacheDir) async {
  if (!await cacheDir.exists()) return;
  await for (final entity in cacheDir.list(recursive: false)) {
    if (entity is File && entity.path.fileName.startsWith('web-send-')) {
      try {
        await entity.delete();
      } catch (e) {
        // 忽略删除失败，继续清理其他文件
      }
    }
  }
}
