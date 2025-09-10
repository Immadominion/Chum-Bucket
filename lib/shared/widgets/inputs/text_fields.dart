import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_dimensions.dart';

/// Standard text input field used throughout the app
class StandardTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onTap;
  final bool readOnly;
  final int? maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool enabled;
  final FocusNode? focusNode;

  const StandardTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      enabled: enabled,
      style: TextStyle(fontSize: 16.sp, color: AppColors.onSurface),
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        hintStyle: TextStyle(
          fontSize: 16.sp,
          color: AppColors.onSurfaceVariant,
        ),
        labelStyle: TextStyle(
          fontSize: 14.sp,
          color: AppColors.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          borderSide: BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          borderSide: BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          borderSide: BorderSide(color: AppColors.error),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          borderSide: BorderSide(color: AppColors.outline.withOpacity(0.5)),
        ),
        fillColor:
            enabled
                ? AppColors.surfaceVariant
                : AppColors.surfaceVariant.withOpacity(0.5),
        filled: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMedium,
          vertical: AppDimensions.paddingMedium,
        ),
      ),
    );
  }
}

/// Specialized text field for amounts/numbers
class AmountTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final String? prefixText;
  final String? suffixText;
  final double? value;

  const AmountTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.validator,
    this.onChanged,
    this.prefixText,
    this.suffixText,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return StandardTextField(
      controller: controller,
      hintText: hintText,
      labelText: labelText,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: validator,
      onChanged: onChanged,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,6}')),
      ],
      prefixIcon:
          prefixText != null
              ? Padding(
                padding: EdgeInsets.only(left: AppDimensions.paddingMedium),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1.0,
                  child: Text(
                    prefixText!,
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              )
              : null,
      suffixIcon:
          suffixText != null
              ? Padding(
                padding: EdgeInsets.only(right: AppDimensions.paddingMedium),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1.0,
                  child: Text(
                    suffixText!,
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              : null,
    );
  }
}

/// Search input field with search icon
class SearchTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final void Function(String)? onChanged;
  final VoidCallback? onClear;

  const SearchTextField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return StandardTextField(
      controller: controller,
      hintText: hintText ?? 'Search...',
      onChanged: onChanged,
      prefixIcon: Icon(
        Icons.search,
        color: AppColors.onSurfaceVariant,
        size: 20.sp,
      ),
      suffixIcon:
          controller?.text.isNotEmpty == true
              ? IconButton(
                onPressed: () {
                  controller?.clear();
                  onClear?.call();
                },
                icon: Icon(
                  Icons.clear,
                  color: AppColors.onSurfaceVariant,
                  size: 20.sp,
                ),
              )
              : null,
    );
  }
}
