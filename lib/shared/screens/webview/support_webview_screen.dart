import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class SupportWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const SupportWebViewScreen({
    super.key,
    required this.url,
    this.title = 'Support',
  });

  @override
  State<SupportWebViewScreen> createState() => _SupportWebViewScreenState();
}

class _SupportWebViewScreenState extends State<SupportWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    try {
      _controller =
          WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setNavigationDelegate(
              NavigationDelegate(
                onPageStarted: (String url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = '';
                    });
                  }
                },
                onPageFinished: (String url) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
                onWebResourceError: (WebResourceError error) {
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                      _errorMessage =
                          'Failed to load support chat: ${error.description}';
                    });
                  }
                  AppLogger.error('WebView error: ${error.description}');
                },
              ),
            )
            ..loadRequest(Uri.parse(widget.url));

      AppLogger.info('Initialized WebView for support chat: ${widget.url}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize support chat: $e';
        });
      }
      AppLogger.error('Failed to initialize WebView: $e');
    }
  }

  void _retry() {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: BasilIcon(
            'caret-left-outline',
            color: Theme.of(context).colorScheme.onSurface,
            size: 24.sp,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (_errorMessage.isEmpty)
            WebViewWidget(controller: _controller)
          else
            _buildErrorWidget(),
          if (_isLoading) _buildLoadingWidget(),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(height: 16.h),
            Text(
              'Loading Support Chat...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please wait while we connect you to our support team',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14.sp,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: EdgeInsets.all(24.w),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: Theme.of(context).colorScheme.error,
              size: 64.sp,
            ),
            SizedBox(height: 24.h),
            Text(
              'Connection Error',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              _errorMessage,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 16.sp,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32.h),
            ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              child: Text(
                'Try Again',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
