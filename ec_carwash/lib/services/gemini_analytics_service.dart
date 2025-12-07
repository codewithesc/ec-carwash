import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to generate AI-powered analytics summaries using Google Gemini via Cloud Functions
class GeminiAnalyticsService {
  static const String _cloudFunctionUrl =
      'https://generateaisummary-eeutjvfm5a-uc.a.run.app';

  /// Generate AI summary for sales report
  static Future<String> generateSalesSummary({
    required double revenue,
    required int transactions,
    required double expenses,
    required double profitMargin,
    required Map<String, double> topServices,
    required String period,
  }) async {
    final topServicesStr = topServices.entries
        .take(3)
        .map((e) => '${e.key}: ₱${e.value.toStringAsFixed(2)}')
        .join(', ');

    final prompt = '''
Analyze this car wash business sales data for $period:
- Total Revenue: ₱${revenue.toStringAsFixed(2)}
- Total Expenses: ₱${expenses.toStringAsFixed(2)}
- Number of Transactions: $transactions
- Profit Margin: ${profitMargin.toStringAsFixed(1)}%
- Top Revenue Services: $topServicesStr

Provide 3-4 actionable business insights in a friendly, professional tone. Focus on:
1. Overall business performance
2. Revenue opportunities
3. Cost management suggestions
4. Specific recommendations

Keep it concise and practical for a car wash business owner.
''';

    return _generateText(prompt);
  }

  /// Generate AI summary for peak operating times
  static Future<String> generatePeakTimeSummary({
    required Map<dynamic, int> peakData,
    required String period,
    required String timeUnit,
  }) async {
    final sortedData = peakData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topPeriods = sortedData.take(3).map((e) {
      String label = _formatTimeLabel(e.key, timeUnit);
      return '$label: ${e.value} bookings';
    }).join(', ');

    final prompt = '''
Analyze peak operating times for a car wash business during $period:
- Busiest periods: $topPeriods
- Time granularity: $timeUnit

Provide 2-3 sentences with:
1. Key insights about customer traffic patterns
2. Staffing recommendations
3. Operational suggestions

Be specific and actionable.
''';

    return _generateText(prompt);
  }

  /// Generate AI summary for top services
  static Future<String> generateServicesSummary({
    required Map<String, double> serviceRevenue,
  }) async {
    final sortedServices = serviceRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalRevenue = serviceRevenue.values.fold(0.0, (sum, val) => sum + val);

    final servicesStr = sortedServices.take(5).map((e) {
      final percentage = (e.value / totalRevenue * 100).toStringAsFixed(1);
      return '${e.key}: ₱${e.value.toStringAsFixed(2)} ($percentage%)';
    }).join(', ');

    final prompt = '''
Analyze car wash service revenue distribution:
$servicesStr

Provide 2-3 sentences with:
1. Which services are performing well and why
2. Which services to promote more
3. Pricing or bundling opportunities

Be specific and actionable for a car wash business.
''';

    return _generateText(prompt);
  }

  /// Generate AI summary for expenses pattern
  static Future<String> generateExpensesSummary({
    required Map<String, double> expensesByCategory,
    required double totalExpenses,
  }) async {
    final sortedExpenses = expensesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final expensesStr = sortedExpenses.take(5).map((e) {
      final percentage = (e.value / totalExpenses * 100).toStringAsFixed(1);
      return '${e.key}: ₱${e.value.toStringAsFixed(2)} ($percentage%)';
    }).join(', ');

    final prompt = '''
Analyze car wash expense patterns:
- Total Expenses: ₱${totalExpenses.toStringAsFixed(2)}
- Breakdown: $expensesStr

Provide 2-3 sentences with:
1. Expense distribution insights
2. Cost-saving opportunities
3. Budget optimization suggestions

Be specific and actionable for a car wash business.
''';

    return _generateText(prompt);
  }

  /// Helper method to generate text from prompt via Cloud Function
  static Future<String> _generateText(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse(_cloudFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['summary'] ?? 'No summary generated';
      } else {
        throw Exception('Failed to generate summary: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to generate AI summary: $e');
    }
  }

  /// Helper to format time labels
  static String _formatTimeLabel(dynamic key, String timeUnit) {
    switch (timeUnit) {
      case 'hour':
        final hour = key as int;
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return '$displayHour:00 $period';
      case 'day_of_week':
        final days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[key as int];
      case 'day':
        return 'Day $key';
      case 'month':
        final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return months[key as int];
      case 'year':
        return key.toString();
      default:
        return key.toString();
    }
  }
}
