// ชุดสีหลักของ Linko: ใช้ ID คงที่ในการบันทึก และแยกเฉดที่อ่านง่ายสำหรับแต่ละโหมด
import 'package:flutter/material.dart';

/// ตัวเลือกสีเดียวกันใช้เฉดเข้มบนพื้นสว่าง และเฉดอ่อนบนพื้นมืด
enum ThemeAccent {
  linko('default', 'ค่าเริ่มต้น Linko', Color(0xFFC92847), Color(0xFFFF8092)),
  blue('blue', 'สีน้ำเงิน', Color(0xFF2457D6), Color(0xFF8EADFF)),
  green('green', 'สีเขียว', Color(0xFF006B57), Color(0xFF4DD4AC)),
  yellow('yellow', 'สีเหลือง', Color(0xFF805600), Color(0xFFFACC15)),
  pink('pink', 'สีชมพู', Color(0xFFB21C65), Color(0xFFFF9ACD)),
  orange('orange', 'สีส้ม', Color(0xFFA13C00), Color(0xFFFFB784)),
  purple('purple', 'สีม่วง', Color(0xFF7430BE), Color(0xFFD3AEFF)),
  monochrome('monochrome', 'ขาว / ดำ', Color(0xFF171A21), Color(0xFFF8FAFC));

  const ThemeAccent(this.id, this.label, this.light, this.dark);

  final String id;
  final String label;
  final Color light;
  final Color dark;

  Color colorFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// ค่าเก่าหรือ ID ที่ไม่รู้จักใช้สี Linko เพื่อให้เปิดแอปได้หลังเปลี่ยนเวอร์ชัน
  static ThemeAccent fromId(String? id) =>
      values.firstWhere((accent) => accent.id == id, orElse: () => linko);
}
