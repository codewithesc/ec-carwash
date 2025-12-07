import 'package:intl/intl.dart';

/// Utility class for formatting currency values with proper thousand separators
class CurrencyFormatter {
  // NumberFormat for Philippine Peso with comma separators
  static final NumberFormat _pesoFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  static final NumberFormat _pesoFormatNoSymbol = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '',
    decimalDigits: 2,
  );

  /// Format a number as Philippine Peso with symbol (₱)
  /// Example: 4656390.50 → ₱4,656,390.50
  static String format(double amount) {
    return _pesoFormat.format(amount);
  }

  /// Format a number as Philippine Peso without symbol
  /// Example: 4656390.50 → 4,656,390.50
  static String formatNoSymbol(double amount) {
    return _pesoFormatNoSymbol.format(amount).trim();
  }

  /// Format a number with custom decimal places
  /// Example: formatCustom(4656390.5, 0) → ₱4,656,391
  static String formatCustom(double amount, int decimalPlaces) {
    final formatter = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: decimalPlaces,
    );
    return formatter.format(amount);
  }
}
