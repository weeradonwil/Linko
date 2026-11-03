/// Shared audience and content policy used by uploads and resumable privacy jobs.
class PostPolicy {
  PostPolicy._();

  static bool profileIsPrivate(Map<String, dynamic> profile) =>
      (profile['privacyMigrationTarget'] is bool
          ? profile['privacyMigrationTarget']
          : profile['privacyTarget'] is bool
          ? profile['privacyTarget']
          : profile['isPrivate']) ==
      true;

  /// Account privacy does not rewrite a post's chosen audience. The composer
  /// only offers public/private, so legacy follower visibility returns to public.
  static String audience(bool _, Object? visibility) =>
      visibility == 'private' ? 'private' : 'public';

  static bool hasContent(String text, {required bool hasMedia}) =>
      text.trim().isNotEmpty || hasMedia;
}
