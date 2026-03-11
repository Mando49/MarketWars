import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../search/stock_detail_screen.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _searchCtrl = TextEditingController();
  List<StockResult> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final res = await context.read<PortfolioProvider>().searchStocks(query);
    if (mounted) {
      setState(() {
        _searchResults = res;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: () => context.read<PortfolioProvider>().refreshPrices(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text('↻',
                    style: TextStyle(color: AppTheme.green, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<PortfolioProvider>(
        builder: (_, prov, __) {
          if (prov.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.green));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              // ── Value card ──
              _PortfolioValueCard(prov: prov),

              // ── Long Holdings ──
              if (prov.holdings.isEmpty)
                _EmptyHoldings()
              else ...[
                _SectionLabel('Holdings', count: prov.holdings.length),
                _Card(
                    child: Column(
                  children: prov.holdings
                      .map((h) => _HoldingTile(holding: h))
                      .toList(),
                )),
              ],

              // ── Short Positions ──
              if (prov.shortPositions.isNotEmpty) ...[
                _SectionLabel('📉 Short Positions',
                    count: prov.shortPositions.length),
                ...prov.shortPositions.map((p) => _ShortTile(position: p)),
              ],

              // ── Recent Trades ──
              if (prov.trades.isNotEmpty) ...[
                const _SectionLabel('Recent Trades'),
                _Card(
                    child: Column(
                  children: prov.trades
                      .take(5)
                      .map((t) => _TradeTile(trade: t))
                      .toList(),
                )),
              ],

              // ── Search Stocks ──
              _buildSearchSection(),

              // ── Trending Movers ──
              _TrendingSection(prov: prov),

              // ── Disclaimer ──
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Simulated portfolio performance does not reflect real investment '
                  'results. Market Wars is not a registered investment advisor. '
                  'For entertainment only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                    fontFamily: 'Courier',
                    height: 1.5,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('🔍 SEARCH STOCKS',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                fontFamily: 'Courier',
                letterSpacing: 2,
              )),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              const Padding(
                  padding: EdgeInsets.only(left: 14),
                  child: Icon(Icons.search_rounded,
                      color: AppTheme.textMuted, size: 20)),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Ticker or company name...',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                  onChanged: _search,
                ),
              ),
              if (_isSearching)
                const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.green))),
              if (!_isSearching && _searchCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _searchResults = []);
                    },
                    child: const Icon(Icons.close_rounded,
                        color: AppTheme.textMuted, size: 18),
                  ),
                ),
            ]),
          ),
        ),
        if (_searchResults.isNotEmpty)
          _Card(
            child: Column(
              children: _searchResults
                  .map((r) => GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => StockDetailScreen(
                                    symbol: r.symbol,
                                    companyName: r.description))),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: AppTheme.border)),
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.greenDim,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color:
                                        AppTheme.green.withValues(alpha: 0.18)),
                              ),
                              child: Text(r.symbol,
                                  style: const TextStyle(
                                    color: AppTheme.green,
                                    fontFamily: 'Courier',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.description,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(r.type,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 9,
                                        fontFamily: 'Courier',
                                      )),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppTheme.textMuted, size: 18),
                          ]),
                        ),
                      ))
                  .toList(),
            ),
          ),
        if (_searchCtrl.text.isNotEmpty &&
            _searchResults.isEmpty &&
            !_isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: Text('No results found',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
          ),
      ],
    );
  }
}

// ── Portfolio value card ──
class _PortfolioValueCard extends StatelessWidget {
  final PortfolioProvider prov;
  const _PortfolioValueCard({required this.prov});

  @override
  Widget build(BuildContext context) {
    final isUp = prov.totalGainLoss >= 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A0F1A), Color(0xFF060810)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.green.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(children: [
        const Text('PORTFOLIO VALUE',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.textMuted,
              letterSpacing: 2,
              fontFamily: 'Courier',
            )),
        const SizedBox(height: 6),
        Text(AppTheme.currency(prov.totalPortfolioValue),
            style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: isUp ? AppTheme.greenDim : AppTheme.redDim,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
                color: (isUp ? AppTheme.green : AppTheme.red)
                    .withValues(alpha: 0.2)),
          ),
          child: Text(
            '${isUp ? "▲ +" : "▼ "}${AppTheme.currency(prov.totalGainLoss.abs())} '
            '(${prov.totalGainLossPercent.toStringAsFixed(2)}%)',
            style: TextStyle(
              color: isUp ? AppTheme.green : AppTheme.red,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Courier',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Cash: ${AppTheme.currency(prov.userProfile?.cashBalance ?? 0)}',
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontFamily: 'Courier')),
      ]),
    );
  }
}

// ── Long holding tile ──
class _HoldingTile extends StatelessWidget {
  final PortfolioHolding holding;
  const _HoldingTile({required this.holding});

  @override
  Widget build(BuildContext context) {
    final isUp = holding.gainLoss >= 0;
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                  symbol: holding.symbol, companyName: holding.companyName))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: isUp ? AppTheme.green : AppTheme.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(holding.symbol,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                Text(holding.companyName,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${holding.shares.toStringAsFixed(4)} shares @ ${AppTheme.currency(holding.averageCost)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'Courier')),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(AppTheme.currency(holding.totalValue),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(
              '${isUp ? "+" : ""}${AppTheme.currency(holding.gainLoss)} '
              '(${holding.gainLossPercent.toStringAsFixed(1)}%)',
              style: TextStyle(
                color: isUp ? AppTheme.green : AppTheme.red,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                fontFamily: 'Courier',
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Short position tile ──
class _ShortTile extends StatelessWidget {
  final ShortPosition position;
  const _ShortTile({required this.position});

  @override
  Widget build(BuildContext context) {
    final isProfit = position.gainLoss >= 0;
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                  symbol: position.symbol, companyName: position.companyName))),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.purple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.purple.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: isProfit ? AppTheme.green : AppTheme.red,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Text(position.symbol,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: AppTheme.purple.withValues(alpha: 0.3)),
                    ),
                    child: const Text('SHORT',
                        style: TextStyle(
                          color: AppTheme.purple,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Courier',
                        )),
                  ),
                ]),
                Text(position.companyName,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${position.shares.toStringAsFixed(4)} shares shorted @ '
                    '${AppTheme.currency(position.priceAtShort)}',
                    style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        fontFamily: 'Courier')),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(AppTheme.currency(position.currentPrice),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(
              '${isProfit ? "+" : ""}${AppTheme.currency(position.gainLoss)} '
              '(${position.gainLossPercent.toStringAsFixed(1)}%)',
              style: TextStyle(
                color: isProfit ? AppTheme.green : AppTheme.red,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                fontFamily: 'Courier',
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Trade history tile ──
class _TradeTile extends StatelessWidget {
  final Trade trade;
  const _TradeTile({required this.trade});

  @override
  Widget build(BuildContext context) {
    final emoji = trade.type == TradeType.buy
        ? '🟢'
        : trade.type == TradeType.sell
            ? '🔴'
            : trade.type == TradeType.short
                ? '📉'
                : '✅'; // coverShort

    final label = trade.type == TradeType.buy
        ? 'Bought'
        : trade.type == TradeType.sell
            ? 'Sold'
            : trade.type == TradeType.short
                ? 'Shorted'
                : 'Covered';

    final color = trade.type == TradeType.buy
        ? AppTheme.green
        : (trade.type == TradeType.short || trade.type == TradeType.coverShort)
            ? AppTheme.purple
            : AppTheme.red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label ${trade.symbol}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
              '${trade.shares.toStringAsFixed(4)} shares @ '
              '${AppTheme.currency(trade.pricePerShare)}',
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontFamily: 'Courier')),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(AppTheme.currency(trade.totalAmount),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                fontFamily: 'Courier',
              )),
          Text('${trade.timestamp.month}/${trade.timestamp.day}',
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontFamily: 'Courier')),
        ]),
      ]),
    );
  }
}

// ── Trending movers ──
class _TrendingSection extends StatelessWidget {
  final PortfolioProvider prov;
  const _TrendingSection({required this.prov});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(children: [
          const Text('🔥 TRENDING',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                fontFamily: 'Courier',
                letterSpacing: 2,
              )),
          const Spacer(),
          if (prov.isTrendingLoading)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.green)),
          if (!prov.isTrendingLoading)
            GestureDetector(
              onTap: () => prov.loadTrending(),
              child: const Text('Refresh',
                  style: TextStyle(
                      color: AppTheme.green,
                      fontSize: 11,
                      fontFamily: 'Courier')),
            ),
        ]),
      ),
      if (prov.trendingStocks.isEmpty && !prov.isTrendingLoading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: Text('No trending data — tap Refresh',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        )
      else
        _Card(
            child: Column(
          children:
              prov.trendingStocks.map((s) => _TrendingTile(stock: s)).toList(),
        )),
    ]);
  }
}

class _TrendingTile extends StatelessWidget {
  final TrendingStock stock;
  const _TrendingTile({required this.stock});

  @override
  Widget build(BuildContext context) {
    final isUp = stock.isUp;
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => StockDetailScreen(
                  symbol: stock.symbol, companyName: stock.companyName))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(children: [
          SizedBox(
              width: 26,
              child: Text('${stock.rank}',
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                  textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(stock.symbol,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
                Text(stock.companyName,
                    style:
                        const TextStyle(color: AppTheme.textMuted, fontSize: 9),
                    overflow: TextOverflow.ellipsis),
              ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(AppTheme.currency(stock.price),
                style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            Text(
                '${isUp ? "▲ +" : "▼ "}${stock.changePercent.abs().toStringAsFixed(2)}%',
                style: TextStyle(
                  color: isUp ? AppTheme.green : AppTheme.red,
                  fontFamily: 'Courier',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ]),
        ]),
      ),
    );
  }
}

// ── Shared widgets ──
class _EmptyHoldings extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Column(children: [
          Text('📊', style: TextStyle(fontSize: 44)),
          SizedBox(height: 8),
          Text('No holdings yet', style: TextStyle(color: AppTheme.textMuted)),
          SizedBox(height: 4),
          Text('Search for stocks to start trading!',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ]),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final int? count;
  const _SectionLabel(this.text, {this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(children: [
        Text(text.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Courier',
              fontSize: 10,
              color: AppTheme.textMuted,
              letterSpacing: 1.5,
            )),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text('$count',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.green,
                  fontFamily: 'Courier',
                )),
          ),
        ],
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: child,
        ),
      );
}
