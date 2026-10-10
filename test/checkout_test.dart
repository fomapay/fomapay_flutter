import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomapay_flutter/fomapay_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Faux backend : un paiement en mémoire, dont le test pilote l'état.
class FakeApi {
  FakeApi({this.storeModes = const ['fomapay_direct', 'mobile_money'], this.failCreation = 0});

  final List<String> storeModes;

  /// Nombre de créations qui échouent avant de réussir.
  int failCreation;
  String status = 'pending';
  String? payerPhone;
  String? failureReason;
  int created = 0;
  final calls = <String>[];

  Map<String, dynamic> get payment => {
        'id': 'pay_$created',
        'reference': 'FP-TEST$created',
        'status': status,
        'amount': 1000,
        'currency': 'CDF',
        'paymentModes': ['fomapay_direct', 'mobile_money'],
        'qrCode': 'fomapay://pay/FP-TEST$created',
        'payerPhone': payerPhone,
        'failureReason': failureReason,
      };

  FomaPay client() => FomaPay(
        publicKey: 'pk_test_unit',
        apiUrl: 'https://api.test',
        maxRetries: 0,
        httpClient: MockClient((request) async {
          final path = request.url.path;
          calls.add('${request.method} $path');
          http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

          if (path == '/v1/store') return ok({'id': 's1', 'name': 'Chez Foma', 'paymentModes': storeModes});
          if (path == '/v1/payments' && request.method == 'POST') {
            if (failCreation > 0) {
              failCreation--;
              return http.Response(
                jsonEncode({
                  'error': {'code': 'ERROR_LEVEL_0_LIMIT_REACHED', 'message': 'Plafond mensuel atteint.'}
                }),
                403,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            created++;
            status = 'pending';
            return ok(payment);
          }
          if (path.endsWith('/mobile-money')) {
            payerPhone = (jsonDecode(request.body) as Map)['phone'] as String;
            status = 'processing';
          } else if (path.endsWith('/simulate')) {
            status = (jsonDecode(request.body) as Map)['outcome'] == 'success' ? 'success' : 'failed';
          }
          return ok(payment);
        }),
      );
}

void main() {
  const params = PaymentParams(amount: 1000, currency: Currency.cdf, orderId: 'CMD-2026-001');
  const poll = Duration(milliseconds: 100);

  /// Affiche une page avec un bouton qui ouvre la fenêtre de paiement ; renvoie de quoi lire son résultat.
  Future<List<Payment?>> open(WidgetTester tester, FakeApi api) async {
    final results = <Payment?>[];
    final fomapay = api.client();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(await showModalBottomSheet<Payment>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FomaPayCheckoutSheet(fomapay: fomapay, params: params, pollInterval: poll),
              )),
              child: const Text('Payer'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Payer'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('FomaPay Direct : QR code, simulation d’un succès, paiement renvoyé', (tester) async {
    final api = FakeApi();
    final results = await open(tester, api);

    expect(find.text('Chez Foma'), findsOneWidget);
    expect(find.text('CMD-2026-001'), findsOneWidget);
    expect(find.text('1 000 CDF'), findsOneWidget);
    expect(find.text('TEST'), findsOneWidget);
    expect(tester.widget<QrImageView>(find.byType(QrImageView)), isNotNull);
    expect(find.text('FP-TEST1'), findsOneWidget);

    await tester.tap(find.text('Simuler un succès'));
    await tester.pumpAndSettle();
    expect(find.text('Paiement réussi'), findsOneWidget);
    expect(find.text('Référence FP-TEST1'), findsOneWidget);

    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(results.single?.isSuccessful, isTrue);
    expect(results.single?.reference, 'FP-TEST1');
  });

  testWidgets('Mobile Money : numéro validé, attente sur le téléphone, confirmation par interrogation', (tester) async {
    final api = FakeApi();
    await open(tester, api);

    await tester.tap(find.text('Mobile Money'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);

    await tester.enterText(find.byType(TextField), '81 23');
    await tester.tap(find.text('Payer 1 000 CDF'));
    await tester.pump();
    expect(find.textContaining('9 chiffres'), findsOneWidget);
    expect(api.calls.where((c) => c.endsWith('/mobile-money')), isEmpty);

    await tester.tap(find.text('Airtel Money'));
    await tester.enterText(find.byType(TextField), '097 000 0000');
    await tester.tap(find.text('Payer 1 000 CDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Validez sur votre téléphone'), findsOneWidget);
    expect(find.textContaining('+243970000000'), findsOneWidget);

    // L'opérateur confirme : la fenêtre le découvre à l'interrogation suivante.
    api.status = 'success';
    await tester.pump(poll);
    await tester.pumpAndSettle();
    expect(find.text('Paiement réussi'), findsOneWidget);
  });

  testWidgets('un refus propose de réessayer avec un nouveau paiement', (tester) async {
    final api = FakeApi();
    final results = await open(tester, api);

    api.failureReason = 'Solde insuffisant.';
    await tester.tap(find.text('Simuler un échec'));
    await tester.pumpAndSettle();
    expect(find.text('Paiement refusé'), findsOneWidget);
    expect(find.text('Solde insuffisant.'), findsOneWidget);

    api.failureReason = null;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(api.created, 2);
    expect(find.text('FP-TEST2'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('boutique Niveau 0 : seul FomaPay Direct est proposé', (tester) async {
    await open(tester, FakeApi(storeModes: const ['fomapay_direct']));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Mobile Money'), findsNothing);
  });

  testWidgets('une création refusée affiche le message de l’API, puis réessaie', (tester) async {
    final api = FakeApi(failCreation: 1);
    await open(tester, api);
    expect(find.text('Paiement indisponible'), findsOneWidget);
    expect(find.text('Plafond mensuel atteint.'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
