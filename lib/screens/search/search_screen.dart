import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/portfolio_provider.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'stock_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<StockResult> _results = [];
  bool _searching = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search(String query) async {
    if (query.isEmpty) { setState(() => _results = []); return; }
    setState(() => _searching = true);
    final res = await context.read<PortfolioProvider>().searchStocks(query);
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<PortfolioProvider>();
    final showTrending = _ctrl.text.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(children: [
        // ── Search box ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.08)),
            ),
            child: Row(children: [
              const Padding(
                padding: EdgeInsets.only(left: 14),
                child: Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20)),
              Expanded(child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  border: InputBorder.none, hintText: 'Ticker or company name...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                ),
                onChanged: _search,
              )),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.green))),
            ]),
          ),
        ),

        // ── Trending label or search label ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(
              showTrending ? '🔥 TRENDING' : 'RESULTS',
              style: const TextStyle(
                fontSize: 10, color: AppTheme.textMuted,
                fontFamily: 'Courier', letterSpacing: 2))),
        ),

        // ── Results list ──
        Expanded(child: showTrending
          ? _TrendingList(prov: prov)
          : _ResultsList(results: _results)),
      ]),
    );
  }
}

class _TrendingList extends StatelessWidget {
  final PortfolioProvider prov;
  const _TrendingList({required this.prov});

  @override
  Widget build(BuildContext context) {
    if (prov.isTrendingLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.green));
    }
    if (prov.trendingStocks.isEmpty) {
      return const Center(child: Text('Loading trending stocks...',
        style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      itemCount: prov.trendingStocks.length,
      itemBuilder: (_, i) => _TrendingRow(stock: prov.trendingStocks[i]),
    );
  }
}

class _TrendingRow extends StatelessWidget {
  final TrendingStock stock;
  const _TrendingRow({required this.stock});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => StockDetailScreen(
          symbol: stock.symbol, companyName: stock.companyName))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Row(children: [
          SizedBox(width: 26, child: Text('${stock.rank}',
            style: const TextStyle(
              fontFamily: 'Courier', fontSize: 12,
              fontWeight: FontWeight.w700, color: AppTheme.textMuted),
            textAlign: TextAlign.center)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.greenDim,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
            ),
            child: Text(stock.symbol,
              style: const TextStyle(
                color: AppTheme.green, fontFamily: 'Courier',
                fontSize: 11, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stock.companyName, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Text('COMMON STOCK',
              style: TextStyle(
                color: AppTheme.textMuted, fontSize: 9, fontFamily: 'Courier')),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(AppTheme.currency(stock.price),
              style: const TextStyle(
                fontFamily: 'Courier', fontSize: 13, fontWeight: FontWeight.w700)),
            Text(
              '${stock.isUp ? "▲ +" : "▼ "}${stock.changePercent.abs().toStringAsFixed(2)}%',
              style: TextStyle(
                color: stock.isUp ? AppTheme.green : AppTheme.red,
                fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<StockResult> results;
  const _ResultsList({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(child: Text('No results found',
        style: TextStyle(color: AppTheme.textMuted)));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final r = results[i];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => StockDetailScreen(
              symbol: r.symbol, companyName: r.description))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.greenDim, borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppTheme.green.withValues(alpha: 0.18))),
                child: Text(r.symbol,
                  style: const TextStyle(
                    color: AppTheme.green, fontFamily: 'Courier',
                    fontSize: 11, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.description, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(r.type,
                  style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 9, fontFamily: 'Courier')),
              ])),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 18),
            ]),
          ),
        );
      },
    );
  }
}
