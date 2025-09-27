import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/app_logger.dart';
import '../../shared/screens/webview/support_webview_screen.dart';

class ChatService {
  static String get tawkUrl =>
      dotenv.env['TAWK_TO_URL'] ??
      'https://tawk.to/chat/68c3692a2d363c192cbaaea5/1j4tl5k2i';

  /// Opens Tawk.to chat in in-app webview
  static Future<void> openChat(BuildContext context) async {
    try {
      AppLogger.info('Opening Tawk.to chat in in-app browser');

      // Try in-app webview first
      final Uri chatUrl = Uri.parse(tawkUrl);

      if (await canLaunchUrl(chatUrl)) {
        await launchUrl(
          chatUrl,
          mode: LaunchMode.inAppWebView,
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
        AppLogger.info('Opened chat in in-app browser');
      } else {
        // Fallback to WebView screen
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (context) =>
                      SupportWebViewScreen(url: tawkUrl, title: 'Support Chat'),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to open chat: $e');
      // Fallback to external browser
      await _openChatExternal();
    }
  }

  /// Fallback method to open chat in external browser
  static Future<void> _openChatExternal() async {
    try {
      final Uri chatUrl = Uri.parse(tawkUrl);

      if (await canLaunchUrl(chatUrl)) {
        await launchUrl(chatUrl, mode: LaunchMode.externalApplication);
        AppLogger.info('Opened Tawk.to chat in external browser');
      } else {
        AppLogger.error('Could not launch chat URL: $tawkUrl');
      }
    } catch (e) {
      AppLogger.error('Failed to open chat: $e');
    }
  }

  /// Opens chat with a pre-filled message
  static Future<void> openChatWithMessage(String message) async {
    try {
      // Encode the message for URL
      final encodedMessage = Uri.encodeComponent(message);
      final chatUrlWithMessage = '$tawkUrl?message=$encodedMessage';

      final Uri chatUrl = Uri.parse(chatUrlWithMessage);

      if (await canLaunchUrl(chatUrl)) {
        await launchUrl(chatUrl, mode: LaunchMode.externalApplication);
        AppLogger.info('Opened Tawk.to chat with pre-filled message');
      } else {
        AppLogger.error('Could not launch chat URL: $chatUrlWithMessage');
      }
    } catch (e) {
      AppLogger.error('Failed to open chat with message: $e');
    }
  }
}
