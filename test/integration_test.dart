// Tests d'intégration contre le sandbox FomaPay. Ils ne s'exécutent que si
// FOMAPAY_TEST_PUBLIC_KEY (pk_test_…) est définie ; FOMAPAY_API_URL cible un backend local :
//
//   FOMAPAY_API_URL=http://localhost:8080 FOMAPAY_TEST_PUBLIC_KEY=pk_test_… flutter test test/integration_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fomapay_flutter/fomapay_flutter.dart';

void main() {
  final key = Platform.environment['FOMAPAY_TEST_PUBLIC_KEY'] ?? '';
  final apiUrl = Platform.environment['FOMAPAY_API_URL'];

  test('sandbox',
      skip: key.isEmpty ? 'FOMAPAY_TEST_PUBLIC_KEY non définie' : false,
      () async {
    final fomapay = FomaPay(
        publicKey: key,
        apiUrl:
            apiUrl == null || apiUrl.isEmpty ? FomaPay.defaultApiUrl : apiUrl);
    addTearDown(fomapay.close);

    final store = await fomapay.store();
    expect(store.livemode, isFalse);
    expect(store.paymentModes, hasLength(2));

    // Format standard d'une transaction, dans les deux modes.
    final payment = await fomapay.createPayment(const PaymentParams(
      amount: 1000,
      currency: Currency.cdf,
      orderId: 'CMD-2026-001',
      customer: Customer(
          name: 'Jean Marc', phone: '+243810000000', email: 'jean@example.com'),
      paymentModes: [PaymentMode.fomapayDirect, PaymentMode.mobileMoney],
      callbackUrl: 'https://marchand.cd/api/callback',
      metadata: {'custom_field': 'valeur'},
    ));
    expect(payment.status, PaymentStatus.pending);
    expect(payment.callbackUrl, 'https://marchand.cd/api/callback');
    expect(payment.qrCode, isNotEmpty);
    expect(payment.metadata, {'custom_field': 'valeur'});

    // Mode Mobile Money : l'opérateur simulé confirme après ~3 s.
    final processing = await fomapay.payWithMobileMoney(payment.id,
        operator: MobileOperator.airtelMoney, phone: '+243970000000');
    expect(processing.status, PaymentStatus.processing);
    final paid = await fomapay.waitForPayment(payment.reference,
        interval: const Duration(seconds: 1),
        timeout: const Duration(seconds: 12));
    expect(paid.isSuccessful, isTrue);
    expect(paid.channel, 'airtel_money');

    // Numéro terminé par 0001 : refus de l'opérateur.
    final other = await fomapay
        .createPayment(const PaymentParams(amount: 5, currency: Currency.usd));
    await fomapay.payWithMobileMoney(other.id,
        operator: MobileOperator.mpesa, phone: '+243810000001');
    final refused = await fomapay.waitForPayment(other.id,
        interval: const Duration(seconds: 1),
        timeout: const Duration(seconds: 12));
    expect(refused.status, PaymentStatus.failed);

    // Mode FomaPay Direct : issue forcée en sandbox.
    final direct = await fomapay.createPayment(const PaymentParams(
        amount: 12.5,
        currency: Currency.usd,
        paymentModes: [PaymentMode.fomapayDirect]));
    expect((await fomapay.simulatePayment(direct.id)).isSuccessful, isTrue);

    // Idempotence : la même clé renvoie le même paiement.
    final same = PaymentParams(
        amount: 3,
        currency: Currency.usd,
        idempotencyKey: 'dart-it-${payment.id}');
    expect((await fomapay.createPayment(same)).id,
        (await fomapay.createPayment(same)).id);

    await expectLater(
      fomapay.createPayment(
          const PaymentParams(amount: -1, currency: Currency.usd)),
      throwsA(isA<FomaPayApiException>()
          .having((e) => e.code, 'code', 'ERROR_VALIDATION')),
    );
    await expectLater(
      fomapay.getPayment('FP-INEXISTANT'),
      throwsA(
          isA<FomaPayApiException>().having((e) => e.status, 'status', 404)),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
