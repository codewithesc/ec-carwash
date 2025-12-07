import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Navigate to these
import 'book_service_screen.dart';
import 'customer_home.dart';
import 'account_info_screen.dart';
import 'notifications_screen.dart';
import '../../services/google_sign_in_service.dart';
import '../login_page.dart';

class BookingHistoryScreen extends StatefulWidget {
  final int initialTabIndex; // 0 = Completed, 1 = Cancelled

  const BookingHistoryScreen({super.key, this.initialTabIndex = 0});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  String _selectedMenu = "History";

  void _onSelect(String menu) {
    setState(() => _selectedMenu = menu);
    Navigator.pop(context); // close drawer first

    if (menu == "Home") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CustomerHome()),
      );
    } else if (menu == "Book") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BookServiceScreen()),
      );
    } else if (menu == "History") {
      // already here — do nothing
    } else if (menu == "Notifications") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    } else if (menu == "Account") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountInfoScreen()),
      );
    }
  }

  String _formatDateTime(dynamic rawScheduledDateTime) {
    try {
      if (rawScheduledDateTime == null) return "N/A";

      DateTime dt;
      if (rawScheduledDateTime is Timestamp) {
        dt = rawScheduledDateTime.toDate();
      } else if (rawScheduledDateTime is DateTime) {
        dt = rawScheduledDateTime;
      } else {
        dt = DateTime.tryParse(rawScheduledDateTime.toString()) ?? DateTime.now();
      }

      return DateFormat('MMM dd, yyyy – hh:mm a').format(dt);
    } catch (_) {
      return rawScheduledDateTime.toString();
    }
  }

  void _rebookTransaction(Map<String, dynamic> transactionData) {
    // Support both unified and legacy transaction shapes
    final legacyCustomer =
        (transactionData['customer'] as Map<String, dynamic>?) ?? {};
    final plateNumber = (transactionData['vehiclePlateNumber'] ??
            legacyCustomer['plateNumber'])
        ?.toString();

    // Get the services from the transaction (new: services, legacy: items)
    final rawList = (transactionData['services'] ?? transactionData['items'])
            as List<dynamic>? ??
        [];
    final services = rawList.cast<Map<String, dynamic>>();

    if (plateNumber == null || plateNumber.isEmpty || services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Unable to rebook: Missing vehicle or service information'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Prepare a minimal customer object if legacy is missing
    final customer = legacyCustomer.isNotEmpty
        ? legacyCustomer
        : {
            'plateNumber': plateNumber,
            'name': transactionData['customerName'] ?? '',
          };

    // Navigate to the booking screen with the rebook data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookServiceScreen(
          rebookData: {
            'plateNumber': plateNumber,
            'services': services,
            'customer': customer,
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 2,
      initialIndex: (widget.initialTabIndex >= 0 && widget.initialTabIndex <= 1)
          ? widget.initialTabIndex
          : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Booking History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),

        // Drawer (matches CustomerHome style)
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Colors.yellow[700]),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    "EC Carwash",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text("Home"),
                selected: _selectedMenu == "Home",
                selectedTileColor: Colors.yellow[100],
                onTap: () => _onSelect("Home"),
              ),
              ListTile(
                leading: const Icon(Icons.book_online),
                title: const Text("Book a Service"),
                selected: _selectedMenu == "Book",
                selectedTileColor: Colors.yellow[100],
                onTap: () => _onSelect("Book"),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text("Booking History"),
                selected: _selectedMenu == "History",
                selectedTileColor: Colors.yellow[100],
                onTap: () => _onSelect("History"),
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text("Notifications"),
                selected: _selectedMenu == "Notifications",
                selectedTileColor: Colors.yellow[100],
                onTap: () => _onSelect("Notifications"),
              ),
              ListTile(
                leading: const Icon(Icons.account_circle),
                title: const Text("Account"),
                selected: _selectedMenu == "Account",
                selectedTileColor: Colors.yellow[100],
                onTap: () => _onSelect("Account"),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("Logout"),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await GoogleSignInService.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),

        body: user == null
            ? const Center(child: Text('Please log in to view history.'))
            : TabBarView(
                children: [
                  _buildCompletedTab(user), // from Transactions
                  _buildCancelledTab(
                    user,
                  ), // from Bookings(status == cancelled)
                ],
              ),
      ),
    );
  }

  /// COMPLETED = from Bookings where status == "completed" AND source == "customer-app"
  /// Then filter client-side for userId OR userEmail match
  Widget _buildCompletedTab(User user) {
    // Get all completed customer-app bookings and filter by user
    final stream = FirebaseFirestore.instance
        .collection('Bookings')
        .where('status', isEqualTo: 'completed')
        .where('source', isEqualTo: 'customer-app')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snap.error}'),
                const SizedBox(height: 8),
                Text('User: ${user.email}', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: Text('No data available.'));
        }

        // Filter bookings for THIS user only (by userId OR userEmail)
        final userBookings = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bookingUserId = data['userId'] as String? ?? '';
          final bookingUserEmail = data['userEmail'] as String? ?? '';

          // Match if userId OR userEmail matches (case-insensitive for email)
          return (bookingUserId.isNotEmpty && bookingUserId == user.uid) ||
                 (bookingUserEmail.isNotEmpty &&
                  bookingUserEmail.toLowerCase() == user.email?.toLowerCase());
        }).toList();

        if (userBookings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No completed bookings yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your completed service history will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
              itemCount: userBookings.length,
              itemBuilder: (_, i) {
                final data = userBookings[i].data() as Map<String, dynamic>;

                final plate = (data['plateNumber'] ?? 'N/A').toString();

                // Use updatedAt (when marked complete) or scheduledDateTime
                final scheduledDateTime = data['updatedAt'] ??
                                         data['scheduledDateTime'] ??
                                         data['selectedDateTime'] ??
                                         data['createdAt'];
                final formattedDateTime = _formatDateTime(scheduledDateTime);

                final services = (data['services'] as List<dynamic>? ?? [])
                    .cast<Map<String, dynamic>>();

                // Build services label
                final servicesLabel = services.isNotEmpty
                    ? services
                        .map((s) {
                          final name = (s['serviceName'] ?? '').toString();
                          final vt = (s['vehicleType'] ?? '').toString();
                          return vt.isNotEmpty ? '$name ($vt)' : name;
                        })
                        .join(', ')
                    : 'N/A';

                final total = (data['totalAmount'] ?? data['total'] ?? 0).toString();

                return Card(
                  margin: const EdgeInsets.all(12),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('Plate: $plate'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date: $formattedDateTime'),
                            const SizedBox(height: 4),
                            Text('Services: $servicesLabel'),
                            const SizedBox(height: 4),
                            Text('Total: PHP $total'),
                          ],
                        ),
                        trailing: const Chip(
                          label: Text(
                            'COMPLETED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: Colors.green,
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _rebookTransaction(data),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Rebook'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.yellow[700],
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
      },
    );
  }

  /// CANCELLED = from Bookings where status == "cancelled" AND source == "customer-app"
  /// Then filter client-side for userId OR userEmail match
  Widget _buildCancelledTab(User user) {
    final stream = FirebaseFirestore.instance
        .collection('Bookings')
        .where('status', isEqualTo: 'cancelled')
        .where('source', isEqualTo: 'customer-app')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error loading cancelled bookings: ${snap.error}'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: Text('No data available.'));
        }

        // Filter bookings for THIS user only (by userId OR userEmail)
        final userBookings = snap.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bookingUserId = data['userId'] as String? ?? '';
          final bookingUserEmail = data['userEmail'] as String? ?? '';

          // Match if userId OR userEmail matches (case-insensitive for email)
          return (bookingUserId.isNotEmpty && bookingUserId == user.uid) ||
                 (bookingUserEmail.isNotEmpty &&
                  bookingUserEmail.toLowerCase() == user.email?.toLowerCase());
        }).toList();

        if (userBookings.isEmpty) {
          return const Center(child: Text('No cancelled bookings.'));
        }

        return ListView.builder(
          itemCount: userBookings.length,
          itemBuilder: (_, i) {
            final data = userBookings[i].data() as Map<String, dynamic>;
            final plate = (data['plateNumber'] ?? 'N/A').toString();

            // Use unified datetime field (with fallback for legacy data)
            final scheduledDateTime = data['scheduledDateTime'] ??
                                     data['selectedDateTime'] ??
                                     data['date'];
            final formattedDateTime = _formatDateTime(scheduledDateTime);

            final services = (data['services'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>();
            final total = data['total']; // if you saved it on the booking

            return Card(
              margin: const EdgeInsets.all(12),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text('Plate: $plate'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date: $formattedDateTime'),
                    const SizedBox(height: 4),
                    Text(
                      services.isNotEmpty
                          ? 'Services: ${services.map((s) => s['serviceName'] ?? '').join(', ')}'
                          : 'Services: N/A',
                    ),
                    if (total != null) ...[
                      const SizedBox(height: 4),
                      Text('Total: ₱$total'),
                    ],
                  ],
                ),
                trailing: const Chip(
                  label: Text(
                    'CANCELLED',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
