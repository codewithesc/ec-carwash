import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ec_carwash/data_models/expense_data.dart';
import 'package:intl/intl.dart';
import 'package:ec_carwash/services/gemini_analytics_service.dart';
import 'package:ec_carwash/utils/currency_formatter.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedFilter = 'today'; // today, weekly, monthly, yearly, custom
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;

  // Peak Operating Time Data (bookings per time unit - hour/day/month depending on filter)
  Map<dynamic, int> _peakTimeData = {};

  // Top Services Data (now counts transactions instead of revenue)
  Map<String, double> _serviceRevenue = {};

  // Expenses Pattern Data
  Map<String, double> _expensesByCategory = {};

  // Sales Report Data
  double _totalRevenue = 0.0;
  int _totalTransactions = 0;
  double _totalExpenses = 0.0;
  double _profitMargin = 0.0;
  bool _showSalesReport = false;

  // AI Summary State
  String? _salesSummary;
  String? _peakTimeSummary;
  String? _servicesSummary;
  String? _expensesSummary;
  bool _isGeneratingSalesSummary = false;
  bool _isGeneratingPeakSummary = false;
  bool _isGeneratingServicesSummary = false;
  bool _isGeneratingExpensesSummary = false;
  String? _geminiError;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime startDate;
      DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

      // Calculate date range based on filter
      switch (_selectedFilter) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'weekly':
          startDate = now.subtract(Duration(days: now.weekday - 1));
          startDate = DateTime(startDate.year, startDate.month, startDate.day);
          endDate = startDate.add(const Duration(days: 7));
          break;
        case 'monthly':
          startDate = DateTime(now.year, now.month, 1);
          endDate = DateTime(now.year, now.month + 1, 1).subtract(const Duration(seconds: 1));
          break;
        case 'yearly':
          startDate = DateTime(now.year, 1, 1);
          endDate = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
        case 'custom':
          if (_startDate != null && _endDate != null) {
            startDate = _startDate!;
            endDate = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
          } else {
            startDate = DateTime(now.year, now.month, now.day);
          }
          break;
        default:
          startDate = DateTime(now.year, now.month, now.day);
      }

      // Load completed transactions (includes CSV imports, POS transactions, and completed bookings)
      final transactionsSnapshot = await FirebaseFirestore.instance
          .collection('Transactions')
          .where('status', isEqualTo: 'completed')
          .get();

      // Process data with date filtering
      Map<dynamic, int> peakTimeCount = {};
      Map<String, double> serviceRev = {};
      double totalRev = 0.0;
      int txnCount = 0;

      // Process transactions only (no separate booking processing to avoid duplicates)
      for (final doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final transactionAt = (data['transactionAt'] as Timestamp?)?.toDate();

        // Filter by date range
        if (transactionAt == null ||
            transactionAt.isBefore(startDate) ||
            transactionAt.isAfter(endDate)) {
          continue;
        }

        txnCount++;
        final total = (data['total'] as num?)?.toDouble() ?? 0.0;
        final services = data['services'] as List?;

        totalRev += total;

        // Peak time analysis
        dynamic timeKey;
        switch (_selectedFilter) {
          case 'today':
            timeKey = transactionAt.hour;
            break;
          case 'weekly':
            timeKey = transactionAt.weekday; // Fixed: use weekday instead of day
            break;
          case 'monthly':
            timeKey = transactionAt.day;
            break;
          case 'yearly':
            timeKey = transactionAt.month;
            break;
          case 'custom':
            final daysDiff = endDate.difference(startDate).inDays;

            if (daysDiff <= 1) {
              // Single day: use hours
              timeKey = transactionAt.hour;
            } else if (daysDiff <= 90) {
              // Up to 90 days: use day offset from start date (0, 1, 2, ... n)
              timeKey = transactionAt.difference(DateTime(startDate.year, startDate.month, startDate.day)).inDays;
            } else if (daysDiff <= 366) {
              // 3 months to 1 year: use months
              timeKey = transactionAt.month;
            } else {
              // Over 1 year: use years
              timeKey = transactionAt.year;
            }
            break;
          default:
            timeKey = transactionAt.hour;
        }

        peakTimeCount[timeKey] = (peakTimeCount[timeKey] ?? 0) + 1;

        // Top services analysis (count transactions, not revenue)
        if (services != null) {
          for (final service in services) {
            final serviceCode = service['serviceCode'] ?? 'Unknown';
            // Count each service occurrence (transaction count)
            serviceRev[serviceCode] = (serviceRev[serviceCode] ?? 0.0) + 1.0;
          }
        }
      }

      // Load expenses for the period
      final expenses = await ExpenseManager.getExpenses(
        startDate: startDate,
        endDate: endDate,
      );

      Map<String, double> expensesByCat = {};
      double totalExp = 0.0;

      for (final expense in expenses) {
        totalExp += expense.amount;
        expensesByCat[expense.category] = (expensesByCat[expense.category] ?? 0.0) + expense.amount;
      }

      // Calculate profit margin
      final profit = totalRev - totalExp;
      final profitMargin = totalRev > 0 ? (profit / totalRev) * 100 : 0.0;

      if (mounted) {
        setState(() {
          _peakTimeData = peakTimeCount;
          _serviceRevenue = serviceRev;
          _expensesByCategory = expensesByCat;
          _totalRevenue = totalRev;
          _totalTransactions = txnCount;
          _totalExpenses = totalExp;
          _profitMargin = profitMargin;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading analytics: $e')),
        );
      }
    }
  }

  /// Generate AI summary for sales report
  Future<void> _generateSalesSummary() async {
    if (_isGeneratingSalesSummary) return;

    setState(() {
      _isGeneratingSalesSummary = true;
      _geminiError = null;
    });

    try {
      final summary = await GeminiAnalyticsService.generateSalesSummary(
        revenue: _totalRevenue,
        transactions: _totalTransactions,
        expenses: _totalExpenses,
        profitMargin: _profitMargin,
        topServices: _serviceRevenue,
        period: _getPeriodLabel(),
      );

      if (mounted) {
        setState(() {
          _salesSummary = summary;
          _isGeneratingSalesSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geminiError = e.toString();
          _isGeneratingSalesSummary = false;
        });
      }
    }
  }

  /// Generate AI summary for peak times
  Future<void> _generatePeakTimeSummary() async {
    if (_isGeneratingPeakSummary) return;

    setState(() {
      _isGeneratingPeakSummary = true;
      _geminiError = null;
    });

    try {
      final summary = await GeminiAnalyticsService.generatePeakTimeSummary(
        peakData: _peakTimeData,
        period: _getPeriodLabel(),
        timeUnit: _getTimeUnit(),
      );

      if (mounted) {
        setState(() {
          _peakTimeSummary = summary;
          _isGeneratingPeakSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geminiError = e.toString();
          _isGeneratingPeakSummary = false;
        });
      }
    }
  }

  /// Generate AI summary for services
  Future<void> _generateServicesSummary() async {
    if (_isGeneratingServicesSummary) return;

    setState(() {
      _isGeneratingServicesSummary = true;
      _geminiError = null;
    });

    try {
      final summary = await GeminiAnalyticsService.generateServicesSummary(
        serviceRevenue: _serviceRevenue,
      );

      if (mounted) {
        setState(() {
          _servicesSummary = summary;
          _isGeneratingServicesSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geminiError = e.toString();
          _isGeneratingServicesSummary = false;
        });
      }
    }
  }

  /// Generate AI summary for expenses
  Future<void> _generateExpensesSummary() async {
    if (_isGeneratingExpensesSummary) return;

    setState(() {
      _isGeneratingExpensesSummary = true;
      _geminiError = null;
    });

    try {
      final summary = await GeminiAnalyticsService.generateExpensesSummary(
        expensesByCategory: _expensesByCategory,
        totalExpenses: _totalExpenses,
      );

      if (mounted) {
        setState(() {
          _expensesSummary = summary;
          _isGeneratingExpensesSummary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geminiError = e.toString();
          _isGeneratingExpensesSummary = false;
        });
      }
    }
  }

  /// Get period label for AI context
  String _getPeriodLabel() {
    switch (_selectedFilter) {
      case 'today':
        return 'today';
      case 'weekly':
        return 'this week';
      case 'monthly':
        return 'this month';
      case 'yearly':
        return 'this year';
      case 'custom':
        if (_startDate != null && _endDate != null) {
          final formatter = DateFormat('MMM d, yyyy');
          return '${formatter.format(_startDate!)} to ${formatter.format(_endDate!)}';
        }
        return 'custom period';
      default:
        return 'today';
    }
  }

  /// Get time unit for peak times
  String _getTimeUnit() {
    switch (_selectedFilter) {
      case 'today':
        return 'hour';
      case 'weekly':
        return 'day_of_week';
      case 'monthly':
        return 'day';
      case 'yearly':
        return 'month';
      case 'custom':
        if (_startDate == null || _endDate == null) return 'hour';
        final daysDiff = _endDate!.difference(_startDate!).inDays;
        if (daysDiff <= 1) return 'hour';
        if (daysDiff <= 31) return 'day';
        if (daysDiff <= 366) return 'month';
        return 'year';
      default:
        return 'hour';
    }
  }

  /// Build AI summary section widget
  Widget _buildAISummarySection({
    required String? summary,
    required bool isGenerating,
    required VoidCallback onGenerate,
    required String title,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              if (!isGenerating)
                IconButton(
                  icon: Icon(
                    summary == null ? Icons.lightbulb : Icons.refresh,
                    color: Colors.blue.shade700,
                  ),
                  onPressed: onGenerate,
                  tooltip: summary == null ? 'Generate AI Insights' : 'Refresh Insights',
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isGenerating)
            Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: Colors.blue.shade700),
                  const SizedBox(height: 8),
                  Text(
                    'Generating insights...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            )
          else if (_geminiError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Error: ${_geminiError ?? "Unknown error"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (summary == null)
            Text(
              'Click the lightbulb icon to generate AI-powered insights for this report.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade700.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Text(
              summary,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    try {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // All charts stacked vertically
            _buildPeakOperatingTimeChart(),
            const SizedBox(height: 20),
            _buildTopServicesChart(),
            const SizedBox(height: 20),
            _buildExpensesPatternChart(),
            const SizedBox(height: 20),
            // Sales Report at bottom (expandable button)
            _buildSalesReportButton(),
          ],
        ),
      );
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading analytics',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildFilterChip('Today', 'today'),
          const SizedBox(width: 8),
          _buildFilterChip('Weekly', 'weekly'),
          const SizedBox(width: 8),
          _buildFilterChip('Monthly', 'monthly'),
          const SizedBox(width: 8),
          _buildFilterChip('Yearly', 'yearly'),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _showCustomRangeDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              backgroundColor: _selectedFilter == 'custom' ? Colors.yellow.shade700 : Colors.yellow.shade50,
              side: BorderSide(color: Colors.black87, width: _selectedFilter == 'custom' ? 1.5 : 1),
            ),
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _selectedFilter == 'custom' && _startDate != null && _endDate != null
                  ? 'Custom Range'
                  : 'Custom',
              style: TextStyle(
                fontWeight: _selectedFilter == 'custom' ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.black87 : Colors.black.withValues(alpha: 0.7),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
        _loadAnalyticsData();
      },
      selectedColor: Colors.yellow.shade700,
      backgroundColor: Colors.grey.shade200,
      side: BorderSide(
        color: isSelected ? Colors.black87 : Colors.transparent,
        width: 1.5,
      ),
    );
  }

  Widget _buildSalesReportButton() {
    return Card(
      color: Colors.yellow.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.yellow.shade700,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black87, width: 1),
          ),
          child: const Icon(Icons.analytics, color: Colors.black87, size: 20),
        ),
        title: const Text(
          'Sales Report',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          'Click to view detailed report',
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        initiallyExpanded: _showSalesReport,
        onExpansionChanged: (expanded) {
          setState(() => _showSalesReport = expanded);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _buildSalesReportContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesReportContent() {
    final profit = _totalRevenue - _totalExpenses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildSalesMetric('Total Revenue', CurrencyFormatter.format(_totalRevenue))),
            const SizedBox(width: 16),
            Expanded(child: _buildSalesMetric('Transactions', '$_totalTransactions')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSalesMetric('Total Expenses', CurrencyFormatter.format(_totalExpenses))),
            const SizedBox(width: 16),
            Expanded(child: _buildSalesMetric('Profit', CurrencyFormatter.format(profit))),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.yellow.shade700,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black87, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Profit Margin',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${_profitMargin.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        if (_serviceRevenue.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text(
            'Top Revenue Packages',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          ..._getTopServices(3).map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(entry.value),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          )),
        ],
        const SizedBox(height: 20),
        _buildAISummarySection(
          summary: _salesSummary,
          isGenerating: _isGeneratingSalesSummary,
          onGenerate: _generateSalesSummary,
          title: 'AI Insights',
        ),
      ],
    );
  }

  Widget _buildSalesMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black87, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, double>> _getTopServices(int limit) {
    final entries = _serviceRevenue.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  Widget _buildPeakOperatingTimeChart() {
    // Determine title and labels based on filter
    String chartTitle;
    String chartSubtitle;
    Map<int, int> completeData = {};

    switch (_selectedFilter) {
      case 'today':
        chartTitle = 'Peak Operating Hours';
        chartSubtitle = 'Busiest times of the day';
        // Hours from 8 AM to 6 PM
        for (int hour = 8; hour <= 18; hour++) {
          completeData[hour] = _peakTimeData[hour] ?? 0;
        }
        break;
      case 'weekly':
        chartTitle = 'Peak Operating Days';
        chartSubtitle = 'Busiest days of the week';
        // Days 1-7 (Mon-Sun)
        for (int day = 1; day <= 7; day++) {
          completeData[day] = _peakTimeData[day] ?? 0;
        }
        break;
      case 'monthly':
        chartTitle = 'Peak Operating Days';
        chartSubtitle = 'Busiest days of the month';
        // Days 1-31
        for (int day = 1; day <= 31; day++) {
          completeData[day] = _peakTimeData[day] ?? 0;
        }
        break;
      case 'yearly':
        chartTitle = 'Peak Operating Months';
        chartSubtitle = 'Busiest months of the year';
        // Months 1-12 - filter to ensure only month data is used
        for (int month = 1; month <= 12; month++) {
          // Only include if the key is actually a month (1-12)
          if (_peakTimeData.containsKey(month)) {
            completeData[month] = _peakTimeData[month] ?? 0;
          } else {
            completeData[month] = 0;
          }
        }
        break;
      case 'custom':
        // Determine based on date range
        if (_startDate == null || _endDate == null) {
          chartTitle = 'Peak Times';
          chartSubtitle = 'No data available';
        } else {
          final daysDiff = _endDate!.difference(_startDate!).inDays;

          if (daysDiff <= 1) {
            // Single day: show hours
            chartTitle = 'Peak Operating Hours';
            final formatter = DateFormat('MMM d, yyyy');
            chartSubtitle = formatter.format(_startDate!);
            for (int hour = 8; hour <= 18; hour++) {
              completeData[hour] = _peakTimeData[hour] ?? 0;
            }
          } else if (daysDiff <= 90) {
            // Up to 90 days (3 months): show day offset (continuous days across months)
            chartTitle = 'Peak Operating Days';
            final formatter = DateFormat('MMM d, yyyy');
            chartSubtitle = '${formatter.format(_startDate!)} to ${formatter.format(_endDate!)}';
            for (int dayOffset = 0; dayOffset <= daysDiff; dayOffset++) {
              completeData[dayOffset] = _peakTimeData[dayOffset] ?? 0;
            }
          } else if (daysDiff <= 366) {
            // 3 months to 1 year: show months
            chartTitle = 'Peak Operating Months';
            final formatter = DateFormat('MMM yyyy');
            chartSubtitle = '${formatter.format(_startDate!)} to ${formatter.format(_endDate!)}';
            for (int month = 1; month <= 12; month++) {
              completeData[month] = _peakTimeData[month] ?? 0;
            }
          } else {
            chartTitle = 'Peak Operating Years';
            chartSubtitle = '${_startDate!.year} to ${_endDate!.year}';
            // Get the year range
            final startYear = _startDate!.year;
            final endYear = _endDate!.year;
            for (int year = startYear; year <= endYear; year++) {
              completeData[year] = _peakTimeData[year] ?? 0;
            }
          }
        }
        break;
      default:
        chartTitle = 'Peak Operating Hours';
        chartSubtitle = 'Busiest times of the day';
        for (int hour = 8; hour <= 18; hour++) {
          completeData[hour] = _peakTimeData[hour] ?? 0;
        }
    }

    final maxBookings = completeData.values.isEmpty
        ? 1
        : completeData.values.reduce((a, b) => a > b ? a : b);

    // If no bookings, show empty state
    if (maxBookings == 0 || completeData.isEmpty) {
      return Card(
        color: Colors.yellow.shade50,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black87, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, color: Colors.black87, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    chartTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'No booking data available for the selected period',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: Colors.yellow.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, color: Colors.black87, size: 20),
                const SizedBox(width: 8),
                Text(
                  chartTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              chartSubtitle,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxBookings * 1.2).toDouble(),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => Colors.black87,
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.all(8),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String label = _getTooltipLabel(group.x.toInt(), _selectedFilter);
                        return BarTooltipItem(
                          '$label\n${rod.toY.toInt()} bookings',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return _getBottomTitle(value.toInt(), _selectedFilter);
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        interval: maxBookings > 10 ? null : (maxBookings > 5 ? 2 : 1),
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value > maxBookings) return const SizedBox.shrink();
                          return Text(
                            '${value.toInt()}',
                            style: const TextStyle(fontSize: 10, color: Colors.black87),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxBookings * 1.2) / 5,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: completeData.entries.map((entry) {
                    return BarChartGroupData(
                      x: entry.key,
                      barRods: [
                        BarChartRodData(
                          toY: entry.value.toDouble(),
                          color: Colors.yellow.shade700,
                          width: 16,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          borderSide: const BorderSide(color: Colors.black87, width: 1),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildAISummarySection(
              summary: _peakTimeSummary,
              isGenerating: _isGeneratingPeakSummary,
              onGenerate: _generatePeakTimeSummary,
              title: 'AI Insights',
            ),
          ],
        ),
      ),
    );
  }

  Widget _getBottomTitle(int value, String filter) {
    String label;

    // Defensive check: if value is 1-12 and we're clearly looking at month data,
    // force month labels regardless of filter state
    if (value >= 1 && value <= 12 && filter == 'yearly') {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      label = months[value - 1];
      return Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.black87),
      );
    }

    switch (filter) {
      case 'today':
        // Hours (8 AM - 6 PM)
        final period = value >= 12 ? 'PM' : 'AM';
        final displayHour = value == 0 ? 12 : (value > 12 ? value - 12 : value);
        label = '$displayHour$period';
        break;
      case 'weekly':
        // Days of week
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        label = value >= 1 && value <= 7 ? days[value - 1] : '';
        break;
      case 'monthly':
        // Days of month (show key days to avoid crowding)
        if (value == 1 || value % 5 == 0) {
          label = value.toString();
        } else {
          label = '';
        }
        break;
      case 'yearly':
        // Months
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        label = value >= 1 && value <= 12 ? months[value - 1] : '';
        break;
      case 'custom':
        // Determine based on actual date range, not value
        if (_startDate != null && _endDate != null) {
          final daysDiff = _endDate!.difference(_startDate!).inDays;

          if (daysDiff <= 1) {
            // Single day: show hours
            final period = value >= 12 ? 'PM' : 'AM';
            final displayHour = value == 0 ? 12 : (value > 12 ? value - 12 : value);
            label = '$displayHour$period';
          } else if (daysDiff <= 90) {
            // Up to 90 days: show date labels (value is day offset)
            // Show labels every 5-10 days depending on range, plus first and last
            final interval = daysDiff <= 31 ? 5 : 10;
            if (value == 0 || value == daysDiff || value % interval == 0) {
              final actualDate = _startDate!.add(Duration(days: value));
              // Show as "M/D" format for clarity across months
              label = '${actualDate.month}/${actualDate.day}';
            } else {
              label = '';
            }
          } else if (daysDiff <= 366) {
            // 3 months to 1 year: show months
            const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            label = value >= 1 && value <= 12 ? months[value - 1] : '';
          } else {
            // Over 1 year: show years
            label = value.toString();
          }
        } else {
          label = value.toString();
        }
        break;
      default:
        label = value.toString();
    }
    return Text(
      label,
      style: const TextStyle(fontSize: 10, color: Colors.black87),
    );
  }

  String _getTooltipLabel(int value, String filter) {
    switch (filter) {
      case 'today':
        // Hours (full format)
        final period = value >= 12 ? 'PM' : 'AM';
        final displayHour = value == 0 ? 12 : (value > 12 ? value - 12 : value);
        return '$displayHour:00 $period';
      case 'weekly':
        // Days of week (full name)
        const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return value >= 1 && value <= 7 ? days[value - 1] : 'Day $value';
      case 'monthly':
        // Days of month (with ordinal)
        return 'Day $value';
      case 'yearly':
        // Months (full name)
        const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        return value >= 1 && value <= 12 ? months[value - 1] : 'Month $value';
      case 'custom':
        // Determine based on actual date range
        if (_startDate != null && _endDate != null) {
          final daysDiff = _endDate!.difference(_startDate!).inDays;
          if (daysDiff <= 1) {
            // Hours
            final period = value >= 12 ? 'PM' : 'AM';
            final displayHour = value == 0 ? 12 : (value > 12 ? value - 12 : value);
            return '$displayHour:00 $period';
          } else if (daysDiff <= 90) {
            // Day offset - show actual date (up to 90 days)
            final actualDate = _startDate!.add(Duration(days: value));
            return DateFormat('MMM d, yyyy').format(actualDate);
          } else if (daysDiff <= 366) {
            // Months - show full month name with year
            const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
            return value >= 1 && value <= 12 ? months[value - 1] : 'Month $value';
          } else {
            // Years
            return value.toString();
          }
        }
        return 'Day $value';
      default:
        return value.toString();
    }
  }

  Widget _buildTopServicesChart() {
    if (_serviceRevenue.isEmpty) {
      return _buildEmptyChart('Top Service Packages', 'No data available');
    }

    final topServices = _getTopServices(5);
    final total = topServices.fold(0.0, (acc, entry) => acc + entry.value);

    if (total == 0 || topServices.isEmpty) {
      return _buildEmptyChart('Top Service Packages', 'No data available');
    }

    return Card(
      color: Colors.yellow.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star, color: Colors.black87, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Top Service Packages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sections: topServices.asMap().entries.where((entry) => entry.value.value > 0).map((entry) {
                          final index = entry.key;
                          final data = entry.value;
                          final percentage = (data.value / total) * 100;
                          final colors = [
                            Colors.yellow.shade700,
                            Colors.yellow.shade600,
                            Colors.yellow.shade500,
                            Colors.yellow.shade400,
                            Colors.yellow.shade300,
                          ];
                          return PieChartSectionData(
                            color: colors[index % colors.length],
                            value: data.value,
                            title: '${percentage.toStringAsFixed(0)}%',
                            radius: 100,
                            titleStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            borderSide: const BorderSide(color: Colors.black87, width: 1),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: topServices.asMap().entries.map((entry) {
                        final index = entry.key;
                        final data = entry.value;
                        final colors = [
                          Colors.yellow.shade700,
                          Colors.yellow.shade600,
                          Colors.yellow.shade500,
                          Colors.yellow.shade400,
                          Colors.yellow.shade300,
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: colors[index % colors.length],
                                  border: Border.all(color: Colors.black87, width: 1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data.key,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${data.value.toInt()} transactions',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black.withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildAISummarySection(
              summary: _servicesSummary,
              isGenerating: _isGeneratingServicesSummary,
              onGenerate: _generateServicesSummary,
              title: 'AI Insights',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesPatternChart() {
    if (_expensesByCategory.isEmpty) {
      return _buildEmptyChart('Expenses Pattern', 'No expenses data available');
    }

    final total = _expensesByCategory.values.fold(0.0, (acc, value) => acc + value);

    if (total == 0) {
      return _buildEmptyChart('Expenses Pattern', 'No expenses data available');
    }

    return Card(
      color: Colors.yellow.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.money_off, color: Colors.black87, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Expenses Pattern',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total Expenses: ${CurrencyFormatter.format(total)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            ..._expensesByCategory.entries.map((entry) {
              final percentage = (entry.value / total) * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${CurrencyFormatter.format(entry.value)} (${percentage.toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        minHeight: 12,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow.shade700),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 20),
            _buildAISummarySection(
              summary: _expensesSummary,
              isGenerating: _isGeneratingExpensesSummary,
              onGenerate: _generateExpensesSummary,
              title: 'AI Insights',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyChart(String title, String message) {
    return Card(
      color: Colors.yellow.shade50,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black87, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Icon(Icons.bar_chart, size: 48, color: Colors.black.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomRangeDialog() {
    showDialog(
      context: context,
      builder: (context) => _CustomRangeDialog(
        startDate: _startDate,
        endDate: _endDate,
        onApply: (start, end) {
          setState(() {
            _startDate = start;
            _endDate = end;
            _selectedFilter = 'custom';
          });
          _loadAnalyticsData();
        },
      ),
    );
  }
}

// Custom Range Dialog Widget
class _CustomRangeDialog extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final Function(DateTime start, DateTime end) onApply;

  const _CustomRangeDialog({
    this.startDate,
    this.endDate,
    required this.onApply,
  });

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  int? _startMonth;
  int? _startYear;
  int? _endMonth;
  int? _endYear;

  @override
  void initState() {
    super.initState();
    if (widget.startDate != null) {
      _startMonth = widget.startDate!.month;
      _startYear = widget.startDate!.year;
    }
    if (widget.endDate != null) {
      _endMonth = widget.endDate!.month;
      _endYear = widget.endDate!.year;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _startMonth,
                    items: List.generate(12, (index) {
                      final month = index + 1;
                      return DropdownMenuItem(
                        value: month,
                        child: Text(DateFormat('MMMM').format(DateTime(2000, month))),
                      );
                    }),
                    onChanged: (value) => setState(() => _startMonth = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _startYear,
                    items: List.generate(5, (index) {
                      final year = DateTime.now().year - index;
                      return DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      );
                    }),
                    onChanged: (value) => setState(() => _startYear = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('End Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _endMonth,
                    items: List.generate(12, (index) {
                      final month = index + 1;
                      return DropdownMenuItem(
                        value: month,
                        child: Text(DateFormat('MMMM').format(DateTime(2000, month))),
                      );
                    }),
                    onChanged: (value) => setState(() => _endMonth = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _endYear,
                    items: List.generate(5, (index) {
                      final year = DateTime.now().year - index;
                      return DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      );
                    }),
                    onChanged: (value) => setState(() => _endYear = value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_startMonth == null || _startYear == null || _endMonth == null || _endYear == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select both start and end dates')),
              );
              return;
            }

            final startDate = DateTime(_startYear!, _startMonth!, 1);
            final endDate = DateTime(_endYear!, _endMonth! + 1, 1).subtract(const Duration(seconds: 1));

            if (endDate.isBefore(startDate)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('End date must be after start date')),
              );
              return;
            }

            Navigator.pop(context);
            widget.onApply(startDate, endDate);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellow.shade700,
            foregroundColor: Colors.black87,
          ),
          child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
