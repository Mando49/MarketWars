import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final String companyName;

  const StockDetailScreen({
    super.key,
    required this.symbol,
    required this.companyName,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  StockQuote? _quote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = await context.read<PortfolioProvider>().fetchQuote(widget.symbol);
    if (mounted) setState(() { _quote = q; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final prov    = context.watch<PortfolioProvider>();
    final holding = prov.holdings.firstWhere(
      (h) => h.symbol == widget.symbol, orElse: () => PortfolioHolding(
        symbol: '', companyName: '', shares: 0, averageCost: 0, currentPrice: 0));
    final shortPos = prov.shortPositions.firstWhere(
      (p) => p.symbol == widget.symbol, orElse: () => ShortPosition(
        symbol: '', companyName: '', shares: 0, priceAtShort: 0, currentPrice: 0));

    final hasLong  = holding.symbol.isNotEmpty  && holding.shares > 0;
    final hasShort = shortPos.symbol.isNotEmpty && shortPos.shares > 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.symbol),
          Text(widget.companyName,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted,
              fontWeight: FontWeight.normal)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.green))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // ── Price card ──
                _PriceCard(quote: _quote),

                // ── Stats grid ──
                if (_quote != null) _StatsGrid(quote: _quote!),

                // ── Trade buttons ──
                _TradeButtons(
                  symbol: widget.symbol,
                  companyName: widget.companyName,
                  quote: _quote,
                  hasLong: hasLong,
                  hasShort: hasShort,
                  holdingShares: holding.shares,
                  shortShares: shortPos.shares,
                ),

                // ── Short explanation ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('📉 Short Selling',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppTheme.purple, fontFamily: 'Courier',
                      )),
                    const SizedBox(height: 4),
                    const Text(
                      'Bet this stock goes DOWN. You profit if the price drops '
                      'after you short it. Tap Cover to close your position and '
                      'lock in gains (or losses).',
                      style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11,
                        fontFamily: 'Courier', height: 1.5,
                      )),
                    if (hasShort) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Open: ${shortPos.shares.toStringAsFixed(4)} shares @ '
                        '\$${shortPos.priceAtShort.toStringAsFixed(2)} · '
                        'P&L: ${shortPos.gainLoss >= 0 ? "+" : ""}'
                        '\$${shortPos.gainLoss.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: shortPos.gainLoss >= 0 ? AppTheme.green : AppTheme.red,
                          fontSize: 11, fontFamily: 'Courier', fontWeight: FontWeight.w700,
                        )),
                    ],
                  ]),
                ),

                if (prov.errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(prov.errorMessage,
                      style: const TextStyle(color: AppTheme.red, fontSize: 13),
                      textAlign: TextAlign.center),
                  ),
              ],
            ),
    );
  }
}

// ── Price card ──
class _PriceCard extends StatelessWidget {
  final StockQuote? quote;
  const _PriceCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    if (quote == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Unable to load quote',
          style: TextStyle(color: AppTheme.textMuted))));
    }
    final isUp = quote!.isPositive;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF101520), Color(0xFF0B0E17)]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border.withValues(alpha: 2)),
      ),
      child: Column(children: [
        Text('\$${quote!.currentPrice.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isUp ? AppTheme.greenDim : AppTheme.redDim,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: (isUp ? AppTheme.green : AppTheme.red).withValues(alpha: 0.2)),
          ),
          child: Text(
            '${isUp ? "▲ +" : "▼ "}\$${quote!.change.abs().toStringAsFixed(2)} '
            '(${quote!.changePercent.abs().toStringAsFixed(2)}%) today',
            style: TextStyle(
              color: isUp ? AppTheme.green : AppTheme.red,
              fontWeight: FontWeight.w700, fontSize: 12, fontFamily: 'Courier',
            )),
        ),
      ]),
    );
  }
}

// ── Stats grid ──
class _StatsGrid extends StatelessWidget {
  final StockQuote quote;
  const _StatsGrid({required this.quote});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('OPEN',       '\$${quote.open.toStringAsFixed(2)}',     AppTheme.textPrimary),
      ('PREV CLOSE', '\$${quote.prevClose.toStringAsFixed(2)}', AppTheme.textPrimary),
      ('HIGH',       '\$${quote.high.toStringAsFixed(2)}',     AppTheme.green),
      ('LOW',        '\$${quote.low.toStringAsFixed(2)}',      AppTheme.red),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.6,
        children: stats.map((s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(s.$1, style: const TextStyle(
              fontSize: 9, color: AppTheme.textMuted,
              fontFamily: 'Courier', letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(s.$2, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              fontFamily: 'Courier', color: s.$3)),
          ]),
        )).toList(),
      ),
    );
  }
}

// ── Buy / Sell / Short / Cover buttons ──
class _TradeButtons extends StatelessWidget {
  final String symbol, companyName;
  final StockQuote? quote;
  final bool hasLong, hasShort;
  final double holdingShares, shortShares;

  const _TradeButtons({
    required this.symbol, required this.companyName, required this.quote,
    required this.hasLong, required this.hasShort,
    required this.holdingShares, required this.shortShares,
  });

  void _open(BuildContext context, String mode) {
    if (quote == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _TradeModal(
        symbol: symbol, companyName: companyName,
        price: quote!.currentPrice, mode: mode,
        maxShares: mode == 'sell' ? holdingShares
                 : mode == 'cover' ? shortShares
                 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(children: [
        // Row 1: Buy + Sell
        Row(children: [
          Expanded(child: _Btn(
            label: 'Buy', color: AppTheme.green, textColor: Colors.black,
            onTap: () => _open(context, 'buy'))),
          const SizedBox(width: 10),
          Expanded(child: _Btn(
            label: hasLong ? 'Sell (${holdingShares.toStringAsFixed(2)})' : 'Sell',
            color: AppTheme.redDim, textColor: AppTheme.red,
            border: AppTheme.red.withValues(alpha: 0.3),
            onTap: hasLong ? () => _open(context, 'sell') : null)),
        ]),
        const SizedBox(height: 8),
        // Row 2: Short + Cover
        Row(children: [
          Expanded(child: _Btn(
            label: '📉 Short', color: AppTheme.purple.withValues(alpha: 0.08),
            textColor: AppTheme.purple, border: AppTheme.purple.withValues(alpha: 0.3),
            onTap: () => _open(context, 'short'))),
          const SizedBox(width: 10),
          Expanded(child: _Btn(
            label: hasShort ? '✅ Cover (${shortShares.toStringAsFixed(2)})' : '✅ Cover',
            color: AppTheme.purple.withValues(alpha: 0.15), textColor: AppTheme.purple,
            border: AppTheme.purple.withValues(alpha: 0.3),
            onTap: hasShort ? () => _open(context, 'cover') : null)),
        ]),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color, textColor;
  final Color? border;
  final VoidCallback? onTap;

  const _Btn({
    required this.label, required this.color,
    required this.textColor, this.border, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: disabled ? AppTheme.surface2 : color,
          borderRadius: BorderRadius.circular(14),
          border: border != null
              ? Border.all(color: disabled ? AppTheme.border : border!)
              : null,
        ),
        child: Center(child: Text(label,
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800,
            color: disabled ? AppTheme.textMuted : textColor,
          ))),
      ),
    );
  }
}

// ── Trade modal ──
class _TradeModal extends StatefulWidget {
  final String symbol, companyName, mode;
  final double price;
  final double? maxShares;

  const _TradeModal({
    required this.symbol, required this.companyName,
    required this.price, required this.mode, this.maxShares,
  });

  @override
  State<_TradeModal> createState() => _TradeModalState();
}

class _TradeModalState extends State<_TradeModal> {
  final _ctrl = TextEditingController(text: '1');
  bool _busy = false;

  double get _shares => double.tryParse(_ctrl.text) ?? 0;
  double get _total  => _shares * widget.price;

  Color get _accentColor =>
      widget.mode == 'buy'   ? AppTheme.green
    : widget.mode == 'sell'  ? AppTheme.red
    : AppTheme.purple; // short or cover

  String get _actionLabel =>
      widget.mode == 'buy'        ? 'Confirm Buy'
    : widget.mode == 'sell'       ? 'Confirm Sell'
    : widget.mode == 'short'      ? 'Confirm Short'
    : 'Confirm Cover';

  String? get _infoText =>
      widget.mode == 'short'
        ? '📉 You profit if the price goes DOWN. You lose if it goes UP.'
        : widget.mode == 'cover'
        ? '✅ Buying back shares to close your short position.'
        : null;

  Future<void> _confirm() async {
    final prov = context.read<PortfolioProvider>();
    setState(() => _busy = true);
    bool ok = false;
    switch (widget.mode) {
      case 'buy':
        ok = await prov.buyStock(widget.symbol, widget.companyName, _shares, widget.price);
        break;
      case 'sell':
        ok = await prov.sellStock(widget.symbol, _shares, widget.price);
        break;
      case 'short':
        ok = await prov.shortStock(widget.symbol, widget.companyName, _shares, widget.price);
        break;
      case 'cover':
        ok = await prov.coverShort(widget.symbol, _shares, widget.price);
        break;
    }
    if (mounted) {
      setState(() => _busy = false);
      if (ok) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = {
      'buy': 'Buy ${widget.symbol}', 'sell': 'Sell ${widget.symbol}',
      'short': '📉 Short ${widget.symbol}', 'cover': '✅ Cover ${widget.symbol}',
    };

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border.withValues(alpha: 5),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),

          // Title
          Text(titles[widget.mode]!,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Current price: \$${widget.price.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.textMuted, fontFamily: 'Courier', fontSize: 12)),

          // Info box for short/cover
          if (_infoText != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.purple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
              ),
              child: Text(_infoText!,
                style: const TextStyle(
                  color: AppTheme.purple, fontSize: 11,
                  fontFamily: 'Courier', height: 1.4),
                textAlign: TextAlign.center),
            ),
          ],

          const SizedBox(height: 16),

          // Share input
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border.withValues(alpha: 2)),
            ),
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Courier'),
              decoration: const InputDecoration(
                border: InputBorder.none, hintText: '0.0000',
                hintStyle: TextStyle(color: AppTheme.textMuted),
                suffixText: 'shares',
                suffixStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          const SizedBox(height: 10),

          // Total
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
            ),
            child: Center(child: Text('Total: \$${_total.toStringAsFixed(2)}',
              style: TextStyle(
                color: _accentColor, fontWeight: FontWeight.w700,
                fontSize: 14, fontFamily: 'Courier',
              ))),
          ),

          const SizedBox(height: 14),

          // Confirm button
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _busy ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor,
              foregroundColor: widget.mode == 'buy' ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(_actionLabel,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}
