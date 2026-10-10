import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'models.dart';

/// Client FomaPay pour une application. N'utilise que la clé **publique** (`pk_…`) :
/// elle sait créer et suivre un paiement, rien d'autre. La clé secrète reste sur votre serveur.
///
/// ```dart
/// final fomapay = FomaPay(publicKey: 'pk_test_…');
/// ```
class FomaPay {
  FomaPay({
    required this.publicKey,
    String apiUrl = defaultApiUrl,
    this.timeout = const Duration(seconds: 30),
    int maxRetries = 2,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
  })  : _baseUrl = apiUrl.replaceFirst(RegExp(r'/+$'), ''),
        maxRetries = max(0, maxRetries),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null,
        _sleep = sleep ?? Future<void>.delayed {
    if (!RegExp(r'^pk_(test|live)_').hasMatch(publicKey)) {
      throw const FomaPayException(
        'ERROR_INVALID_API_KEY',
        'Clé publique absente ou mal formée : elle commence par pk_test_ ou pk_live_ (FomaPay Business › Développeurs).',
      );
    }
  }

  static const defaultApiUrl = 'https://api.fomapay.cd';
  static const version = '0.1.0';
  static const _maxBackoff = Duration(seconds: 8);
  static final _random = Random.secure();

  final String publicKey;

  /// Délai maximal d'une requête.
  final Duration timeout;

  /// Nouvelles tentatives après un échec rejouable.
  final int maxRetries;

  final String _baseUrl;
  final http.Client _http;
  final bool _ownsHttp;
  final Future<void> Function(Duration) _sleep;
  Future<StoreInfo>? _store;

  /// Faux avec une clé `pk_test_…` : aucun argent ne circule.
  bool get livemode => publicKey.startsWith('pk_live_');

  /// Boutique liée à la clé, avec les modes de paiement que son niveau KYC autorise (mise en cache).
  Future<StoreInfo> store() => _store ??= _request('GET', '/v1/store')
          .then(StoreInfo.fromJson, onError: (Object e) {
        _store = null;
        throw e;
      });

  /// Crée une demande de paiement. Porte toujours une clé d'idempotence : rejouable sans doublon.
  Future<Payment> createPayment(PaymentParams params) => _request(
        'POST',
        '/v1/payments',
        body: params.toJson(),
        idempotencyKey: params.idempotencyKey ?? newIdempotencyKey(),
      ).then(Payment.fromJson);

  /// Relit un paiement par son identifiant ou sa référence (FP-…).
  Future<Payment> getPayment(String id) =>
      _request('GET', '/v1/payments/${Uri.encodeComponent(id)}')
          .then(Payment.fromJson);

  /// Envoie la demande de débit (push USSD) sur le téléphone du client.
  Future<Payment> payWithMobileMoney(String id,
          {required MobileOperator operator, required String phone}) =>
      _request(
        'POST',
        '/v1/payments/${Uri.encodeComponent(id)}/mobile-money',
        body: {'operator': operator.value, 'phone': phone},
      ).then(Payment.fromJson);

  /// Force l'issue d'un paiement. Sandbox uniquement.
  Future<Payment> simulatePayment(String id, {bool success = true}) => _request(
        'POST',
        '/v1/payments/${Uri.encodeComponent(id)}/simulate',
        body: {'outcome': success ? 'success' : 'failed'},
      ).then(Payment.fromJson);

  /// Attend l'issue d'un paiement (succès, échec ou expiration).
  Future<Payment> waitForPayment(
    String id, {
    Duration interval = const Duration(milliseconds: 2500),
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final payment = await getPayment(id);
      if (!payment.isPending) return payment;
      if (DateTime.now().isAfter(deadline)) {
        throw const FomaPayException('ERROR_PAYMENT_TIMEOUT',
            "Le paiement n'a pas été confirmé à temps.");
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Libère le client HTTP créé par le SDK.
  void close() {
    if (_ownsHttp) _http.close();
  }

  /// Clé unique : rejouer la requête ne crée pas de doublon.
  static String newIdempotencyKey() =>
      'dart-${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  /// 0,5 s, 1 s, 2 s… plafonné à 8 s, avec un aléa pour désynchroniser les clients.
  static Duration _backoff(int attempt) {
    final delay =
        min(500 * (1 << min(attempt, 10)), _maxBackoff.inMilliseconds);
    return Duration(milliseconds: delay ~/ 2 + _random.nextInt(delay ~/ 2 + 1));
  }

  /// Exécute une requête, avec nouvelles tentatives quand elle est rejouable sans risque
  /// (lecture, ou POST accompagné d'une clé d'idempotence).
  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body, String? idempotencyKey}) async {
    final replayable = method == 'GET' || idempotencyKey != null;
    for (var attempt = 0;; attempt++) {
      FomaPayException error;
      bool retry;
      Duration? wait;
      try {
        final request = http.Request(method, Uri.parse(_baseUrl + path))
          ..headers.addAll({
            'Authorization': 'Bearer $publicKey',
            'Accept': 'application/json',
            if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
            if (body != null) 'Content-Type': 'application/json',
          });
        if (body != null) request.body = jsonEncode(body);

        final response = await _http
            .send(request)
            .then(http.Response.fromStream)
            .timeout(timeout);
        final data = _decode(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (data is Map<String, dynamic>) return data;
          throw FomaPayApiException(
              'ERROR_INVALID_RESPONSE', "Réponse illisible de l'API FomaPay.",
              status: response.statusCode);
        }

        final envelope = data is Map && data['error'] is Map
            ? data['error'] as Map
            : const {};
        error = FomaPayApiException(
          envelope['code'] as String? ?? 'ERROR_UNKNOWN',
          envelope['message'] as String? ??
              'Erreur HTTP ${response.statusCode}',
          status: response.statusCode,
          details: envelope['details'] is Map
              ? Map<String, dynamic>.from(envelope['details'] as Map)
              : const {},
        );
        if (response.statusCode == 429) {
          // La gateway a refusé la requête avant tout traitement : toujours rejouable.
          retry = true;
          final retryAfter =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 0;
          if (retryAfter > 0) {
            wait = Duration(seconds: min(retryAfter, _maxBackoff.inSeconds));
          }
        } else {
          retry = response.statusCode >= 500 && replayable;
        }
      } on FomaPayException {
        rethrow;
      } on TimeoutException {
        error = const FomaPayNetworkException(
            'ERROR_TIMEOUT', "FomaPay n'a pas répondu dans le délai imparti.");
        retry = replayable;
      } catch (_) {
        error = const FomaPayNetworkException('ERROR_NETWORK',
            'Impossible de joindre FomaPay. Vérifiez votre connexion Internet.');
        retry = replayable;
      }

      if (!retry || attempt >= maxRetries) throw error;
      await _sleep(wait ?? _backoff(attempt));
    }
  }

  static dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
