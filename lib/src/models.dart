/// Devises acceptées.
enum Currency {
  usd('USD'),
  cdf('CDF');

  const Currency(this.code);

  /// Code ISO envoyé à l'API.
  final String code;

  static Currency parse(String? code) => values.firstWhere((c) => c.code == code, orElse: () => usd);
}

/// Modes de paiement proposés au client.
enum PaymentMode {
  /// Portefeuille FomaPay (QR / code marchand). Disponible dès le Niveau 0.
  fomapayDirect('fomapay_direct'),

  /// M-Pesa, Orange Money, Airtel Money. Réservé aux boutiques vérifiées (Niveau 1+).
  mobileMoney('mobile_money');

  const PaymentMode(this.value);
  final String value;

  static List<PaymentMode> parseList(dynamic list) => [
        for (final item in list is List ? list : const [])
          for (final mode in values)
            if (mode.value == item) mode,
      ];
}

/// Opérateurs Mobile Money.
enum MobileOperator {
  mpesa('mpesa', 'M-Pesa'),
  orangeMoney('orange_money', 'Orange Money'),
  airtelMoney('airtel_money', 'Airtel Money');

  const MobileOperator(this.value, this.label);
  final String value;

  /// Nom commercial, à afficher.
  final String label;
}

enum PaymentStatus {
  pending,
  processing,
  success,
  failed,
  expired;

  static PaymentStatus parse(String? value) => values.firstWhere((s) => s.name == value, orElse: () => pending);
}

/// Client final d'un paiement.
class Customer {
  const Customer({this.name, this.phone, this.email});

  final String? name;
  final String? phone;
  final String? email;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      Customer(name: json['name'] as String?, phone: json['phone'] as String?, email: json['email'] as String?);

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
      };
}

/// Paramètres de création d'un paiement.
class PaymentParams {
  const PaymentParams({
    required this.amount,
    required this.currency,
    this.orderId,
    this.description,
    this.customer,
    this.paymentModes,
    this.callbackUrl,
    this.metadata,
    this.idempotencyKey,
  });

  /// Montant en unités de la devise (12.5 = 12,50 USD).
  final num amount;
  final Currency currency;

  /// Votre identifiant de commande, renvoyé tel quel dans les webhooks.
  final String? orderId;
  final String? description;
  final Customer? customer;

  /// Par défaut, tous les modes que le niveau KYC de la boutique autorise.
  final List<PaymentMode>? paymentModes;

  /// Page de votre site vers laquelle renvoyer le client une fois le paiement terminé.
  final String? callbackUrl;
  final Map<String, dynamic>? metadata;

  /// Ex. l'identifiant de commande : un appel répété renvoie le même paiement.
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency.code,
        if (orderId != null) 'orderId': orderId,
        if (description != null) 'description': description,
        if (customer != null) 'customer': customer!.toJson(),
        if (paymentModes != null) 'paymentModes': [for (final mode in paymentModes!) mode.value],
        if (callbackUrl != null) 'callbackUrl': callbackUrl,
        if (metadata != null) 'metadata': metadata,
      };
}

/// Un paiement.
class Payment {
  const Payment({
    required this.id,
    required this.reference,
    required this.status,
    required this.amount,
    required this.currency,
    this.fee = 0,
    this.net = 0,
    this.channel,
    this.orderId,
    this.description,
    this.customer,
    this.metadata,
    this.paymentModes = const [],
    this.callbackUrl,
    this.payerPhone,
    this.qrCode,
    this.livemode = false,
    this.storeId,
    this.failureCode,
    this.failureReason,
    this.expiresAt,
    this.completedAt,
    this.createdAt,
    this.raw = const {},
  });

  final String id;

  /// Référence lisible (FP-…).
  final String reference;
  final PaymentStatus status;
  final num amount;
  final Currency currency;
  final num fee;
  final num net;

  /// Canal réellement utilisé (fomapay_direct, mpesa…).
  final String? channel;
  final String? orderId;
  final String? description;
  final Customer? customer;
  final Map<String, dynamic>? metadata;
  final List<PaymentMode> paymentModes;
  final String? callbackUrl;
  final String? payerPhone;

  /// Contenu du QR code à afficher au client (FomaPay Direct).
  final String? qrCode;
  final bool livemode;
  final String? storeId;
  final String? failureCode;
  final String? failureReason;
  final DateTime? expiresAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  /// Réponse JSON complète de l'API.
  final Map<String, dynamic> raw;

  bool get isSuccessful => status == PaymentStatus.success;

  /// Le paiement attend encore le client ou l'opérateur.
  bool get isPending => status == PaymentStatus.pending || status == PaymentStatus.processing;

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        status: PaymentStatus.parse(json['status'] as String?),
        amount: json['amount'] as num? ?? 0,
        currency: Currency.parse(json['currency'] as String?),
        fee: json['fee'] as num? ?? 0,
        net: json['net'] as num? ?? 0,
        channel: json['channel'] as String?,
        orderId: json['orderId'] as String?,
        description: json['description'] as String?,
        customer: json['customer'] is Map ? Customer.fromJson(Map<String, dynamic>.from(json['customer'] as Map)) : null,
        metadata: json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : null,
        paymentModes: PaymentMode.parseList(json['paymentModes']),
        callbackUrl: json['callbackUrl'] as String?,
        payerPhone: json['payerPhone'] as String?,
        qrCode: json['qrCode'] as String?,
        livemode: json['livemode'] == true,
        storeId: json['storeId'] as String?,
        failureCode: json['failureCode'] as String?,
        failureReason: json['failureReason'] as String?,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
        completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        raw: json,
      );
}

/// Boutique liée à la clé, avec les modes que son niveau KYC autorise.
class StoreInfo {
  const StoreInfo({
    required this.id,
    required this.name,
    this.shortCode = '',
    this.logoUrl,
    this.livemode = false,
    this.kycLevel = 0,
    this.paymentModes = const [],
  });

  final String id;
  final String name;
  final String shortCode;
  final String? logoUrl;
  final bool livemode;
  final int kycLevel;
  final List<PaymentMode> paymentModes;

  factory StoreInfo.fromJson(Map<String, dynamic> json) => StoreInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        shortCode: json['shortCode'] as String? ?? '',
        logoUrl: json['logoUrl'] as String?,
        livemode: json['livemode'] == true,
        kycLevel: (json['kycLevel'] as num?)?.toInt() ?? 0,
        paymentModes: PaymentMode.parseList(json['paymentModes']),
      );
}

/// Événement de webhook : `payment.succeeded`, `payment.failed`…
class WebhookEvent {
  const WebhookEvent({required this.id, required this.type, required this.created, required this.livemode, required this.data});

  final String id;
  final String type;
  final String created;
  final bool livemode;

  /// Le paiement concerné.
  final Payment data;

  factory WebhookEvent.fromJson(Map<String, dynamic> json) => WebhookEvent(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        created: json['created'] as String? ?? '',
        livemode: json['livemode'] == true,
        data: Payment.fromJson(json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : const {}),
      );
}

/// « 1 000 CDF », « 12,50 USD ».
String formatAmount(num amount, Currency currency) {
  final decimals = currency == Currency.cdf && amount == amount.roundToDouble() ? 0 : 2;
  final parts = amount.abs().toStringAsFixed(decimals).split('.');
  final digits = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(' ');
    grouped.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$grouped${decimals > 0 ? ',${parts[1]}' : ''} ${currency.code}';
}

/// Met un numéro congolais au format international :
/// « 081 234 5678 », « 812345678 » ou « +243 81… » deviennent « +243812345678 ».
/// Renvoie `null` si le numéro est incomplet.
String? normalizePhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('243')) digits = digits.substring(3);
  if (digits.startsWith('0')) digits = digits.substring(1);
  return digits.length == 9 ? '+243$digits' : null;
}
