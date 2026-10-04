/// Market discovery's controls, in one row: a search field and a filter
/// button (badged with how many filters are on). The button opens a compact
/// sheet — when, topic, sort — and whatever is on shows as one dismissible
/// pill row, only while something is set.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// What discovery is narrowed to. Presentation only: server eligibility still
/// governs every call.
@immutable
class MarketFilters {
  const MarketFilters({
    this.window = MarketDiscoveryWindow.all,
    this.category,
    this.sort = MarketDiscoverySort.closingSoon,
    this.forYou = false,
  });

  final MarketDiscoveryWindow window;

  /// A category slug from the catalog itself, or null for every category.
  final String? category;
  final MarketDiscoverySort sort;

  /// The person's chosen topics first, then everything else. While on, no
  /// single category is selected.
  final bool forYou;

  static const none = MarketFilters();

  /// How many of the three choices differ from their default; the filter
  /// button's badge.
  int get activeCount =>
      (window != MarketDiscoveryWindow.all ? 1 : 0) +
      (forYou || category != null ? 1 : 0) +
      (sort != MarketDiscoverySort.closingSoon ? 1 : 0);

  bool get isEmpty => activeCount == 0;

  MarketFilters withWindow(MarketDiscoveryWindow value) => MarketFilters(
    window: value,
    category: category,
    sort: sort,
    forYou: forYou,
  );

  /// One topic choice: a category, "For you", or neither (every category).
  MarketFilters withTopic({String? category, bool forYou = false}) =>
      MarketFilters(
        window: window,
        category: forYou ? null : category,
        sort: sort,
        forYou: forYou,
      );

  MarketFilters withSort(MarketDiscoverySort value) => MarketFilters(
    window: window,
    category: category,
    sort: value,
    forYou: forYou,
  );

  @override
  bool operator ==(Object other) =>
      other is MarketFilters &&
      other.window == window &&
      other.category == category &&
      other.sort == sort &&
      other.forYou == forYou;

  @override
  int get hashCode => Object.hash(window, category, sort, forYou);
}

/// The one control row: search on the left, filters on the right.
class MarketSearchBar extends StatefulWidget {
  const MarketSearchBar({
    super.key,
    required this.onQueryChanged,
    required this.onFilters,
    this.activeFilters = 0,
    this.fill = AppColors.surface,
    this.hint = 'Search',
  });

  final ValueChanged<String> onQueryChanged;
  final VoidCallback onFilters;

  /// Drawn as a badge on the filter button when above zero.
  final int activeFilters;

  /// The field and button's fill: white on the page, grey inside a sheet.
  final Color fill;
  final String hint;

  @override
  State<MarketSearchBar> createState() => _MarketSearchBarState();
}

class _MarketSearchBarState extends State<MarketSearchBar> {
  // The prototype sets its search field at 12px; 13 keeps typed text legible.
  static final _text = GoogleFonts.montserrat(
    fontSize: 13,
    color: AppColors.textPrimary,
  );
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onQueryChanged('');
    setState(() {});
  }

  OutlineInputBorder _border([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: side,
      );

  @override
  Widget build(BuildContext context) {
    final active = widget.activeFilters;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            onChanged: (value) {
              widget.onQueryChanged(value);
              setState(() {});
            },
            style: _text,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: _text.copyWith(color: AppColors.textSecondary),
              prefixIcon: const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 9, 0),
                child: BasilIcon(
                  'search-outline',
                  size: 19,
                  color: Color(0xFF7B8290),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 42,
                minHeight: 48,
              ),
              suffixIcon:
                  _controller.text.isEmpty
                      ? null
                      : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _clear,
                        icon: const BasilIcon(
                          'cross-outline',
                          size: 18,
                          color: Color(0xFF7B8290),
                        ),
                      ),
              filled: true,
              fillColor: widget.fill,
              contentPadding: const EdgeInsets.fromLTRB(0, 15, 14, 15),
              // Borderless field, as in the prototype; the focus ring stays
              // for keyboard and screen-reader users.
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(
                const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Filters',
          child: Semantics(
            button: true,
            label: active == 0 ? 'Filters' : 'Filters, $active on',
            excludeSemantics: true,
            onTap: widget.onFilters,
            child: Material(
              color: widget.fill,
              borderRadius: BorderRadius.circular(15),
              child: InkWell(
                key: const ValueKey('market-filters-button'),
                borderRadius: BorderRadius.circular(15),
                onTap: widget.onFilters,
                child: SizedBox.square(
                  dimension: 48,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      BasilIcon(
                        'settings-adjust-outline',
                        size: 21,
                        color:
                            active == 0
                                ? AppColors.textPrimary
                                : AppColors.primary,
                      ),
                      if (active > 0)
                        Positioned(
                          top: 7,
                          right: 7,
                          child: Container(
                            width: 16,
                            height: 16,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$active',
                              textScaler: TextScaler.noScaling,
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                height: 1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What is on, as one scrolling row of pills; each pill's cross turns that
/// filter off. Draws nothing while every filter is at its default.
class MarketActiveFilters extends StatelessWidget {
  const MarketActiveFilters({
    super.key,
    required this.filters,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });

  final MarketFilters filters;
  final ValueChanged<MarketFilters> onChanged;

  /// Lets the row scroll edge to edge while its first pill keeps the gutter.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final category = filters.category;
    return SingleChildScrollView(
      key: const ValueKey('market-active-filters'),
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          if (filters.forYou)
            _ActivePill(
              label: 'For you',
              icon: 'heart-outline',
              onClear: () => onChanged(filters.withTopic()),
            )
          else if (category != null)
            _ActivePill(
              label: marketCategoryLabel(category),
              icon: MarketGlyph.categoryIcon(category),
              onClear: () => onChanged(filters.withTopic()),
            ),
          if (filters.window != MarketDiscoveryWindow.all)
            _ActivePill(
              label: filters.window.label,
              icon: filters.window.icon,
              onClear:
                  () =>
                      onChanged(filters.withWindow(MarketDiscoveryWindow.all)),
            ),
          if (filters.sort != MarketDiscoverySort.closingSoon)
            _ActivePill(
              label: filters.sort.label,
              icon: filters.sort.icon,
              onClear:
                  () => onChanged(
                    filters.withSort(MarketDiscoverySort.closingSoon),
                  ),
            ),
        ],
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({
    required this.label,
    required this.icon,
    required this.onClear,
  });

  final String label;
  final String icon;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Semantics(
      button: true,
      label: 'Remove filter: $label',
      excludeSemantics: true,
      onTap: onClear,
      child: InkWell(
        onTap: onClear,
        borderRadius: BorderRadius.circular(12),
        // Drawn at 34dp inside a 48dp touch target.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BasilIcon(icon, size: 15, color: AppColors.pinkInk),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.pinkInk,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const BasilIcon(
                    'cross-outline',
                    size: 18,
                    color: AppColors.pinkInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the filter sheet. Choices apply as they are tapped — the list
/// behind updates live — so the sheet's one action only closes it.
Future<void> showMarketFilterSheet({
  required BuildContext context,
  required MarketFilters value,
  required List<MarketCategoryCount> categories,
  required ValueChanged<MarketFilters> onChanged,
  bool offerForYou = false,
  bool offerMostActive = false,
}) => showChumbucketWavySheet<void>(
  context: context,
  builder:
      (_) => MarketFilterSheet(
        value: value,
        categories: categories,
        onChanged: onChanged,
        offerForYou: offerForYou,
        offerMostActive: offerMostActive,
      ),
);

class MarketFilterSheet extends StatefulWidget {
  const MarketFilterSheet({
    super.key,
    required this.value,
    required this.categories,
    required this.onChanged,
    this.offerForYou = false,
    this.offerMostActive = false,
  });

  final MarketFilters value;
  final List<MarketCategoryCount> categories;
  final ValueChanged<MarketFilters> onChanged;

  /// "For you" needs chosen topics.
  final bool offerForYou;

  /// "Most active" needs venue-reported volume; over all-zero figures it
  /// would be a coin flip.
  final bool offerMostActive;

  @override
  State<MarketFilterSheet> createState() => _MarketFilterSheetState();
}

class _MarketFilterSheetState extends State<MarketFilterSheet> {
  late MarketFilters _value = widget.value;

  void _set(MarketFilters next) {
    setState(() => _value = next);
    widget.onChanged(next);
  }

  Widget _section(String title, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 0, children: chips),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return ChumbucketWavySheet(
      title: 'Filters',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('When', [
              for (final window in MarketDiscoveryWindow.values)
                MarketFilterChip(
                  label: window.label,
                  icon: window.icon,
                  selected: value.window == window,
                  onPressed: () => _set(value.withWindow(window)),
                ),
            ]),
            _section('Topic', [
              if (widget.offerForYou)
                MarketFilterChip(
                  label: 'For you',
                  icon: 'heart-outline',
                  selected: value.forYou,
                  onPressed:
                      () => _set(
                        value.forYou
                            ? value.withTopic()
                            : value.withTopic(forYou: true),
                      ),
                ),
              MarketFilterChip(
                label: 'All',
                icon: 'apps-outline',
                selected: !value.forYou && value.category == null,
                onPressed: () => _set(value.withTopic()),
              ),
              for (final entry in widget.categories)
                MarketFilterChip(
                  label: marketCategoryLabel(entry.category),
                  icon: MarketGlyph.categoryIcon(entry.category),
                  count: entry.count,
                  selected: !value.forYou && value.category == entry.category,
                  onPressed:
                      () => _set(
                        value.category == entry.category && !value.forYou
                            ? value.withTopic()
                            : value.withTopic(category: entry.category),
                      ),
                ),
            ]),
            if (widget.offerMostActive)
              _section('Sort', [
                for (final sort in MarketDiscoverySort.values)
                  MarketFilterChip(
                    label: sort.label,
                    icon: sort.icon,
                    selected: value.sort == sort,
                    onPressed: () => _set(value.withSort(sort)),
                  ),
              ]),
          ],
        ),
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChumbucketPrimaryButton(
              label: 'Show markets',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            if (!value.isEmpty)
              ChumbucketTextAction(
                label: 'Clear filters',
                color: AppColors.textSecondary,
                onPressed: () => _set(MarketFilters.none),
              ),
          ],
        ),
      ),
    );
  }
}
