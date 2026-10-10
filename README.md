# fomapay_flutter

SDK Flutter officiel de **FomaPay** : une fenêtre de paiement prête à l'emploi pour encaisser en RDC par **FomaPay Direct** (QR code, dès le Niveau 0) et par **Mobile Money** (M-Pesa, Orange Money, Airtel Money, dès le Niveau 1).

- Bottom sheet soignée, thèmes clair et sombre, Android, iOS, web et desktop
- N'embarque que la clé **publique** `pk_…` : aucun secret dans l'application
- Nouvelles tentatives automatiques et délai d'attente
- Mode test intégré (« Simuler un succès / un échec »)

## Intégration en 3 étapes

### 1. Installer

```bash
flutter pub add fomapay_flutter
```

### 2. Ouvrir la fenêtre de paiement

```dart
import 'package:fomapay_flutter/fomapay_flutter.dart';

final fomapay = FomaPay(publicKey: 'pk_test_…'); // FomaPay Business › Développeurs

final payment = await FomaPayCheckout.show(
  context,
  fomapay: fomapay,
  params: const PaymentParams(
    amount: 1000,
    currency: Currency.cdf,
    orderId: 'CMD-2026-001',
    customer: Customer(name: 'Jean Marc', phone: '+243810000000', email: 'jean@example.com'),
    paymentModes: [PaymentMode.fomapayDirect, PaymentMode.mobileMoney],
    callbackUrl: 'https://marchand.cd/api/callback',
    metadata: {'custom_field': 'valeur'},
  ),
);

if (payment != null) {
  // Paiement confirmé à l'écran : affichez la suite de la commande.
}
```

`show` renvoie le paiement confirmé, ou `null` si le client a fermé la fenêtre. Seuls les modes que le niveau KYC de la boutique autorise sont proposés.

### 3. Confirmer la commande sur votre serveur

L'écran du client n'est jamais une preuve de paiement. Votre serveur reçoit le webhook `payment.succeeded`, signé, et valide la commande : voyez les SDKs serveur (`fomapay-php`, `fomapay-python`, `fomapay-go`, `fomapay-java`, `@fomapay/sdk-js/server`).

## Personnaliser

```dart
FomaPayCheckout.show(
  context,
  fomapay: fomapay,
  params: params,
  customization: const CheckoutCustomization(
    title: 'Dzoket Store',
    description: 'Commande #CMD-8921',
    logoUrl: 'https://dzoket.cd/logo.png',
    accentColor: Color(0xFF7A1FA2),
  ),
);
```

Pour une interface entièrement sur mesure, deux niveaux sont disponibles :

- `CheckoutController` (un `ChangeNotifier`) porte toute la logique de la fenêtre — création, choix du mode, suivi, nouvelle tentative — sans aucun widget ;
- le client `FomaPay` expose les appels bruts : `createPayment`, `payWithMobileMoney`, `getPayment`, `waitForPayment`, `store`, `simulatePayment` (sandbox).

Le widget `FomaPayCheckoutSheet` peut aussi être placé ailleurs que dans une bottom sheet (page plein écran, dialogue sur desktop).

## Erreurs

```dart
try {
  await fomapay.createPayment(params);
} on FomaPayApiException catch (e) {      // l'API a répondu avec une erreur
  print('${e.code} (${e.status}) : ${e.message}'); // ex. ERROR_LEVEL_0_LIMIT_REACHED
} on FomaPayNetworkException catch (e) {  // ERROR_NETWORK ou ERROR_TIMEOUT
  print(e.message);
}
```

La fenêtre de paiement gère elle-même ces erreurs et propose « Réessayer ».

## Fiabilité

```dart
final fomapay = FomaPay(
  publicKey: 'pk_live_…',
  timeout: const Duration(seconds: 15), // 30 s par défaut
  maxRetries: 3,                        // 2 par défaut
);
```

- **Nouvelles tentatives** avec attente exponentielle (0,5 s, 1 s… plafonnée à 8 s). Ne sont rejouées que les requêtes sans risque : les lectures, et les créations de paiement, qui portent toujours un en-tête `Idempotency-Key`. Un `429` est toujours rejoué en respectant `Retry-After`.
- **Idempotence** : `PaymentParams(idempotencyKey: 'CMD-2026-001')` pour qu'un double appui ne crée qu'un paiement.
- **Réseau instable** : pendant l'attente, une coupure passagère n'interrompt pas la fenêtre ; le suivi reprend à l'interrogation suivante.

## Sandbox

Avec une clé `pk_test_…`, aucun argent ne circule et la fenêtre affiche le badge « TEST ». Numéros Mobile Money de test : terminé par `0001` → refusé, par `0002` → jamais validé, sinon confirmé après ~3 s.

## Backend en Dart

Si votre serveur est écrit en Dart (Dart Frog, Serverpod, shelf), `FomaPayWebhook.verify(payload, header, secret)` et `FomaPayWebhook.constructEvent(...)` vérifient la signature HMAC-SHA256 des webhooks. Ne les utilisez pas dans l'application : le secret `whsec_…` ne doit jamais y figurer.

## Tests

```bash
flutter test
```

Tests d'intégration contre le sandbox (ignorés si la variable est absente) :

```bash
FOMAPAY_API_URL=http://localhost:8080 FOMAPAY_TEST_PUBLIC_KEY=pk_test_… flutter test test/integration_test.dart
```

Un exemple complet se trouve dans [example/lib/main.dart](example/lib/main.dart).

Licence MIT.
