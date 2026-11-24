import 'package:flutter_test/flutter_test.dart';

import 'package:docuscan_pro/core/services/ad_service.dart';

void main() {
  final install = DateTime(2026, 1, 1, 9);

  bool interstitial({
    required DateTime now,
    bool pro = false,
    bool editing = false,
    DateTime? installDate,
    DateTime? sessionStart,
    DateTime? last,
  }) =>
      AdPolicy.canShowInterstitial(
        now: now,
        isProUser: pro,
        isInEditingMode: editing,
        installDate: installDate ?? install,
        sessionStart: sessionStart ?? now.subtract(const Duration(minutes: 10)),
        lastInterstitial: last,
      );

  group('AdPolicy.canShowInterstitial', () {
    final dayTwo = install.add(const Duration(hours: 25));

    test('blocked during the 24 h new-user grace period', () {
      expect(interstitial(now: install.add(const Duration(hours: 23, minutes: 59))), isFalse);
      expect(interstitial(now: install.add(const Duration(hours: 24))), isTrue);
    });

    test('blocked when install date is unknown', () {
      expect(
        AdPolicy.canShowInterstitial(
          now: dayTwo,
          isProUser: false,
          isInEditingMode: false,
          installDate: null,
          sessionStart: dayTwo.subtract(const Duration(minutes: 5)),
          lastInterstitial: null,
        ),
        isFalse,
      );
    });

    test('never in sessions shorter than 60 s', () {
      expect(
        interstitial(now: dayTwo, sessionStart: dayTwo.subtract(const Duration(seconds: 59))),
        isFalse,
      );
      expect(
        interstitial(now: dayTwo, sessionStart: dayTwo.subtract(const Duration(seconds: 60))),
        isTrue,
      );
    });

    test('at most one per 5-minute window', () {
      expect(
        interstitial(now: dayTwo, last: dayTwo.subtract(const Duration(minutes: 4, seconds: 59))),
        isFalse,
      );
      expect(
        interstitial(now: dayTwo, last: dayTwo.subtract(const Duration(minutes: 5))),
        isTrue,
      );
    });

    test('never for Pro users or during editing', () {
      expect(interstitial(now: dayTwo, pro: true), isFalse);
      expect(interstitial(now: dayTwo, editing: true), isFalse);
    });
  });

  group('AdPolicy.canShowBanner', () {
    test('only from session 2 onward', () {
      expect(AdPolicy.canShowBanner(isProUser: false, sessionCount: 1), isFalse);
      expect(AdPolicy.canShowBanner(isProUser: false, sessionCount: 2), isTrue);
      expect(AdPolicy.canShowBanner(isProUser: false, sessionCount: 10), isTrue);
    });

    test('never for Pro users', () {
      expect(AdPolicy.canShowBanner(isProUser: true, sessionCount: 5), isFalse);
    });
  });

  group('AdSessionTracker', () {
    late DateTime now;
    late AdSessionTracker tracker;

    setUp(() {
      now = DateTime(2026, 3, 1, 12);
      tracker = AdSessionTracker(clock: () => now, initialSessionCount: 3);
    });

    test('cold launch starts the next session from the persisted count', () {
      expect(tracker.startSession(), 4);
      expect(tracker.sessionStart, now);
    });

    test('short background trip keeps the same session', () {
      tracker.startSession();
      final start = tracker.sessionStart;
      tracker.onBackgrounded();
      now = now.add(const Duration(minutes: 29));
      expect(tracker.onForegrounded(), isFalse);
      expect(tracker.sessionCount, 4);
      expect(tracker.sessionStart, start);
    });

    test('30+ min in background starts a new session and resets its clock', () {
      tracker.startSession();
      tracker.onBackgrounded();
      now = now.add(const Duration(minutes: 30));
      expect(tracker.onForegrounded(), isTrue);
      expect(tracker.sessionCount, 5);
      expect(tracker.sessionStart, now);
    });

    test('foreground without a background event is a no-op', () {
      tracker.startSession();
      now = now.add(const Duration(hours: 2));
      expect(tracker.onForegrounded(), isFalse);
      expect(tracker.sessionCount, 4);
    });
  });
}
