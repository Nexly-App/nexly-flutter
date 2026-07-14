/// Platform-agnostic event envelope types and payload builder.
///
/// Pure Dart — no Flutter or `dart:io` imports, so payload assembly is
/// testable with plain `dart test`. Mirrors `buildCollectPayload` in
/// `packages/core/src/collect.ts` of the `trackers` monorepo and
/// `CollectPayload.swift` in `nexly-ios`.
library;

/// User-defined custom analytics payload. The contract is intentionally
/// narrow: a flat map whose values are `String`, `num`, or `bool`. All
/// values are normalised to strings server-side, so downstream analytics
/// deal with one type per key. Nested objects and lists are silently
/// dropped — push richer payloads through a different surface.
typedef CData = Map<String, Object>;

/// Typed override for the per-event standard attribution slot accepted by
/// [Nexly.customEvent]'s `context` parameter. Mirrors
/// `StandardContextOverride` in `packages/core/src/collect.ts` and the
/// server-side `StandardAttributionKeys` — keep all ends in sync when
/// adding a new marketing parameter.
///
/// Standard attribution keys are auto-extracted by the server from the
/// landing URL on the first event of a session; this type lets callers
/// manually override the per-event value when the URL no longer carries
/// the parameter (deep links, post-navigation clicks, server-side
/// redirects).
class StandardContextOverride {
  const StandardContextOverride({
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.utmContent,
    this.utmTerm,
    this.gclid,
    this.gadSource,
    this.gadCampaignId,
    this.fbclid,
    this.msclkid,
    this.ttclid,
    this.liFatId,
    this.yclid,
    this.mcCid,
    this.ref,
  });

  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? utmContent;
  final String? utmTerm;
  final String? gclid;
  final String? gadSource;
  final String? gadCampaignId;
  final String? fbclid;
  final String? msclkid;
  final String? ttclid;
  final String? liFatId;
  final String? yclid;
  final String? mcCid;
  final String? ref;

  /// Wire-format key/value pairs (snake_case), skipping unset fields.
  Map<String, Object> asContext() {
    final out = <String, Object>{};
    void put(String key, String? value) {
      if (value != null && value.isNotEmpty) out[key] = value;
    }

    put('utm_source', utmSource);
    put('utm_medium', utmMedium);
    put('utm_campaign', utmCampaign);
    put('utm_content', utmContent);
    put('utm_term', utmTerm);
    put('gclid', gclid);
    put('gad_source', gadSource);
    put('gad_campaignid', gadCampaignId);
    put('fbclid', fbclid);
    put('msclkid', msclkid);
    put('ttclid', ttclid);
    put('li_fat_id', liFatId);
    put('yclid', yclid);
    put('mc_cid', mcCid);
    put('ref', ref);
    return out;
  }
}

/// Auth fields for ingest (no transport URL). Mirrors `IngestCredentials`.
class IngestCredentials {
  const IngestCredentials({required this.appId, required this.apiToken});

  final String appId;
  final String apiToken;
}

/// Event envelope passed to [buildCollectPayload]. Mirrors
/// `TrackEventInput` in `packages/core/src/collect.ts`.
class TrackEventInput {
  const TrackEventInput({
    required this.credentials,
    required this.eventName,
    required this.eventType,
    this.client,
    this.privacyMode = false,
    this.context = const {},
    this.data = const {},
    this.cdata,
    this.sessionContext,
  });

  final IngestCredentials credentials;
  final String eventName;
  final String eventType;
  final String? client;
  final bool privacyMode;
  final Map<String, Object?> context;
  final Map<String, Object?> data;
  final CData? cdata;
  final Map<String, Object?>? sessionContext;
}

bool _isScalar(Object? v) => v is String || v is num || v is bool;

/// Builds the JSON body for `POST /v1/collect` (snake_case wire format).
///
/// Duplicates `context['path']` to the top-level `path` when present.
/// Includes `cdata` when the caller passed a non-empty map (non-scalar
/// values are dropped, matching the server-side contract). Includes
/// `session_context` when provided (first event of a session).
Map<String, Object?> buildCollectPayload(TrackEventInput input) {
  final context = input.context;
  final pathFromContext = context['path'];
  final body = <String, Object?>{
    'app_id': input.credentials.appId,
    'api_token': input.credentials.apiToken,
    'event_name': input.eventName,
    'event_type': input.eventType,
    'context': context,
    'data': input.data,
  };

  final client = (input.client ?? '').trim();
  if (client.isNotEmpty) {
    body['client'] = client;
  }
  if (input.privacyMode) {
    body['privacy_mode'] = true;
  }
  if (pathFromContext is String && pathFromContext.isNotEmpty) {
    body['path'] = pathFromContext;
  }

  final cdata = input.cdata;
  if (cdata != null && cdata.isNotEmpty) {
    final scalars = <String, Object>{
      for (final entry in cdata.entries)
        if (_isScalar(entry.value)) entry.key: entry.value,
    };
    if (scalars.isNotEmpty) {
      body['cdata'] = scalars;
    }
  }

  final sessionContext = input.sessionContext;
  if (sessionContext != null && sessionContext.isNotEmpty) {
    body['session_context'] = sessionContext;
  }

  return body;
}
