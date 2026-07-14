import 'package:flutter_test/flutter_test.dart';
import 'package:nexly/src/collect_payload.dart';

IngestCredentials credentials() =>
    const IngestCredentials(appId: 'app_123', apiToken: 'nx_secret');

void main() {
  group('buildCollectPayload', () {
    test('includes core fields and duplicates context.path to top-level path',
        () {
      final body = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'pageview',
        eventType: 'pageview',
        client: 'flutter-ios',
        context: const {'path': '/settings', 'visitor_id': 'v1'},
      ));

      expect(body['app_id'], 'app_123');
      expect(body['api_token'], 'nx_secret');
      expect(body['event_name'], 'pageview');
      expect(body['event_type'], 'pageview');
      expect(body['client'], 'flutter-ios');
      expect(body['path'], '/settings');
      expect(body.containsKey('privacy_mode'), isFalse);
      expect(body.containsKey('cdata'), isFalse);
      expect(body.containsKey('session_context'), isFalse);
    });

    test('drops empty cdata and session_context', () {
      final body = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'custom_event',
        eventType: 'custom',
        client: 'flutter-ios',
        cdata: const {},
        sessionContext: const {},
      ));

      expect(body.containsKey('cdata'), isFalse);
      expect(body.containsKey('session_context'), isFalse);
      expect(body.containsKey('path'), isFalse);
    });

    test('includes non-empty cdata and session_context', () {
      final body = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'checkout_started',
        eventType: 'custom',
        client: 'flutter-android',
        cdata: const {'cart_value_cents': 4200, 'currency': 'usd'},
        sessionContext: const {'platform': 'android'},
      ));

      final cdata = body['cdata']! as Map<String, Object>;
      expect(cdata['cart_value_cents'], 4200);
      expect(cdata['currency'], 'usd');

      final sessionContext = body['session_context']! as Map<String, Object?>;
      expect(sessionContext['platform'], 'android');
    });

    test('drops non-scalar cdata values', () {
      final body = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'e',
        eventType: 'custom',
        cdata: {
          'ok': 'yes',
          'nested': {'not': 'allowed'},
          'list': [1, 2, 3],
        },
      ));

      final cdata = body['cdata']! as Map<String, Object>;
      expect(cdata, {'ok': 'yes'});
    });

    test('sets privacy_mode only when true', () {
      final disabled = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'e',
        eventType: 'custom',
      ));
      expect(disabled.containsKey('privacy_mode'), isFalse);

      final enabled = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'e',
        eventType: 'custom',
        privacyMode: true,
      ));
      expect(enabled['privacy_mode'], isTrue);
    });

    test('omits client when null or blank', () {
      final bodyNull = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'e',
        eventType: 'custom',
      ));
      expect(bodyNull.containsKey('client'), isFalse);

      final bodyBlank = buildCollectPayload(TrackEventInput(
        credentials: credentials(),
        eventName: 'e',
        eventType: 'custom',
        client: '   ',
      ));
      expect(bodyBlank.containsKey('client'), isFalse);
    });
  });

  group('StandardContextOverride', () {
    test('emits snake_case keys and skips unset fields', () {
      const override = StandardContextOverride(
        utmSource: 'newsletter',
        gadCampaignId: 'cmp42',
        liFatId: 'li1',
        mcCid: 'mc1',
      );
      expect(override.asContext(), {
        'utm_source': 'newsletter',
        'gad_campaignid': 'cmp42',
        'li_fat_id': 'li1',
        'mc_cid': 'mc1',
      });
    });
  });
}
