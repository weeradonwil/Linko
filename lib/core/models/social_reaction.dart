// รายการ reaction ที่ทุกหน้าต้องใช้ ID, อีโมจิ และชื่อให้ตรงกัน
class SocialReaction {
  const SocialReaction({
    required this.id,
    required this.emoji,
    required this.label,
  });

  final String id;
  final String emoji;
  final String label;

  static const options = <SocialReaction>[
    SocialReaction(id: 'like', emoji: '👍', label: 'ถูกใจ'),
    SocialReaction(id: 'dislike', emoji: '👎', label: 'ไม่ถูกใจ'),
  ];

  static SocialReaction? byId(String? id) {
    // Legacy emoji reactions still appear as Like until users change them.
    if (const {'love', 'haha', 'wow', 'sad', 'angry'}.contains(id)) {
      return options.first;
    }
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}
