import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomapay_flutter/fomapay_flutter.dart';

const secret = 'whsec_unit';
const now = 1800000000;
const body =
    '{"id":"evt_1","type":"payment.succeeded","created":"2026-10-10T10:00:00Z","livemode":false,"data":{"id":"pay_1","status":"success","orderId":"CMD-1"}}';

DateTime at(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

String sign(
        {String payload = body, String key = secret, int timestamp = now}) =>
    't=$timestamp,v1=${Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$timestamp.$payload'))}';

void main() {
  test('une signature valide renvoie l’événement', () {
    final event =
        FomaPayWebhook.constructEvent(body, sign(), secret, now: at(now));
    expect(event.type, 'payment.succeeded');
    expect(event.data.isSuccessful, isTrue);
    expect(event.data.orderId, 'CMD-1');
    expect(FomaPayWebhook.verify(body, sign(), secret, now: at(now + 299)),
        isTrue);
  });

  test('vecteur commun à tous les SDKs', () {
    // printf '1700000000.{"id":"evt_1"}' | openssl dgst -sha256 -hmac whsec_test
    const digest =
        'c89214b5b5da833daed6f0b8c5bb6bd58cea9022bd80ccc78230f3942d632925';
    expect(
        FomaPayWebhook.verify(
            '{"id":"evt_1"}', 't=1700000000,v1=$digest', 'whsec_test',
            now: at(1700000000)),
        isTrue);
    expect(
        FomaPayWebhook.verify('{"id":"evt_1"}',
            't=1700000000, v1=${digest.toUpperCase()}', 'whsec_test',
            now: at(1700000000)),
        isTrue);
  });

  test('les signatures invalides sont refusées', () {
    final cases = <(String, String?, int)>[
      ('$body ', sign(), now), // corps modifié
      (body, sign(key: 'whsec_autre'), now), // mauvais secret
      (body, sign(), now + 301), // trop ancien
      (body, sign(), now - 301), // horodatage dans le futur
      (body, '', now),
      (body, null, now),
      (body, 't=abc,v1=00', now),
      (body, 't=$now', now),
    ];
    for (final (payload, header, clock) in cases) {
      expect(FomaPayWebhook.verify(payload, header, secret, now: at(clock)),
          isFalse,
          reason: '$header');
      expect(
        () => FomaPayWebhook.constructEvent(payload, header, secret,
            now: at(clock)),
        throwsA(isA<FomaPaySignatureException>()
            .having((e) => e.code, 'code', 'ERROR_INVALID_SIGNATURE')),
      );
    }
  });

  test('un secret manquant est signalé', () {
    expect(
      () => FomaPayWebhook.verify(body, sign(), ''),
      throwsA(isA<FomaPayException>()
          .having((e) => e.code, 'code', 'ERROR_WEBHOOK_SECRET_MISSING')),
    );
  });
}
