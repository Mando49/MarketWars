import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'i_stock_service.dart';

class FinnhubStockService implements IStockService {
  static const String _apiKey = 'd6et3ahr01qvn4o0v1sgd6et3ahr01qvn4o0v1t0';
  static const String _baseUrl = 'https://finnhub.io/api/v1';

  @override
  Future<StockQuote?> fetchQuote(String symbol) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/quote?symbol=$symbol&token=$_apiKey'),
      );
      if (res.statusCode == 200) {
        return StockQuote.fromJson(json.decode(res.body));
      }
    } catch (e) {
      debugPrint('Quote error: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> fetchCompanyProfile(String symbol) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/stock/profile2?symbol=$symbol&token=$_apiKey'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data.isNotEmpty && data['name'] != null) return data;
      }
    } catch (e) {
      debugPrint('Profile error: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> fetchBasicFinancials(String symbol) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/stock/metric?symbol=$symbol&metric=all&token=$_apiKey'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        return data['metric'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Metrics error: $e');
    }
    return null;
  }

  @override
  Future<List<double>?> fetchCandles(
      String symbol, String resolution, int from, int to) async {
    try {
      final res = await http.get(
        Uri.parse(
            '$_baseUrl/stock/candle?symbol=$symbol&resolution=$resolution'
            '&from=$from&to=$to&token=$_apiKey'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['s'] == 'ok' && data['c'] != null) {
          return (data['c'] as List).map((v) => (v as num).toDouble()).toList();
        }
      }
    } catch (e) {
      debugPrint('Candle error: $e');
    }
    return null;
  }

  @override
  Future<List<StockResult>> searchStocks(String query) async {
    try {
      final res = await http.get(
        Uri.parse(
            '$_baseUrl/search?q=${Uri.encodeComponent(query)}&token=$_apiKey'),
      );
      if (res.statusCode == 200) {
        return (json.decode(res.body)['result'] as List)
            .map((r) => StockResult.fromJson(r))
            .where((r) => r.type == 'Common Stock')
            .toList();
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
    return [];
  }
}
