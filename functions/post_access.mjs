// สิทธิ์โพสต์ทั่วไปใช้ร่วมกันในงานรายงานและแจ้งเตือน โดยไม่รวมสิทธิ์แชร์เฉพาะปลายทาง
export function profileIsPrivate(profile = {}) {
  return (typeof profile.privacyMigrationTarget === 'boolean' ? profile.privacyMigrationTarget
    : typeof profile.privacyTarget === 'boolean' ? profile.privacyTarget : profile.isPrivate) === true;
}

// ตรวจสิทธิ์รายโพสต์ก่อนสิทธิ์โปรไฟล์: ผู้ติดตามไม่มีสิทธิ์อ่านโพสต์เฉพาะฉัน
export function canReadPostAudience(post, profile, { isOwner = false, isFollower = false } = {}) {
  if (isOwner) return true;
  const visibility = post.visibility ?? 'public';
  if (!['public', 'followers'].includes(visibility)) return false;
  return isFollower || (visibility === 'public' && post.authorIsPrivate !== true && !profileIsPrivate(profile));
}
