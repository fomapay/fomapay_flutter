import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fomapay_flutter/fomapay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const paymentJson = {
  'id': 'pay_1',
  'reference': 'FP-1',
  'status': 'pending',
  'amount': 25,
  'currency': 'USD',
  'orderId': 'CMD-1'
};

http.Response json(int status, Object body,
        {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers
    });

http.Response failure(int status, String code,
        {Map<String, String> headers = const {}}) =>
    json(
      status,
      {
        'error': {
          'code': code,
          'message': 'oups',
          'details': {'champ': 'amount'}
        }
      },
      headers: headers,
    );

void main() {
  late List<http.Request> calls;
  late List<Duration> waits;

  FomaPay client(
      FutureOr<http.Response> Function(int n, http.Request request) respond,
      {int maxRetries = 2,
      Duration? timeout}) {
    calls = [];
    waits = [];
    return FomaPay(
      publicKey: 'pk_test_unit',
      apiUrl: 'https://api.test/',
      maxRetries: maxRetries,
      timeout: timeout ?? const Duration(seconds: 30),
      httpClient: MockClient((request) async {
        calls.add(request);
        return respond(calls.length, request);
      }),
      sleep: (wait) async => waits.add(wait),
    );
  }

  test('refuse une clé secrète ou mal formée', () {
    expect(
      () => FomaPay(publicKey: 'sk_test_abc'),
      throwsA(isA<FomaPayException>()
          .having((e) => e.code, 'code', 'ERROR_INVALID_API_KEY')),
    );
  });

  test('createPayment envoie le format standard et une clé d’idempotence',
      () async {
    final fomapay = client((_, __) => json(201, paymentJson));
    final payment = await fomapay.createPayment(const PaymentParams(
      amount: 25,
      currency: Currency.usd,
      orderId: 'CMD-1',
      customer: Customer(name: 'Jean Marc', phone: '+243810000000'),
      paymentModes: [PaymentMode.fomapayDirect, PaymentMode.mobileMoney],
      callbackUrl: 'https://marchand.cd/api/callback',
      metadata: {'custom_field': 'valeur'},
    ));

    final call = calls.single;
    expect('${call.method} ${call.url}', 'POST https://api.test/v1/payments');
    expect(call.headers['Authorization'], 'Bearer pk_test_unit');
    expect(call.headers['Idempotency-Key'], startsWith('dart-'));
    expect(jsonDecode(call.body), {
      'amount': 25,
      'currency': 'USD',
      'orderId': 'CMD-1',
      'customer': {'name': 'Jean Marc', 'phone': '+243810000000'},
      'paymentModes': ['fomapay_direct', 'mobile_money'],
      'callbackUrl': 'https://marchand.cd/api/callback',
      'metadata': {'custom_field': 'valeur'},
    });
    expect(payment.orderId, 'CMD-1');
    expect(payment.isPending, isTrue);
    expect(payment.isSuccessful, isFalse);
  });

  test('rejoue les erreurs serveur et réseau avec la même clé d’idempotence',
      () async {
    final fomapay = client((n, _) {
      if (n == 1) return failure(503, 'ERROR_UNAVAILABLE');
      if (n == 2) throw http.ClientException('coupure');
      return json(201, paymentJson);
    });

    expect(
        (await fomapay.createPayment(
                const PaymentParams(amount: 25, currency: Currency.usd)))
            .id,
        'pay_1');
    expect(calls, hasLength(3));
    expect(
        calls.map((c) => c.headers['Idempotency-Key']).toSet(), hasLength(1));
    expect(waits[0].inMilliseconds, inInclusiveRange(250, 500));
    expect(waits[1].inMilliseconds, inInclusiveRange(500, 1000));
  });

  test('abandonne après maxRetries et ne rejoue pas les erreurs 4xx', () async {
    final down =
        client((_, __) => failure(500, 'ERROR_INTERNAL'), maxRetries: 1);
    await expectLater(
        down.getPayment('FP-1'),
        throwsA(
            isA<FomaPayApiException>().having((e) => e.status, 'status', 500)));
    expect(calls, hasLength(2));

    final refused =
        client((_, __) => failure(403, 'ERROR_LEVEL_0_LIMIT_REACHED'));
    await expectLater(
      refused.createPayment(
          const PaymentParams(amount: 900, currency: Currency.usd)),
      throwsA(isA<FomaPayApiException>()
          .having((e) => e.code, 'code', 'ERROR_LEVEL_0_LIMIT_REACHED')
          .having((e) => e.details, 'details', {'champ': 'amount'})),
    );
    expect(calls, hasLength(1));
  });

  test('un POST sans clé d’idempotence n’est rejoué que sur un 429', () async {
    final broken = client((_, __) => failure(502, 'ERROR_BAD_GATEWAY'));
    await expectLater(
      broken.payWithMobileMoney('pay_1',
          operator: MobileOperator.mpesa, phone: '+243810000000'),
      throwsA(isA<FomaPayApiException>()),
    );
    expect(calls, hasLength(1));

    final limited = client((n, _) => n == 1
        ? failure(429, 'ERROR_RATE_LIMITED', headers: {'retry-after': '2'})
        : json(200, paymentJson));
    await limited.payWithMobileMoney('FP/1',
        operator: MobileOperator.airtelMoney, phone: '+243970000000');
    expect(calls, hasLength(2));
    expect(waits, [const Duration(seconds: 2)]);
    expect(calls.last.url.toString(),
        'https://api.test/v1/payments/FP%2F1/mobile-money');
    expect(jsonDecode(calls.last.body),
        {'operator': 'airtel_money', 'phone': '+243970000000'});
  });

  test('le délai dépassé donne ERROR_TIMEOUT', () async {
    final slow = client((_, __) => Completer<http.Response>().future,
        maxRetries: 1, timeout: const Duration(milliseconds: 30));
    await expectLater(
        slow.store(),
        throwsA(isA<FomaPayNetworkException>()
            .having((e) => e.code, 'code', 'ERROR_TIMEOUT')));
    expect(calls, hasLength(2));
  });

  test('store est mis en cache, sauf après une erreur', () async {
    final fomapay = client(
        (n, _) => n == 1
            ? failure(500, 'ERROR_INTERNAL')
            : json(200, {
                'id': 's1',
                'name': 'Chez Foma',
                'shortCode': 'FOMA',
                'kycLevel': 2,
                'paymentModes': ['fomapay_direct', 'mobile_money']
              }),
        maxRetries: 0);

    await expectLater(fomapay.store(), throwsA(isA<FomaPayApiException>()));
    final store = await fomapay.store();
    await fomapay.store();
    expect(calls, hasLength(2));
    expect(store.kycLevel, 2);
    expect(store.paymentModes,
        [PaymentMode.fomapayDirect, PaymentMode.mobileMoney]);
    expect(fomapay.livemode, isFalse);
  });

  test('formatAmount et normalizePhone', () {
    expect(formatAmount(1000, Currency.cdf), '1 000 CDF');
    expect(formatAmount(1234567.5, Currency.usd), '1 234 567,50 USD');
    expect(formatAmount(12.5, Currency.cdf), '12,50 CDF');
    for (final input in [
      '0812345678',
      '812345678',
      '+243 81 234 5678',
      '243812345678'
    ]) {
      expect(normalizePhone(input), '+243812345678', reason: input);
    }
    expect(normalizePhone('81234'), isNull);
  });
}
