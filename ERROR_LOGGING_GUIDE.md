# Error Logging Guide - EC Carwash App

## 📊 Overview

Your app now has comprehensive error logging for both **Mobile (APK)** and **Web Admin**.

---

## 🔴 How to Log Errors in Code

### Import the error logger:
```dart
import 'package:ec_carwash/services/error_logger.dart';
```

### Log an error:
```dart
try {
  // Your code here
  await someRiskyOperation();
} catch (e, stackTrace) {
  await ErrorLogger.logError(
    e,
    stackTrace: stackTrace,
    context: 'Failed to load expenses',
    additionalData: {'userId': user.uid},
    fatal: false, // Set to true for critical errors
  );

  // Still show user-friendly message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to load data. Please try again.')),
  );
}
```

### Log a breadcrumb (for debugging):
```dart
await ErrorLogger.log('User clicked print button');
```

### Set user context (call after login):
```dart
await ErrorLogger.setUserIdentifier(user.uid, email: user.email);
```

---

## 📱 **Mobile App (APK) - View Logs**

### Firebase Crashlytics Dashboard
1. Go to: https://console.firebase.google.com/project/ec-carwash-app/crashlytics
2. You'll see:
   - **Crash-free users** percentage
   - **Total crashes** count
   - **List of errors** with frequency
   - **Device info** (Android version, device model)
   - **User impact** (how many users affected)

### What gets logged automatically:
- ✅ All uncaught exceptions
- ✅ Fatal errors
- ✅ Stack traces
- ✅ Device information
- ✅ User ID and email
- ✅ App version

### Example:
```
Error: Failed to load bookings
Stack: at BookingHistory.loadData (booking_history.dart:245)
Device: Samsung Galaxy A52, Android 13
User: john@example.com
Count: 5 users affected
```

---

## 🌐 **Web Admin - View Logs**

### Method 1: Firestore ErrorLogs Collection
1. Go to: https://console.firebase.google.com/project/ec-carwash-app/firestore
2. Open collection: `ErrorLogs`
3. Each document shows:
   - `error`: Error message
   - `stackTrace`: Code location
   - `context`: What the user was doing
   - `userId`: Who experienced it
   - `userEmail`: User's email
   - `timestamp`: When it happened
   - `platform`: "web"
   - `fatal`: true/false
   - `additionalData`: Custom data

### Method 2: Firebase Analytics
1. Go to: https://console.firebase.google.com/project/ec-carwash-app/analytics/app/web:NzFmMTdjZWEtMzVhMS00ZGI2LTg3ZDAtN2U3ODliYjMwYjk1/streamview
2. Click "Events"
3. Look for:
   - `error_caught` - Non-fatal errors
   - `error_fatal` - Critical errors

### Method 3: Browser Console (Real-time)
1. Admin opens browser (Chrome/Firefox)
2. Press **F12** or Right-click → **Inspect**
3. Go to **Console** tab
4. Errors appear in red with 🔴 emoji

---

## 🎯 **Common Use Cases**

### 1. Print Expenses Failed
```dart
Future<void> _printExpenseHistory() async {
  try {
    // ... print logic
  } catch (e, stackTrace) {
    await ErrorLogger.logError(
      e,
      stackTrace: stackTrace,
      context: 'Print expenses failed',
      additionalData: {
        'category': _selectedCategory,
        'filter': _selectedFilter,
        'count': _expenses.length,
      },
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error printing: $e')),
    );
  }
}
```

### 2. Booking Creation Failed (Mobile)
```dart
try {
  await BookingManager.createBooking(booking);
} catch (e, stackTrace) {
  await ErrorLogger.logError(
    e,
    stackTrace: stackTrace,
    context: 'Failed to create booking',
    additionalData: {
      'vehicleType': selectedVehicle,
      'services': selectedServices,
    },
    fatal: true, // Critical - user can't book
  );
}
```

### 3. Payment Processing Error
```dart
try {
  await processPayment(amount);
} catch (e, stackTrace) {
  await ErrorLogger.logError(
    e,
    stackTrace: stackTrace,
    context: 'Payment processing failed',
    additionalData: {'amount': amount},
    fatal: true,
  );
}
```

---

## 🔧 **Testing the Error Logger**

### Test on Mobile:
```dart
// Add this button temporarily
ElevatedButton(
  onPressed: () async {
    await ErrorLogger.logError(
      Exception('Test error from mobile'),
      context: 'Testing Crashlytics',
      fatal: false,
    );
  },
  child: Text('Test Error Log'),
)
```

Then check Firebase Crashlytics dashboard after 1-2 minutes.

### Test on Web:
```dart
// Add this button temporarily
ElevatedButton(
  onPressed: () async {
    await ErrorLogger.logError(
      Exception('Test error from web admin'),
      context: 'Testing web error logging',
      fatal: false,
    );
  },
  child: Text('Test Web Error'),
)
```

Then check Firestore → ErrorLogs collection immediately.

---

## 📈 **Best Practices**

### ✅ DO:
- Log errors in `try-catch` blocks
- Provide meaningful `context` (what user was trying to do)
- Set `fatal: true` for critical errors that prevent core functionality
- Include relevant `additionalData` (userId, amounts, IDs)
- Set user identifier after login

### ❌ DON'T:
- Log sensitive data (passwords, credit cards)
- Log expected validation errors (user enters wrong email format)
- Log every single non-critical event
- Forget to show user-friendly messages to users

---

## 🚨 **Critical Errors to Monitor**

Monitor these regularly:

1. **Booking Creation Failures** - Users can't book services
2. **Payment Errors** - Money transactions failing
3. **Login/Auth Failures** - Users locked out
4. **Data Load Failures** - Admin can't see bookings/transactions
5. **Notification Send Failures** - Users miss important updates

---

## 📞 **Support**

### Firebase Crashlytics Docs:
https://firebase.google.com/docs/crashlytics

### Firebase Analytics Docs:
https://firebase.google.com/docs/analytics

### Check Logs:
- Mobile: https://console.firebase.google.com/project/ec-carwash-app/crashlytics
- Web: https://console.firebase.google.com/project/ec-carwash-app/firestore/data/ErrorLogs

---

## ⚙️ **Cloud Function Endpoint** (Backup)

If Firestore direct logging fails on web, the error logger automatically falls back to:

```
POST https://us-central1-ec-carwash-app.cloudfunctions.net/logWebError
```

Payload:
```json
{
  "error": "Error message",
  "stackTrace": "Stack trace string",
  "context": "What user was doing",
  "userId": "user123",
  "userEmail": "user@example.com",
  "fatal": false,
  "additionalData": {}
}
```

This is already handled automatically by `ErrorLogger.logError()`.
