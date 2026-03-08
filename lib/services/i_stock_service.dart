import '../models/models.dart';

abstract class IStockService {
  Future<StockQuote?> fetchQuote(String symbol);
  Future<List<StockResult>> searchStocks(String query);
  Future<Map<String, dynamic>?> fetchCompanyProfile(String symbol);
  Future<Map<String, dynamic>?> fetchBasicFinancials(String symbol);
  Future<List<double>?> fetchCandles(String symbol, String resolution, int from, int to);
}
