import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

Future<void> registerAuthLinkProtocol() async {
  if (!Platform.isWindows) {
    return;
  }

  const scheme = 'io.neurodienst.app';
  final prefix = 'SOFTWARE\\Classes\\$scheme';
  final executable = Platform.resolvedExecutable.replaceAll('"', r'\"');
  final command = '"$executable" "%1"';

  try {
    _setRegistryString(prefix, '', 'URL:NeuroDienst');
    _setRegistryString(prefix, 'URL Protocol', '');
    _setRegistryString('$prefix\\shell\\open\\command', '', command);
  } catch (error) {
    debugPrint('Could not register the NeuroDienst auth link: $error');
  }
}

void _setRegistryString(String key, String valueName, String data) {
  final keyPointer = key.toPcwstr();
  final namePointer = valueName.toPcwstr();
  final dataPointer = data.toPcwstr();

  try {
    final result = RegSetKeyValue(
      HKEY_CURRENT_USER,
      keyPointer,
      namePointer,
      REG_SZ,
      dataPointer,
      dataPointer.length * 2 + 2,
    );

    if (result != ERROR_SUCCESS) {
      throw WindowsException(HRESULT_FROM_WIN32(result));
    }
  } finally {
    free(keyPointer);
    free(namePointer);
    free(dataPointer);
  }
}
