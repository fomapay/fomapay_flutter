import 'dart:async';

import 'package:flutter/foundation.dart';

import '../client.dart';
import '../errors.dart';
import '../models.dart';

/// Étapes de la fenêtre de paiement.
enum CheckoutPhase {
  /// Création du paiement en cours.
  loading,

  /// Le client choisit son mode et paie.
  ready,

  /// Demande Mobile Money envoyée : le client valide sur son téléphone.
  processing,
  success,
  failed,

  /// Le paiement n'a pas pu être créé (réseau, plafond KYC…).
  error,
}

/// Logique de la fenêtre de paiement, indépendante de l'interface : crée le paiement,
/// suit son état et expose ce qu'il faut afficher. Utilisable seule pour une interface sur mesure.
class CheckoutController extends ChangeNotifier {
  CheckoutController(this.fomapay, this.params, {this.pollInterval = const Duration(milliseconds: 2500)});

  final FomaPay fomapay;
  final PaymentParams params;
  final Duration pollInterval;

  CheckoutPhase phase = CheckoutPhase.loading;
  StoreInfo? store;
  Payment? payment;
  PaymentMode? mode;

  /// Dernière erreur, à afficher au client.
  FomaPayException? error;

  /// Une action (envoi Mobile Money, simulation) est en cours.
  bool busy = false;

  Timer? _poll;
  bool _disposed = false;
  bool _firstAttempt = true;

  /// Modes proposés : ceux du paiement que la boutique a le droit d'utiliser.
  List<PaymentMode> get modes {
    final allowed = store?.paymentModes ?? const <PaymentMode>[];
    final requested = payment?.paymentModes ?? const <PaymentMode>[];
    return [
      for (final mode in PaymentMode.values)
        if (allowed.contains(mode) && (requested.isEmpty || requested.contains(mode))) mode,
    ];
  }

  /// Vrai en sandbox : la fenêtre propose alors de simuler l'issue.
  bool get isTest => !fomapay.livemode;

  /// Crée le paiement. Rappelée par « Réessayer » : un paiement échoué ne se rejoue pas, on en crée un autre.
  Future<void> start() async {
    _poll?.cancel();
    phase = CheckoutPhase.loading;
    error = null;
    payment = null;
    _notify();
    try {
      // La clé d'idempotence du marchand ne vaut que pour la première tentative.
      final attempt = _firstAttempt
          ? params
          : PaymentParams(
              amount: params.amount,
              currency: params.currency,
              orderId: params.orderId,
              description: params.description,
              customer: params.customer,
              paymentModes: params.paymentModes,
              callbackUrl: params.callbackUrl,
              metadata: params.metadata,
            );
      _firstAttempt = false;
      final results = await Future.wait([fomapay.store(), fomapay.createPayment(attempt)]);
      if (_disposed) return;
      store = results[0] as StoreInfo;
      payment = results[1] as Payment;
      mode = modes.isEmpty ? null : (modes.contains(mode) ? mode : modes.first);
      _apply(payment!);
      _startPolling();
    } on FomaPayException catch (e) {
      error = e;
      phase = CheckoutPhase.error;
    }
    _notify();
  }

  void selectMode(PaymentMode value) {
    if (phase != CheckoutPhase.ready || mode == value) return;
    mode = value;
    error = null;
    _notify();
  }

  /// Envoie la demande de débit sur le téléphone du client.
  Future<void> payWithMobileMoney(MobileOperator operator, String phone) =>
      _act(() => fomapay.payWithMobileMoney(payment!.id, operator: operator, phone: phone));

  /// Force l'issue du paiement (sandbox).
  Future<void> simulate({required bool success}) => _act(() => fomapay.simulatePayment(payment!.id, success: success));

  Future<void> _act(Future<Payment> Function() action) async {
    if (busy || payment == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      final updated = await action();
      if (_disposed) return;
      _apply(updated);
    } on FomaPayException catch (e) {
      error = e;
    }
    busy = false;
    _notify();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) async {
      final current = payment;
      if (current == null || !current.isPending || busy) return;
      try {
        final updated = await fomapay.getPayment(current.id);
        if (_disposed || payment?.id != updated.id) return;
        _apply(updated);
        _notify();
      } on FomaPayException {
        // Coupure passagère : la prochaine interrogation réessaiera.
      }
    });
  }

  void _apply(Payment updated) {
    payment = updated;
    phase = switch (updated.status) {
      PaymentStatus.pending => CheckoutPhase.ready,
      PaymentStatus.processing => CheckoutPhase.processing,
      PaymentStatus.success => CheckoutPhase.success,
      PaymentStatus.failed || PaymentStatus.expired => CheckoutPhase.failed,
    };
    if (!updated.isPending) _poll?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
