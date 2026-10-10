import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'models.dart';

/// Vérification des webhooks FomaPay (HMAC-SHA256), pour un backend écrit en Dart
/// (Dart Frog, Serverpod, shelf…). À ne pas utiliser dans l'application : le secret
/// `whsec_…` ne doit jamais y être embarqué.
abstract final class FomaPayWebhook {
  /// En-tête HTTP qui porte la signature.
  static const signatureHeader = 'X-FomaPay-Signature';

  /// Âge maximal accepté pour un événement (anti-rejeu).
  static const defaultTolerance = Duration(minutes: 5);

  /// Indique si la signature est valide pour ce corps BRUT.
  static bool verify(String payload, String? header, String secret, {Duration tolerance = defaultTolerance, DateTime? now}) {
    if (secret.isEmpty) {
      throw const FomaPayException('ERROR_WEBHOOK_SECRET_MISSING', 'Le secret de signature du webhook (whsec_…) est requis.');
    }
    final parts = <String, String>{
      for (final part in (header ?? '').split(','))
        if (part.contains('=')) part.trim().split('=').first: part.trim().substring(part.trim().indexOf('=') + 1),
    };
    final timestamp = parts['t'] ?? '';
    final signature = (parts['v1'] ?? '').toLowerCase();
    if (!RegExp(r'^\d{1,18}$').hasMatch(timestamp) || signature.isEmpty) return false;

    final expected = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$timestamp.$payload')).toString();
    // Comparaison en temps constant.
    var diff = expected.length ^ signature.length;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ (i < signature.length ? signature.codeUnitAt(i) : 0);
    }
    if (diff != 0) return false;

    // L'horodatage n'est contrôlé qu'après la signature : il est alors authentique.
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return (seconds - int.parse(timestamp)).abs() <= tolerance.inSeconds;
  }

  /// Vérifie la signature puis renvoie l'événement ; lève [FomaPaySignatureException] sinon.
  static WebhookEvent constructEvent(String payload, String? header, String secret,
      {Duration tolerance = defaultTolerance, DateTime? now}) {
    if (!verify(payload, header, secret, tolerance: tolerance, now: now)) {
      throw const FomaPaySignatureException('ERROR_INVALID_SIGNATURE', 'Signature de webhook invalide ou expirée.');
    }
    try {
      return WebhookEvent.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    } catch (_) {
      throw const FomaPaySignatureException('ERROR_INVALID_PAYLOAD', "Le corps du webhook n'est pas un événement FomaPay valide.");
    }
  }
}
