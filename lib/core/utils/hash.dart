import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 计算字符串的 SHA256 十六进制摘要。
/// FFBox 登录接口要求 passkey 为 SHA256(password)。
String sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();
