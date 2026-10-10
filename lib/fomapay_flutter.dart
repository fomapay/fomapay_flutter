/// SDK Flutter officiel de FomaPay : fenêtre de paiement FomaPay Direct (QR code) et Mobile Money.
///
/// ```dart
/// final fomapay = FomaPay(publicKey: 'pk_test_…');
/// final payment = await FomaPayCheckout.show(
///   context,
///   fomapay: fomapay,
///   params: const PaymentParams(amount: 1000, currency: Currency.cdf, orderId: 'CMD-2026-001'),
/// );
/// ```
library;

export 'src/checkout/checkout_controller.dart';
export 'src/checkout/checkout_sheet.dart'
    show CheckoutCustomization, FomaPayCheckout, FomaPayCheckoutSheet;
export 'src/client.dart';
export 'src/errors.dart';
export 'src/models.dart';
export 'src/webhook.dart';
