import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:ffbox_edgelink/core/utils/log.dart';
import 'package:path_provider/path_provider.dart';

/// 存储密码的加解密工具。
///
/// 首次需要保存密码时，在 Android 应用私有目录（`/data/data/<package>/files`，
/// 即 `getApplicationSupportDirectory()`）生成一个随机密钥文件 `secret.key`，
/// 用 AES-256-CBC 加密历史记录中保存的密码；其余平台没有可靠的私有目录保证，
/// 回退为明文保存（`encrypt`/`decrypt` 直接返回原文）。
///
/// 密文带 `enc:` 前缀用于区分历史遗留的明文数据，解密失败时返回空串。
class SecretCipher {
  SecretCipher._();

  static const _prefix = 'enc:';
  static const _ivLength = 16;
  static const _keyLength = 32;
  static bool _loaded = false;
  static String? _keyBase64;

  // --- 平台判断与密钥管理 ---

  static bool get _isAndroid => Platform.isAndroid;

  /// 生成指定长度的安全随机字节。
  static Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => Random.secure().nextInt(256)),
      );

  /// 加载或首次生成密钥；非 Android 或失败时返回 null。
  static Future<String?> _loadOrCreateKey() async {
    if (_loaded) return _keyBase64;
    _loaded = true;
    if (!_isAndroid) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/secret.key');
      if (await file.exists()) {
        _keyBase64 = (await file.readAsString()).trim();
      } else {
        _keyBase64 = base64Encode(_randomBytes(_keyLength));
        await file.parent.create(recursive: true);
        await file.writeAsString(_keyBase64!, flush: true);
        logDebug('secretCipher: 已生成密钥文件 secret.key');
      }
      return _keyBase64;
    } catch (e) {
      logDebug('secretCipher: 密钥加载失败 $e');
      _keyBase64 = null;
      return null;
    }
  }

  // --- 加解密 ---

  /// 加密明文；明文为空、非 Android 或失败时返回原文。
  static Future<String> encrypt(String plain) async {
    if (plain.isEmpty) return plain;
    final keyBase64 = await _loadOrCreateKey();
    if (keyBase64 == null) return plain;
    try {
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(base64Decode(keyBase64)), mode: enc.AESMode.cbc),
      );
      final iv = enc.IV(_randomBytes(_ivLength));
      final encrypted = encrypter.encrypt(plain, iv: iv);
      final payload = '${base64Encode(iv.bytes)}.${base64Encode(encrypted.bytes)}';
      return '$_prefix$payload';
    } catch (e) {
      logDebug('secretCipher: 加密失败 $e');
      return plain;
    }
  }

  /// 解密密文；非 `enc:` 前缀视为历史明文原样返回，解密失败返回空串。
  static Future<String> decrypt(String stored) async {
    if (!stored.startsWith(_prefix)) return stored;
    final keyBase64 = await _loadOrCreateKey();
    if (keyBase64 == null) return '';
    try {
      final body = stored.substring(_prefix.length);
      final dot = body.indexOf('.');
      if (dot <= 0) return '';
      final iv = enc.IV(base64Decode(body.substring(0, dot)));
      final encrypted = enc.Encrypted(base64Decode(body.substring(dot + 1)));
      final encrypter = enc.Encrypter(
        enc.AES(enc.Key(base64Decode(keyBase64)), mode: enc.AESMode.cbc),
      );
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      logDebug('secretCipher: 解密失败 $e');
      return '';
    }
  }
}
