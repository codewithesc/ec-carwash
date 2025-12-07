import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralized error logging service for both mobile and web
class ErrorLogger {
  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Log an error to appropriate service based on platform
  /// - Mobile: Sends to Firebase Crashlytics
  /// - Web: Sends to Firestore ErrorLogs collection and Analytics
  static Future<void> logError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? additionalData,
    bool fatal = false,
  }) async {
    try {
      // Get current user for context
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'anonymous';
      final userEmail = user?.email ?? 'unknown';

      if (kIsWeb) {
        // Web: Log to Firestore and Analytics
        await _logToFirestore(
          error: error,
          stackTrace: stackTrace,
          context: context,
          userId: userId,
          userEmail: userEmail,
          additionalData: additionalData,
          fatal: fatal,
        );

        await _logToAnalytics(
          error: error,
          context: context,
          fatal: fatal,
        );
      } else {
        // Mobile: Log to Crashlytics
        await FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: context,
          fatal: fatal,
          information: [
            if (additionalData != null)
              ...additionalData.entries.map((e) => '${e.key}: ${e.value}'),
            'userId: $userId',
            'userEmail: $userEmail',
          ],
        );
      }

      // Console logging for debug mode
      if (kDebugMode) {
        print('ERROR LOGGED: ${context ?? "Unknown context"}');
        print('Error: $error');
        if (stackTrace != null) {
          print('Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
        }
      }
    } catch (e) {
      // If logging fails, print to console
      if (kDebugMode) {
        print('Failed to log error: $e');
      }
    }
  }

  /// Log to Firestore (for web platform)
  static Future<void> _logToFirestore({
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
    required String userId,
    required String userEmail,
    Map<String, dynamic>? additionalData,
    required bool fatal,
  }) async {
    try {
      await _firestore.collection('ErrorLogs').add({
        'error': error.toString(),
        'stackTrace': stackTrace?.toString().split('\n').take(10).join('\n'),
        'context': context,
        'userId': userId,
        'userEmail': userEmail,
        'platform': 'web',
        'fatal': fatal,
        'additionalData': additionalData,
        'timestamp': FieldValue.serverTimestamp(),
        'userAgent': kIsWeb ? '' : 'mobile', // Can be enhanced with actual user agent
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log to Firestore: $e');
      }
    }
  }

  /// Log to Analytics (for web platform)
  static Future<void> _logToAnalytics({
    required dynamic error,
    String? context,
    required bool fatal,
  }) async {
    try {
      await _analytics.logEvent(
        name: fatal ? 'error_fatal' : 'error_caught',
        parameters: {
          'error_message': error.toString().substring(0, 100), // First 100 chars
          'context': context ?? 'unknown',
          'platform': 'web',
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log to Analytics: $e');
      }
    }
  }

  /// Set custom user identifier for error tracking
  static Future<void> setUserIdentifier(String userId, {String? email}) async {
    try {
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.setUserIdentifier(userId);
        if (email != null) {
          await FirebaseCrashlytics.instance.setCustomKey('email', email);
        }
      }
      await _analytics.setUserId(id: userId);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set user identifier: $e');
      }
    }
  }

  /// Set custom key-value pairs for error context
  static Future<void> setCustomKey(String key, dynamic value) async {
    try {
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.setCustomKey(key, value);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set custom key: $e');
      }
    }
  }

  /// Log a breadcrumb/event for debugging
  static Future<void> log(String message) async {
    try {
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.log(message);
      }
      if (kDebugMode) {
        print('LOG: $message');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log message: $e');
      }
    }
  }
}
