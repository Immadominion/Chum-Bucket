/// The app's fixed avatar set. A person's choice is stored as an id (1..5) on
/// their own account through the BFF (`account.updateProfile`), and every
/// screen that shows a person derives the picture from that id — so other
/// people's avatars render too, not just your own.
library;

const List<String> kAvatarAssets = <String>[
  'assets/images/ai_gen/profile_images/1.png',
  'assets/images/ai_gen/profile_images/2.png',
  'assets/images/ai_gen/profile_images/3.png',
  'assets/images/ai_gen/profile_images/4.png',
  'assets/images/ai_gen/profile_images/5.png',
];

/// The default when a person has not chosen: the first picture.
const int kDefaultAvatarId = 1;

bool isAvatarId(Object? id) =>
    id is int && id >= 1 && id <= kAvatarAssets.length;

/// The asset for an avatar id, or null for anything outside the set.
String? avatarAssetFor(Object? id) =>
    isAvatarId(id) ? kAvatarAssets[(id as int) - 1] : null;

/// The id for one of the bundled asset paths, or null.
int? avatarIdForAsset(String? path) {
  if (path == null) return null;
  final index = kAvatarAssets.indexOf(path);
  return index < 0 ? null : index + 1;
}

/// What to render for a person on the wire: their own https picture when they
/// have one, else their chosen avatar, else nothing (initials).
String? avatarImageFor({String? avatarUrl, Object? avatarId}) {
  final url = avatarUrl?.trim();
  if (url != null && url.startsWith('https://')) return url;
  if (url != null && url.startsWith('assets/')) return url;
  return avatarAssetFor(avatarId);
}
