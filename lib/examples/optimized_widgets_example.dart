import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/providers/providers.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/shared/widgets/widgets.dart';

/// Optimized login button that only rebuilds when necessary
class OptimizedLoginButton extends StatelessWidget {
  final String email;
  final VoidCallback? onPressed;

  const OptimizedLoginButton({super.key, required this.email, this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Only rebuild when loading state changes, not on every provider change
    return ProviderSelectors.selectBool<AuthProvider>(
      (provider) => provider.isLoading,
      builder: (context, isLoading, _) {
        return PrimaryActionButton(
          text: 'Send Verification Code',
          onPressed: isLoading ? null : onPressed,
          isLoading: isLoading,
        );
      },
    );
  }
}

/// Optimized error display that only rebuilds when error changes
class OptimizedErrorDisplay extends StatelessWidget {
  const OptimizedErrorDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderSelectors.selectString<AuthProvider>(
      (provider) => provider.errorMessage,
      builder: (context, errorMessage, _) {
        if (errorMessage == null) return const SizedBox.shrink();

        return Container(
          padding: EdgeInsets.all(12.r),
          margin: EdgeInsets.only(bottom: 16.h),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 20.sp,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  errorMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14.sp,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Optimized user avatar that only rebuilds when user changes
class OptimizedUserAvatar extends StatelessWidget {
  const OptimizedUserAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderSelectors.select<AuthProvider, String?>(
      (provider) => provider.currentUser?.id,
      builder: (context, userId, _) {
        if (userId == null) {
          return const Icon(Icons.account_circle, size: 40);
        }

        return AppAvatar(initials: userId.substring(0, 2).toUpperCase());
      },
    );
  }
}

/// Combined state selector example - only rebuilds when specific values change
class OptimizedAuthStatus extends StatelessWidget {
  const OptimizedAuthStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderSelectors.selectCombined<AuthProvider>(
      (provider) => {
        'isAuthenticated': provider.isAuthenticated,
        'isLoading': provider.isLoading,
        'isInitialized': provider.isInitialized,
      },
      builder: (context, state, _) {
        final isAuthenticated = state['isAuthenticated'] as bool;
        final isLoading = state['isLoading'] as bool;
        final isInitialized = state['isInitialized'] as bool;

        if (!isInitialized) {
          return Row(
            children: [
              SizedBox(
                width: 16.w,
                height: 16.h,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8.w),
              Text('Initializing...', style: TextStyle(fontSize: 14.sp)),
            ],
          );
        }

        if (isLoading) {
          return Row(
            children: [
              SizedBox(
                width: 16.w,
                height: 16.h,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8.w),
              Text('Signing in...', style: TextStyle(fontSize: 14.sp)),
            ],
          );
        }

        return Row(
          children: [
            Icon(
              isAuthenticated ? Icons.check_circle : Icons.circle_outlined,
              color: isAuthenticated ? Colors.green : Colors.grey,
              size: 16.sp,
            ),
            SizedBox(width: 8.w),
            Text(
              isAuthenticated ? 'Signed in' : 'Not signed in',
              style: TextStyle(fontSize: 14.sp),
            ),
          ],
        );
      },
      // Only rebuild if these specific keys change
      watchKeys: ['isAuthenticated', 'isLoading', 'isInitialized'],
    );
  }
}

/// Example of using context extensions for cleaner code
class OptimizedQuickActions extends StatelessWidget {
  const OptimizedQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    // Use extension methods for cleaner code
    final isAuthenticated = context.watch<AuthProvider, bool>(
      (provider) => provider.isAuthenticated,
    );

    return Row(
      children: [
        if (!isAuthenticated) ...[
          SecondaryActionButton(
            text: 'Sign In',
            onPressed: () {
              // Navigate to sign in
            },
          ),
          SizedBox(width: 8.w),
        ],
        TertiaryActionButton(
          text: isAuthenticated ? 'Profile' : 'Learn More',
          onPressed: () {
            // Navigate based on auth state
          },
        ),
      ],
    );
  }
}
