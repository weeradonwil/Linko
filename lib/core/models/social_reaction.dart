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
    SocialReaction(id: 'love', emoji: '❤️', label: 'รักเลย'),
    SocialReaction(id: 'haha', emoji: '😂', label: 'ฮ่าๆ'),
    SocialReaction(id: 'wow', emoji: '😮', label: 'ว้าว'),
    SocialReaction(id: 'sad', emoji: '😢', label: 'เศร้า'),
    SocialReaction(id: 'angry', emoji: '😡', label: 'โกรธ'),
    SocialReaction(id: 'dislike', emoji: '👎', label: 'ไม่ถูกใจ'),
  ];

  static SocialReaction? byId(String? id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }
}
