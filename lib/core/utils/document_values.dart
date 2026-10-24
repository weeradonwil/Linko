// Defensive reads keep legacy or malformed documents from breaking an entire list.
import 'package:cloud_firestore/cloud_firestore.dart';

String readString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? readOptionalString(Object? value) => value is String ? value : null;

String readName(Object? value, [String fallback = 'สมาชิก']) {
  final text = readString(value).trim();
  return text.isEmpty ? fallback : text;
}

Map<String, dynamic> readMap(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : const {};

List<String> readStrings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

DateTime? readDate(Object? value) => switch (value) {
  Timestamp timestamp => timestamp.toDate(),
  DateTime date => date,
  _ => null,
};

int readCount(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : 0;

/// Keep UTF-16 limits used by the forms without splitting a surrogate pair.
String boundedString(String value, int maxLength) {
  final result = StringBuffer();
  var length = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (length + character.length > maxLength) break;
    result.write(character);
    length += character.length;
  }
  return result.toString();
}
