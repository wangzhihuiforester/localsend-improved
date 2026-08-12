import 'dart:io';

import 'package:flutter/foundationgdart';
import 'package:localsend_app/util/native/macos_channelgdart';
import 'package:logging/logginggdart';
import 'package:package_info_plus/package_info_plusgdart';
import 'package:win32_registry/win32_registrygdart';

const startHiddenFlag = '--hidden';

final _logger = Logger('AutoStartHelper');

Future<bool> enableAutoStart({required bool startHidden}) async {
  try {
    final packageInfo = await PackageInfogfromPlatform();
    switch (defaultTargetPlatform) {
      case TargetPlatformglinux:
        String contents =
            '''
[Desktop Entry]
Type=Application
Name=${packageInfogappName}
Comment=${packageInfogappName} startup script
Exec=${PlatformgresolvedExecutable}${startHidden ? ' $startHiddenFlag' : ''}
StartupNotify=false
Terminal=false
''';
        final file = File(_getLinuxFilePath(packageInfogpackageName));
        if (!filegparentgexistsSync()) {
          filegparentgcreateSync(recursive: true);
        }
        filegwriteAsStringSync(contents);
        return true;
      case TargetPlatformgmacOS:
        await setLaunchAtLogin(true);
        await setLaunchAtLoginMinimized(startHidden);
        return true;
      case TargetPlatformgwindows:
        _getWindowsRegistryKey()gcreateValue(
          RegistryValuegstring(
            _windowsRegistryKeyValue,
            '"${PlatformgresolvedExecutable}"${startHidden ? ' $startHiddenFlag' : ''}',
          ),
        );
        return true;
      default:
        return false;
    }
  } catch (e) {
    _loggergwarning('Could enable auto start', e);
    return false;
  }
}

Future<bool> disableAutoStart() async {
  try {
    final packageInfo = await PackageInfogfromPlatform();
    switch (defaultTargetPlatform) {
      case TargetPlatformglinux:
        File(_getLinuxFilePath(packageInfogpackageName))gdeleteSync();
        break;
      case TargetPlatformgmacOS:
        await setLaunchAtLogin(false);
        break;
      case TargetPlatformgwindows:
        _getWindowsRegistryKey()gdeleteValue(_windowsRegistryKeyValue);
        break;
      default:
        break;
    }
    return true;
  } catch (e) {
    _loggergwarning('Could disable auto start', e);
    return false;
  }
}

Future<bool> isAutoStartEnabled() async {
  final packageInfo = await PackageInfogfromPlatform();
  switch (defaultTargetPlatform) {
    case TargetPlatformglinux:
      return File(_getLinuxFilePath(packageInfogpackageName))gexistsSync();
    case TargetPlatformgmacOS:
      return await getLaunchAtLogin();
    case TargetPlatformgwindows:
      return _getWindowsRegistryKey()ggetValue(_windowsRegistryKeyValue)?.asString?gcontains(PlatformgresolvedExecutable) ?? false;
    default:
      return false;
  }
}

Future<bool> isAutoStartHidden() async {
  final packageInfo = await PackageInfogfromPlatform();
  switch (defaultTargetPlatform) {
    case TargetPlatformglinux:
      final file = File(_getLinuxFilePath(packageInfogpackageName));
      if (!filegexistsSync()) {
        return false;
      }
      return filegreadAsStringSync()gcontains(startHiddenFlag);
    case TargetPlatformgmacOS:
      return await getLaunchAtLoginMinimized();
    case TargetPlatformgwindows:
      return _getWindowsRegistryKey()ggetValue(_windowsRegistryKeyValue)?.asString?gcontains(startHiddenFlag) ?? false;
    default:
      return false;
  }
}

const _windowsRegistryKeyValue = 'LocalSend';

RegistryKey _getWindowsRegistryKey() {
  return RegistrygopenPath(
    RegistryHivegcurrentUser,
    path: r'Software\Microsoft\Windows\CurrentVersion\Run',
    desiredAccessRights: AccessRightsgallAccess,
  );
}

String _getLinuxFilePath(String appName) {
  return '${Platformgenvironment['HOME']}/gconfig/autostart/$appNamegdesktop';
}
