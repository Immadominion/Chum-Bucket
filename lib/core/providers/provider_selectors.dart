import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Utility class for optimized provider selectors to reduce unnecessary rebuilds
class ProviderSelectors {
  /// Generic selector for specific properties to prevent unnecessary rebuilds
  static Selector<T, R> select<T extends ChangeNotifier, R>(
    R Function(T provider) selector, {
    required Widget Function(BuildContext context, R value, Widget? child)
    builder,
    Widget? child,
    bool Function(R previous, R next)? shouldRebuild,
  }) {
    return Selector<T, R>(
      selector: (_, provider) => selector(provider),
      builder: builder,
      child: child,
      shouldRebuild: shouldRebuild,
    );
  }

  /// Boolean selector with custom shouldRebuild logic
  static Selector<T, bool> selectBool<T extends ChangeNotifier>(
    bool Function(T provider) selector, {
    required Widget Function(BuildContext context, bool value, Widget? child)
    builder,
    Widget? child,
  }) {
    return Selector<T, bool>(
      selector: (_, provider) => selector(provider),
      builder: builder,
      child: child,
      shouldRebuild: (previous, next) => previous != next,
    );
  }

  /// String selector with null-safe comparison
  static Selector<T, String?> selectString<T extends ChangeNotifier>(
    String? Function(T provider) selector, {
    required Widget Function(BuildContext context, String? value, Widget? child)
    builder,
    Widget? child,
  }) {
    return Selector<T, String?>(
      selector: (_, provider) => selector(provider),
      builder: builder,
      child: child,
      shouldRebuild: (previous, next) => previous != next,
    );
  }

  /// Loading state selector for UI optimization
  static Selector<T, bool> selectIsLoading<T extends ChangeNotifier>(
    bool Function(T provider) selector, {
    required Widget Function(
      BuildContext context,
      bool isLoading,
      Widget? child,
    )
    builder,
    Widget? child,
  }) {
    return selectBool<T>(selector, builder: builder, child: child);
  }

  /// Error state selector
  static Selector<T, String?> selectError<T extends ChangeNotifier>(
    String? Function(T provider) selector, {
    required Widget Function(BuildContext context, String? error, Widget? child)
    builder,
    Widget? child,
  }) {
    return selectString<T>(selector, builder: builder, child: child);
  }

  /// Double/numeric value selector with precision-based comparison
  static Selector<T, double> selectDouble<T extends ChangeNotifier>(
    double Function(T provider) selector, {
    required Widget Function(BuildContext context, double value, Widget? child)
    builder,
    Widget? child,
    double precision = 0.01,
  }) {
    return Selector<T, double>(
      selector: (_, provider) => selector(provider),
      builder: builder,
      child: child,
      shouldRebuild: (previous, next) => (previous - next).abs() >= precision,
    );
  }

  /// Combined state selector for multiple properties
  static Selector<T, Map<String, dynamic>>
  selectCombined<T extends ChangeNotifier>(
    Map<String, dynamic> Function(T provider) selector, {
    required Widget Function(
      BuildContext context,
      Map<String, dynamic> state,
      Widget? child,
    )
    builder,
    Widget? child,
    List<String>? watchKeys, // Only rebuild if these keys change
  }) {
    return Selector<T, Map<String, dynamic>>(
      selector: (_, provider) => selector(provider),
      builder: builder,
      child: child,
      shouldRebuild: (previous, next) {
        if (watchKeys != null) {
          // Only check specific keys if provided
          return watchKeys.any((key) => previous[key] != next[key]);
        }
        // Otherwise check all values
        return !_mapsEqual(previous, next);
      },
    );
  }

  /// Helper method to compare maps for equality
  static bool _mapsEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (!map2.containsKey(key) || map1[key] != map2[key]) {
        return false;
      }
    }
    return true;
  }
}

/// Extension on BuildContext for cleaner selector usage
extension ProviderSelectorExtension on BuildContext {
  /// Select a specific value from a provider
  R select<T extends ChangeNotifier, R>(R Function(T provider) selector) {
    final provider = Provider.of<T>(this, listen: false);
    return selector(provider);
  }

  /// Watch a specific value from a provider
  R watch<T extends ChangeNotifier, R>(R Function(T provider) selector) {
    final provider = Provider.of<T>(this);
    return selector(provider);
  }
}

/// Extension to add let function for functional programming style
extension LetExtension<T> on T {
  R let<R>(R Function(T) operation) => operation(this);
}
