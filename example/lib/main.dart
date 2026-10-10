// Exemple minimal : un bouton « Payer » qui ouvre la fenêtre de paiement FomaPay.
//
//   flutter run --dart-define=FOMAPAY_PUBLIC_KEY=pk_test_… --dart-define=FOMAPAY_API_URL=http://localhost:8080
import 'package:flutter/material.dart';
import 'package:fomapay_flutter/fomapay_flutter.dart';

final fomapay = FomaPay(
  publicKey: const String.fromEnvironment('FOMAPAY_PUBLIC_KEY'),
  apiUrl: const String.fromEnvironment('FOMAPAY_API_URL', defaultValue: FomaPay.defaultApiUrl),
);

void main() => runApp(const MaterialApp(home: ShopPage()));

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  Future<void> _pay(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final payment = await FomaPayCheckout.show(
      context,
      fomapay: fomapay,
      params: const PaymentParams(
        amount: 25000,
        currency: Currency.cdf,
        orderId: 'CMD-8921',
        description: 'Commande #CMD-8921',
      ),
    );
    // L'écran du client n'est pas une preuve : votre serveur confirme la commande par webhook.
    messenger.showSnackBar(SnackBar(
      content: Text(payment == null ? 'Paiement annulé' : 'Payé : ${payment.reference}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dzoket Store')),
      body: Center(
        child: FilledButton(
          onPressed: () => _pay(context),
          child: Text('Payer ${formatAmount(25000, Currency.cdf)}'),
        ),
      ),
    );
  }
}
