import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ChallengeInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final double fontSize;
  final double hintFontSize;
  final int? maxLines;
  final FontWeight? fontWeight;
  final FontWeight? hintFontWeight;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;

  const ChallengeInput({
    super.key,
    required this.controller,
    this.hintText = 'Type Your challenge',
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.fontSize = 24.0,
    this.hintFontSize = 28.0,
    this.maxLines = 2,
    this.fontWeight = FontWeight.w400,
    this.hintFontWeight = FontWeight.w600,
    this.onChanged,
    this.fieldKey,
    this.textInputAction,
    this.onEditingComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: TextField(
        key: fieldKey,
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        textInputAction: textInputAction ?? TextInputAction.done,
        onEditingComplete:
            onEditingComplete ??
            () {
              // Dismiss keyboard when done editing
              FocusScope.of(context).unfocus();
            },
        decoration: InputDecoration(
          filled: false,
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[350],
            fontSize: hintFontSize.sp,
            fontWeight: hintFontWeight,
          ),
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
        style: TextStyle(
          fontSize: fontSize.sp,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        maxLines: maxLines,
      ),
    );
  }
}

// Keep the original class for backward compatibility
class ChallengeDescriptionInput extends ChallengeInput {
  const ChallengeDescriptionInput({
    super.key,
    required super.controller,
    super.hintText = 'Type Your challenge',
    super.fieldKey = const ValueKey('description_input'),
  });
}

// Class for bet amount input
class ChallengeBetAmountInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const ChallengeBetAmountInput({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  // Format amount nicely (remove trailing zeros)
  String _formatAmount(String text) {
    if (text.isEmpty) return '';

    // Remove any existing formatting except digits and decimal
    String cleanText = text.replaceAll(RegExp(r'[^\d.]'), '');

    // Parse and format
    double? value = double.tryParse(cleanText);
    if (value == null) return '';

    // Format with up to 4 decimal places, removing trailing zeros
    if (value == value.truncate()) {
      return value.truncate().toString();
    }
    return value
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: TextField(
        key: const ValueKey('bet_amount_input'),
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}')),
        ],
        textInputAction: TextInputAction.done,
        onChanged: (value) {
          // Pass raw numeric value to parent
          onChanged(value);
        },
        onEditingComplete: () {
          // Format the value nicely when done editing
          final formattedValue = _formatAmount(controller.text);
          controller.value = TextEditingValue(
            text: formattedValue,
            selection: TextSelection.collapsed(offset: formattedValue.length),
          );

          // Pass the numeric value to parent
          onChanged(formattedValue);

          // Dismiss keyboard
          FocusScope.of(context).unfocus();
        },
        decoration: InputDecoration(
          filled: false,
          hintText: '0.5 SOL',
          hintStyle: TextStyle(
            color: Colors.grey[350],
            fontSize: 40.sp,
            fontWeight: FontWeight.bold,
          ),

          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
        style: TextStyle(
          fontSize: 40.sp,
          fontWeight: FontWeight.w900,
          color: Colors.black,
        ),
        maxLines: 1,
      ),
    );
  }
}
