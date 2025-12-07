# EC Carwash Management System

A comprehensive carwash management application built with Flutter and Firebase, featuring separate interfaces for customers and administrators.

## Overview

EC Carwash is a full-stack mobile and web application designed to streamline carwash operations:
- **Customer App (Mobile)**: Book services, view history, receive notifications
- **Admin Panel (Web)**: Manage bookings, staff, inventory, analytics, and more
- **Real-time Sync**: All data synchronized across platforms via Firebase

## Features

### Customer Features
- Google Sign-In authentication
- Browse and book carwash services
- Real-time booking status updates
- Push notifications for booking changes
- Booking history and receipts
- Account management

### Admin Features
- Point of Sale (POS) system
- Booking management and scheduling
- Staff management with commission tracking
- Inventory management
- Expense tracking
- Payroll system
- Analytics and reporting
- Service management
- Transaction history

## Tech Stack

- **Frontend**: Flutter (Mobile & Web)
- **Backend**: Firebase
  - Firestore (Database)
  - Authentication (Google Sign-In)
  - Cloud Functions (Notifications)
  - Cloud Messaging (Push Notifications)
  - Analytics
  - Crashlytics (Error logging)
- **State Management**: Provider pattern
- **UI**: Material Design with custom theming

## Project Structure

```
ec-carwash/
├── ec_carwash/              # Flutter application
│   ├── lib/
│   │   ├── config/          # Configuration files
│   │   ├── data_models/     # Data models
│   │   ├── screens/         # UI screens
│   │   │   ├── Admin/       # Admin panel screens
│   │   │   └── Customer/    # Customer app screens
│   │   ├── services/        # Business logic & services
│   │   └── utils/           # Utility functions
│   ├── android/             # Android-specific code
│   ├── ios/                 # iOS-specific code
│   └── web/                 # Web-specific code
├── functions/               # Firebase Cloud Functions
│   └── src/
│       └── index.ts         # Cloud Functions code
├── docs/                    # Documentation
└── firebase.json            # Firebase configuration
```

## Getting Started

### Prerequisites

- Flutter SDK (3.0+)
- Dart SDK (3.0+)
- Firebase CLI
- Node.js 18+ (for Cloud Functions)
- Android Studio / Xcode (for mobile development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/codewithesc/ec-carwash.git
   cd ec-carwash
   ```

2. **Install Flutter dependencies**
   ```bash
   cd ec_carwash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Add Android and iOS apps to your Firebase project
   - Download and place `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
   - Enable Authentication, Firestore, Cloud Functions, and Cloud Messaging

4. **Set up Cloud Functions**
   ```bash
   cd functions
   npm install
   npm run build
   firebase deploy --only functions
   ```

5. **Run the application**
   ```bash
   # For Android/iOS (Customer App)
   flutter run

   # For Web (Admin Panel)
   flutter run -d chrome
   ```

## Configuration

### Admin Access
Edit `ec_carwash/lib/config/permissions_config.dart` to configure admin and staff emails:

```dart
class PermissionsConfig {
  static const List<String> superAdminEmails = ['admin@example.com'];
  static const List<String> adminEmails = ['manager@example.com'];
  static const List<String> staffEmails = ['staff@example.com'];
}
```

### Firebase Setup
Ensure the following Firebase services are enabled:
- Authentication (Google Sign-In provider)
- Firestore Database
- Cloud Functions
- Cloud Messaging
- Analytics
- Crashlytics (for mobile)

## Platform Support

- **Android**: ✓ Fully supported
- **iOS**: ✓ Fully supported
- **Web**: ✓ Admin panel only
- **Desktop**: Not supported

## Documentation

Detailed documentation is available in the `docs/` folder:

- [Cloud Functions Setup](docs/CLOUD_FUNCTIONS_README.md)
- [Deployment Guide](docs/DEPLOYMENT_DOCUMENTATION.md)
- [Data Model Documentation](docs/UNIFIED_DATA_MODEL.md)
- [Push Notifications Setup](docs/PUSH_NOTIFICATIONS_COMPLETE.md)
- [Analytics Implementation](docs/IMPLEMENTATION_SUMMARY.md)
- [Bug Reports & Fixes](docs/BUG_REPORT_AND_FIXES.md)

## Building for Production

### Android
```bash
flutter build apk --release
# or for app bundle
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Web
```bash
flutter build web --release
```

## Security

- All sensitive configuration is stored in Firebase
- Admin access controlled via email whitelist
- Firebase Security Rules enforce data access policies
- API keys are configured per platform in Firebase settings

## Contributing

This is a private project. For internal development guidelines, contact the project maintainer.

## License

Proprietary - All rights reserved

## Support

For issues or questions, please contact the development team.

## Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend infrastructure
- Google Fonts for typography
- All open-source packages used in this project
