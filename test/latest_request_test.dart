import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:social_app/core/utils/latest_request.dart';

void main() {
  test(
    'slower old results cannot replace the latest input or filter',
    () async {
      final guard = LatestRequest();
      final old = Completer<String>();
      final current = Completer<String>();
      String? displayed;
      Future<void> load(Future<String> future) async {
        final version = guard.next();
        final value = await future;
        if (guard.accepts(version)) displayed = value;
      }

      final a = load(old.future);
      final b = load(current.future);
      current.complete('new filter');
      await b;
      old.complete('old filter');
      await a;
      expect(displayed, 'new filter');
      final pending = guard.version;
      guard.next();
      expect(guard.accepts(pending), isFalse);
    },
  );
}
