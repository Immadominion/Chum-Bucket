import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/app_logger.dart';

class ChatService {
  static String get tawkUrl => dotenv.env['TAWK_TO_URL'] ?? 'https://tawk.to/chat/68c3692a2d363c192cbaaea5/1j4tl5k2i';

  /// Opens Tawk.to chat in external browser
  /// This avoids Apple's privacy manifest requirements for webview
  static Future<void> openChat() async {
    try {
      final Uri chatUrl = Uri.parse(tawkUrl);
      
      if (await canLaunchUrl(chatUrl)) {
        await launchUrl(
          chatUrl,
          mode: LaunchMode.externalApplication,
        );
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
        await launchUrl(
          chatUrl,
          mode: LaunchMode.externalApplication,
        );
        AppLogger.info('Opened Tawk.to chat with pre-filled message');
      } else {
        AppLogger.error('Could not launch chat URL: $chatUrlWithMessage');
      }
    } catch (e) {
      AppLogger.error('Failed to open chat with message: $e');
    }
  }
}
