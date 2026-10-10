import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../client.dart';
import '../models.dart';
import 'checkout_controller.dart';

/// Personnalisation de la fenêtre de paiement.
class CheckoutCustomization {
  const CheckoutCustomization(
      {this.title, this.description, this.logoUrl, this.accentColor});

  /// Nom affiché en tête (par défaut : celui de la boutique).
  final String? title;

  /// Sous-titre (par défaut : la description du paiement, ou le numéro de commande).
  final String? description;
  final String? logoUrl;

  /// Couleur du bouton principal (par défaut : le bleu FomaPay).
  final Color? accentColor;
}

/// Fenêtre de paiement FomaPay, présentée en bottom sheet.
abstract final class FomaPayCheckout {
  /// Ouvre la fenêtre de paiement.
  ///
  /// Renvoie le paiement **confirmé**, ou `null` si le client a fermé la fenêtre avant la fin.
  /// L'écran du client n'est jamais une preuve de paiement : confirmez toujours la commande
  /// côté serveur (webhook `payment.succeeded`).
  static Future<Payment?> show(
    BuildContext context, {
    required FomaPay fomapay,
    required PaymentParams params,
    CheckoutCustomization customization = const CheckoutCustomization(),
  }) {
    return showModalBottomSheet<Payment>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (_) => FomaPayCheckoutSheet(
          fomapay: fomapay, params: params, customization: customization),
    );
  }
}

class _Palette {
  const _Palette(
      {required this.surface,
      required this.card,
      required this.text,
      required this.muted,
      required this.border});

  static const navy = Color(0xFF032B56);
  static const blue = Color(0xFF2B7BD6);
  static const teal = Color(0xFF00C4B4);
  static const success = Color(0xFF12A150);
  static const danger = Color(0xFFD92D20);

  final Color surface;
  final Color card;
  final Color text;
  final Color muted;
  final Color border;

  static _Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const _Palette(
              surface: Color(0xFF0E1726),
              card: Color(0xFF172236),
              text: Color(0xFFF2F5F9),
              muted: Color(0xFF94A3B8),
              border: Color(0xFF26344D))
          : const _Palette(
              surface: Colors.white,
              card: Color(0xFFF5F7FA),
              text: Color(0xFF0B1B33),
              muted: Color(0xFF64748B),
              border: Color(0xFFE2E8F0));
}

/// Contenu de la fenêtre de paiement. À utiliser directement pour l'intégrer ailleurs que dans une bottom sheet.
class FomaPayCheckoutSheet extends StatefulWidget {
  const FomaPayCheckoutSheet({
    super.key,
    required this.fomapay,
    required this.params,
    this.customization = const CheckoutCustomization(),
    this.pollInterval = const Duration(milliseconds: 2500),
  });

  final FomaPay fomapay;
  final PaymentParams params;
  final CheckoutCustomization customization;
  final Duration pollInterval;

  @override
  State<FomaPayCheckoutSheet> createState() => _FomaPayCheckoutSheetState();
}

class _FomaPayCheckoutSheetState extends State<FomaPayCheckoutSheet> {
  late final CheckoutController _controller = CheckoutController(
      widget.fomapay, widget.params,
      pollInterval: widget.pollInterval)
    ..start();
  final _phone = TextEditingController();
  MobileOperator _operator = MobileOperator.mpesa;
  String? _phoneError;

  @override
  void dispose() {
    _controller.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Le bleu FomaPay, éclairci en thème sombre pour rester lisible.
  Color get _accent =>
      widget.customization.accentColor ??
      (Theme.of(context).brightness == Brightness.dark
          ? _Palette.blue
          : _Palette.navy);

  void _submitMobileMoney() {
    final phone = normalizePhone(_phone.text);
    setState(() => _phoneError = phone == null
        ? 'Entrez un numéro à 9 chiffres, ex. 81 234 5678'
        : null);
    if (phone != null) {
      FocusScope.of(context).unfocus();
      _controller.payWithMobileMoney(_operator, phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _Palette.of(context);
    final theme = Theme.of(context);
    // Thème local : les composants de la fenêtre prennent les couleurs FomaPay, pas celles de l'application hôte.
    return Theme(
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
                seedColor: _accent, brightness: theme.brightness)
            .copyWith(primary: _accent),
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Material(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _header(palette),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: KeyedSubtree(
                          key: ValueKey(_controller.phase),
                          child: _body(palette)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 14, color: palette.muted),
                      const SizedBox(width: 6),
                      Text('Paiement sécurisé par FomaPay',
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_Palette palette) {
    final title =
        widget.customization.title ?? _controller.store?.name ?? 'Paiement';
    final subtitle = widget.customization.description ??
        widget.params.description ??
        widget.params.orderId;
    final logo = widget.customization.logoUrl ?? _controller.store?.logoUrl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: _Palette.navy,
          foregroundImage: logo == null ? null : NetworkImage(logo),
          child: Text(
            title.isEmpty ? 'F' : title.characters.first.toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.text),
                    ),
                  ),
                  if (_controller.isTest) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF4D6),
                          borderRadius: BorderRadius.circular(999)),
                      child: const Text('TEST',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF8A5A00))),
                    ),
                  ],
                ],
              ),
              if (subtitle != null)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.muted)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatAmount(widget.params.amount, widget.params.currency),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: palette.text),
        ),
        IconButton(
          tooltip: 'Fermer',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.close_rounded, color: palette.muted),
        ),
      ],
    );
  }

  Widget _body(_Palette palette) {
    final payment = _controller.payment;
    switch (_controller.phase) {
      case CheckoutPhase.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Center(
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: _Palette.teal)),
        );
      case CheckoutPhase.error:
        return _Outcome(
          palette: palette,
          icon: Icons.wifi_off_rounded,
          color: _Palette.danger,
          title: 'Paiement indisponible',
          message: _controller.error?.message ?? 'Une erreur est survenue.',
          action: _primaryButton('Réessayer', _controller.start),
        );
      case CheckoutPhase.processing:
        return _Outcome(
          palette: palette,
          icon: Icons.phone_iphone_rounded,
          color: _accent,
          title: 'Validez sur votre téléphone',
          message:
              'Une demande de paiement a été envoyée au ${payment?.payerPhone ?? 'numéro indiqué'}. '
              'Saisissez votre code secret pour confirmer.',
          action: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: _Palette.teal)),
            ),
          ),
        );
      case CheckoutPhase.success:
        return _Outcome(
          palette: palette,
          icon: Icons.check_rounded,
          color: _Palette.success,
          title: 'Paiement réussi',
          message: 'Référence ${payment!.reference}',
          action: _primaryButton(
              'Terminer', () => Navigator.of(context).pop(payment)),
        );
      case CheckoutPhase.failed:
        return _Outcome(
          palette: palette,
          icon: Icons.close_rounded,
          color: _Palette.danger,
          title: payment?.status == PaymentStatus.expired
              ? 'Paiement expiré'
              : 'Paiement refusé',
          message: payment?.failureReason ??
              "Le paiement n'a pas abouti. Aucun montant n'a été débité.",
          action: _primaryButton('Réessayer', _controller.start),
        );
      case CheckoutPhase.ready:
        final modes = _controller.modes;
        if (modes.isEmpty) {
          return _Outcome(
            palette: palette,
            icon: Icons.block_rounded,
            color: _Palette.danger,
            title: 'Aucun mode de paiement',
            message: 'Cette boutique ne peut pas encore accepter ce paiement.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (modes.length > 1) ...[
              SegmentedButton<PaymentMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: PaymentMode.fomapayDirect,
                      label: Text('FomaPay'),
                      icon: Icon(Icons.qr_code_2_rounded)),
                  ButtonSegment(
                      value: PaymentMode.mobileMoney,
                      label: Text('Mobile Money'),
                      icon: Icon(Icons.phone_iphone_rounded)),
                ],
                selected: {_controller.mode!},
                onSelectionChanged: (selection) =>
                    _controller.selectMode(selection.first),
              ),
              const SizedBox(height: 18),
            ],
            if (_controller.mode == PaymentMode.fomapayDirect)
              _direct(palette, payment!)
            else
              _mobileMoney(palette),
            if (_controller.error != null) ...[
              const SizedBox(height: 12),
              Text(_controller.error!.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _Palette.danger, fontSize: 13)),
            ],
          ],
        );
    }
  }

  Widget _direct(_Palette palette, Payment payment) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: QrImageView(
            data: payment.qrCode ?? payment.reference,
            size: 196,
            padding: EdgeInsets.zero,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: _Palette.navy),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: _Palette.navy),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Scannez ce code avec l'application FomaPay",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: palette.text),
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              Clipboard.setData(ClipboardData(text: payment.reference)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(payment.reference,
                    style: TextStyle(
                        fontSize: 13,
                        color: palette.muted,
                        letterSpacing: 0.4)),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 14, color: palette.muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _Palette.teal)),
            const SizedBox(width: 10),
            Text('En attente du paiement…',
                style: TextStyle(fontSize: 13, color: palette.muted)),
          ],
        ),
        if (_controller.isTest) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _controller.busy
                      ? null
                      : () => _controller.simulate(success: true),
                  child: const Text('Simuler un succès'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _controller.busy
                      ? null
                      : () => _controller.simulate(success: false),
                  child: const Text('Simuler un échec'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _mobileMoney(_Palette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final operator in MobileOperator.values) ...[
              if (operator != MobileOperator.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: _OperatorTile(
                  palette: palette,
                  operator: operator,
                  selected: operator == _operator,
                  accent: _accent,
                  onTap: () => setState(() => _operator = operator),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d +]')),
            LengthLimitingTextInputFormatter(17)
          ],
          onSubmitted: (_) => _submitMobileMoney(),
          style: TextStyle(
              color: palette.text, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'Numéro ${_operator.label}',
            hintText: '81 234 5678',
            prefixText: '+243  ',
            errorText: _phoneError,
            filled: true,
            fillColor: palette.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        _primaryButton(
          'Payer ${formatAmount(widget.params.amount, widget.params.currency)}',
          _controller.busy ? null : _submitMobileMoney,
          loading: _controller.busy,
        ),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed,
      {bool loading = false}) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white))
          : Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _OperatorTile extends StatelessWidget {
  const _OperatorTile(
      {required this.palette,
      required this.operator,
      required this.selected,
      required this.accent,
      required this.onTap});

  final _Palette palette;
  final MobileOperator operator;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  static const _colors = {
    MobileOperator.mpesa: Color(0xFFE60000),
    MobileOperator.orangeMoney: Color(0xFFFF7900),
    MobileOperator.airtelMoney: Color(0xFFED1C24),
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: operator.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : palette.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? accent : palette.border,
                width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: _colors[operator], shape: BoxShape.circle)),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(
                  operator.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome(
      {required this.palette,
      required this.icon,
      required this.color,
      required this.title,
      required this.message,
      this.action});

  final _Palette palette;
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: color),
            ),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: palette.text)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, height: 1.4, color: palette.muted)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
