/// Erreur de base du SDK. [code] est stable et exploitable par le programme
/// (ex. `ERROR_LEVEL_0_LIMIT_REACHED`) ; [message] est lisible par un humain.
class FomaPayException implements Exception {
  const FomaPayException(this.code, this.message,
      {this.status = 0, this.details = const {}});

  final String code;
  final String message;

  /// Statut HTTP (0 quand il n'y a pas eu de réponse).
  final int status;
  final Map<String, dynamic> details;

  @override
  String toString() => '$code: $message';
}

/// L'API a répondu avec une erreur.
class FomaPayApiException extends FomaPayException {
  const FomaPayApiException(super.code, super.message,
      {super.status, super.details});
}

/// Aucune réponse : connexion impossible (`ERROR_NETWORK`) ou délai dépassé (`ERROR_TIMEOUT`).
class FomaPayNetworkException extends FomaPayException {
  const FomaPayNetworkException(super.code, super.message);
}

/// Signature de webhook invalide ou expirée.
class FomaPaySignatureException extends FomaPayException {
  const FomaPaySignatureException(super.code, super.message)
      : super(status: 400);
}
