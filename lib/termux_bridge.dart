import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class TermuxBridge {
  static const channel = MethodChannel('com.memplato.app/termux');

  static Future<bool> isTermuxInstalled() async {
    try {
      return await channel.invokeMethod('isTermuxInstalled') ?? false;
    } catch (e) {
      debugPrint('isTermuxInstalled error: $e');
      return false;
    }
  }

  static Future<bool> hasRunCommandPermission() async {
    try {
      return await channel.invokeMethod('hasRunCommandPermission') ?? false;
    } catch (e) {
      debugPrint('hasRunCommandPermission error: $e');
      return false;
    }
  }

  static Future<void> openUrl(String url) async {
    try {
      await channel.invokeMethod('openUrl', {'url': url});
    } catch (e) {
      debugPrint('openUrl error: $e');
    }
  }

  static Future<void> openAppSettings() async {
    try {
      await channel.invokeMethod('openAppSettings');
    } catch (e) {
      debugPrint('openAppSettings error: $e');
    }
  }

  static Future<void> openTermux() async {
    try {
      await channel.invokeMethod('openTermux');
    } catch (e) {
      debugPrint('openTermux error: $e');
    }
  }

  static Future<void> runCommand(String command) async {
    try {
      await channel.invokeMethod('runCommand', {'command': command});
    } catch (e) {
      debugPrint('runCommand error: $e');
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      final result = await channel.invokeMethod<bool>('areNotificationsEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openNotificationSettings() async {
    try {
      await channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  static Future<void> startInstallService() async {
    try {
      await channel.invokeMethod('startInstallService');
    } catch (e) {
      debugPrint('startInstallService error: $e');
    }
  }

  static Future<void> stopInstallService() async {
    try {
      await channel.invokeMethod('stopInstallService');
    } catch (e) {
      debugPrint('stopInstallService error: $e');
    }
  }

  static Future<void> updateNotification(String text) async {
    try {
      await channel.invokeMethod('updateNotification', {'text': text});
    } catch (e) {
      debugPrint('updateNotification error: $e');
    }
  }

  static Future<void> sendBatteryNotification() async {
    try {
      await channel.invokeMethod('sendBatteryNotification');
    } catch (e) {
      debugPrint('sendBatteryNotification error: $e');
    }
  }

  // ✅ НОВИЙ МЕТОД
  static Future<void> sendSuccessNotification() async {
    try {
      await channel.invokeMethod('sendSuccessNotification');
    } catch (e) {
      debugPrint('sendSuccessNotification error: $e');
    }
  }
}