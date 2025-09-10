# Resolve Challenge Sheet - Modular Components

This document explains the modular structure of the resolve challenge sheet components.

## File Structure

### Main Component
- `resolve_challenge_sheet.dart` - Main modal sheet container with responsive design

### Sub-Components
- `wave_clipper.dart` - Custom clipper for smooth surface transverse waves
- `overlapping_profile_avatars.dart` - Profile avatars with custom border clipping for overlap effect
- `resolve_sheet_header.dart` - Gradient header with bet amount display
- `resolve_sheet_content.dart` - Bottom section with challenge text and action buttons

## Key Features Implemented

### 🌊 Wave Design
- Smooth surface transverse waves using cubic bezier curves
- 6 wave segments for natural appearance
- Improved from previous quadratic bezier implementation

### 👥 Avatar Overlap Effect
- Custom border clipping for left avatar to hide intersection
- Right avatar maintains full border (appears on top)
- Subtle shadow effects for depth

### 📱 Responsive Design
- Height constraints based on screen size (85% max)
- Minimum height protection for smaller screens
- Flexible layout that adapts to content

### 🔤 Wallet Address Resolution
- Uses existing AddressNameResolver service
- Falls back to shortened format (abc123...xyz789)
- Displays domain names when available
- Same resolution logic used elsewhere in the app

## Benefits of Modularization

1. **Better Code Quality** - Single responsibility principle
2. **Reusability** - Components can be used elsewhere
3. **Maintainability** - Easier to update individual features
4. **Testing** - Each component can be tested independently
5. **Documentation** - Clear separation of concerns
6. **Performance** - Smaller widget trees and better optimization

## Technical Details

- All components use flutter_screenutil for responsive sizing
- Wave clipper uses cubic bezier curves for smoothness
- Profile avatars use custom clipping for overlap effect
- Address resolution happens asynchronously with FutureBuilder
- Responsive height calculations prevent overflow issues
