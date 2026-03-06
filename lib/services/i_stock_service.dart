import '../models/models.dart';

abstract class IStockService {
  Future<StockQuote?> fetchQuote(String symbol);
  Future<List<StockResult>> searchStocks(String query);
}
