/// Shared audience and content policy used by uploads and resumable privacy jobs.
class PostPolicy {
  PostPolicy._();

  static bool profileIsPrivate(Map<String, dynamic> profile) =>
      (profile['privacyTarget'] is bool
          ? profile['privacyTarget']
          : profile['isPrivate']) ==
      true;

  static String audience(bool isPrivate, Object? visibility) =>
      visibility == 'private'
      ? 'private'
      : isPrivate
      ? 'followers'
      : 'public';

  static bool hasContent(String text, {required bool hasMedia}) =>
      text.trim().isNotEmpty || hasMedia;
}
