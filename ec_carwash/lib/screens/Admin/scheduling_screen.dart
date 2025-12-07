import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ec_carwash/data_models/booking_data_unified.dart';
import 'package:ec_carwash/data_models/notification_data.dart';
import 'package:ec_carwash/data_models/unified_transaction_data.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SchedulingScreen extends StatefulWidget {
  const SchedulingScreen({super.key});

  @override
  State<SchedulingScreen> createState() => _SchedulingScreenState();
}

class _SchedulingScreenState extends State<SchedulingScreen> {
  List<Booking> _pendingBookings = [];
  List<Booking> _approvedBookings = [];
  List<Booking> _completedBookings = [];
  List<Booking> _cancelledBookings = [];
  bool _isLoading = true;
  String _selectedFilter = 'today'; // all, today
  Timer? _autoCancelTimer;
  StreamSubscription<QuerySnapshot>? _bookingsSubscription;
  bool _isProcessingBooking = false;

  @override
  void initState() {
    super.initState();
    _setupRealtimeListener();
    _fixExistingPOSBookingsPaymentStatus();
    _startAutoCancelTimer();
  }

  @override
  void dispose() {
    _autoCancelTimer?.cancel();
    _bookingsSubscription?.cancel();
    super.dispose();
  }

  /// Setup real-time listener for bookings
  void _setupRealtimeListener() {
    Query query = FirebaseFirestore.instance.collection('Bookings');

    if (_selectedFilter == 'today') {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      query = query
          .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('scheduledDateTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    _bookingsSubscription = query.snapshots().listen((snapshot) {
      if (!mounted) return;

      try {
        final bookings = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Booking.fromJson(data, doc.id);
        }).toList();

        setState(() {
          _pendingBookings = bookings.where((b) => b.status == 'pending').toList();
          _approvedBookings = bookings.where((b) => b.status == 'approved').toList();
          _completedBookings = bookings.where((b) => b.status == 'completed').toList();
          _cancelledBookings = bookings.where((b) => b.status == 'cancelled').toList();
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading bookings: $e')),
          );
        }
      }
    });
  }

  /// Start a timer that checks for bookings to auto-cancel every 5 minutes
  void _startAutoCancelTimer() {
    _autoCancelTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _autoCheckAndCancelExpiredBookings();
    });
    // Also run it once immediately
    _autoCheckAndCancelExpiredBookings();
  }

  /// Auto-cancel approved/pending bookings from mobile app after 10 minutes if not paid/assigned
  /// Also auto-cancel bookings that exceed team capacity limits
  Future<void> _autoCheckAndCancelExpiredBookings() async {
    try {
      final now = DateTime.now();

      // Query approved and pending bookings from customer app (not POS)
      final snapshot = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('source', isEqualTo: 'customer-app')
          .where('status', whereIn: ['pending', 'approved'])
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final scheduledDateTime = (data['scheduledDateTime'] as Timestamp?)
            ?.toDate();
        final paymentStatus = data['paymentStatus'] ?? 'pending';
        final assignedTeam = data['assignedTeam'] as String?;
        final status = data['status'] as String?;

        if (scheduledDateTime != null) {
          final timeDifference = now.difference(scheduledDateTime);

          // Check 1: No-show cancellation (existing logic - 10 min past scheduled)
          if (timeDifference.inMinutes >= 10 && paymentStatus != 'paid') {
            await _autoCancelBooking(
              doc.reference,
              doc.id,
              data,
              'Auto-cancelled: No show after 10 minutes',
            );
            continue;
          }

          // Check 2: Capacity overflow (NEW LOGIC)
          // Only check approved bookings that have team assignments
          if (status == 'approved' && assignedTeam != null) {
            // Check if time slot is within business hours (8 AM - 6 PM)
            final hour = scheduledDateTime.hour;
            if (hour >= 8 && hour < 18) {
              // Count bookings for this team at this time slot
              final count = await BookingManager.getTeamBookingsCountForTimeSlot(
                team: assignedTeam,
                timeSlot: scheduledDateTime,
              );

              // If more than 2 bookings for this team at this time, auto-cancel
              if (count > 2) {
                await _autoCancelBooking(
                  doc.reference,
                  doc.id,
                  data,
                  'Not available at the requested time slot',
                );
              }
            }
          }
        }
      }

      // Real-time listener will handle the updates automatically
    } catch (e) {
      // Silent catch - errors handled by real-time listener
    }
  }

  /// Helper method for auto-cancellation with notification
  Future<void> _autoCancelBooking(
    DocumentReference docRef,
    String bookingId,
    Map<String, dynamic> data,
    String reason,
  ) async {
    try {
      await docRef.update({
        'status': 'cancelled',
        'cancelReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
        'autoCancelled': true,
      });

      // Send notification to customer
      final userEmail = data['userEmail'] as String?;
      final scheduledDateTime = (data['scheduledDateTime'] as Timestamp?)?.toDate();

      if (userEmail != null && userEmail.isNotEmpty) {
        // Create a detailed cancellation message explaining the reason
        String detailedReason = reason;
        if (scheduledDateTime != null && reason.contains('No show')) {
          final timeStr = '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
          detailedReason = 'Your booking for $timeStr has been cancelled because you did not arrive within 10 minutes. Your time slot may have been given to another customer. Please book again for a new time.';
        } else if (scheduledDateTime != null && reason.contains('requested time')) {
          final timeStr = '${scheduledDateTime.hour.toString().padLeft(2, '0')}:${scheduledDateTime.minute.toString().padLeft(2, '0')}';
          detailedReason = 'Your booking for $timeStr has been cancelled because the scheduled time has passed. Your time slot may have been given to another customer. Please book a new time slot.';
        }

        await NotificationManager.createNotification(
          userId: userEmail,
          title: 'Booking Cancelled',
          message: detailedReason,
          type: 'booking_auto_cancelled',
          metadata: {'bookingId': bookingId, 'reason': reason},
        );
      }

    } catch (e) {
      // Silent catch - errors handled by real-time listener
    }
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      List<Booking> allBookings = [];
      if (_selectedFilter == 'today') {
        allBookings = await BookingManager.getTodayBookings();
      } else {
        allBookings = await BookingManager.getAllBookings();
      }

      setState(() {
        _pendingBookings = allBookings.where((b) => b.status == 'pending').toList();
        _approvedBookings = allBookings.where((b) => b.status == 'approved').toList();
        _completedBookings = allBookings.where((b) => b.status == 'completed').toList();
        _cancelledBookings = allBookings.where((b) => b.status == 'cancelled').toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _pendingBookings = [];
        _approvedBookings = [];
        _completedBookings = [];
        _cancelledBookings = [];
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading bookings: $e')));
      }
    }
  }

  // Check team capacity for a specific time slot
  Future<Map<String, bool>> _checkTeamCapacity(DateTime scheduledDateTime) async {
    try {
      // Round to nearest 30-minute slot
      final roundedMinute = (scheduledDateTime.minute ~/ 30) * 30;
      final slotStart = DateTime(
        scheduledDateTime.year,
        scheduledDateTime.month,
        scheduledDateTime.day,
        scheduledDateTime.hour,
        roundedMinute,
      );
      final slotEnd = slotStart.add(const Duration(minutes: 30));

      // Query bookings in this time slot that are approved
      final querySnapshot = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(slotStart))
          .where('scheduledDateTime', isLessThan: Timestamp.fromDate(slotEnd))
          .where('status', isEqualTo: 'approved')
          .get();

      int teamACount = 0;
      int teamBCount = 0;

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final assignedTeam = data['assignedTeam'] as String?;

        if (assignedTeam == 'Team A') {
          teamACount++;
        } else if (assignedTeam == 'Team B') {
          teamBCount++;
        }
      }

      // Return true if team is available (count < 1), false if full
      return {
        'Team A': teamACount < 1,
        'Team B': teamBCount < 1,
      };
    } catch (e) {
      // If error, allow both teams
      return {'Team A': true, 'Team B': true};
    }
  }

  Future<void> _showTeamSelectionForApproval(Booking booking) async {
    String? selectedTeam;
    Map<String, bool> teamAvailability = {'Team A': true, 'Team B': true};

    // Check team capacity before showing dialog
    teamAvailability = await _checkTeamCapacity(booking.scheduledDateTime);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final teamAAvailable = teamAvailability['Team A'] == true;
            final teamBAvailable = teamAvailability['Team B'] == true;

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.groups, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  const Text("Assign Team & Approve"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Customer: ${booking.userName}",
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text("Plate: ${booking.plateNumber}"),
                  if (booking.vehicleType != null && booking.vehicleType!.isNotEmpty)
                    Text("Vehicle: ${booking.vehicleType}"),
                  Text("Total: ₱${booking.totalAmount.toStringAsFixed(2)}"),
                  const SizedBox(height: 20),
                  const Text(
                    "Which team will handle this booking?",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  if (!teamAAvailable && !teamBAvailable)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Both teams are fully booked for this time slot!",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: teamAvailability['Team A']! ? 1.0 : 0.5,
                          child: InkWell(
                            onTap: teamAvailability['Team A']!
                                ? () {
                                    setState(() {
                                      selectedTeam = "Team A";
                                    });
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: selectedTeam == "Team A"
                                    ? Colors.blue.shade100
                                    : teamAvailability['Team A']!
                                        ? Colors.grey.shade100
                                        : Colors.red.shade50,
                                border: Border.all(
                                  color: selectedTeam == "Team A"
                                      ? Colors.blue.shade600
                                      : teamAvailability['Team A']!
                                          ? Colors.grey.shade300
                                          : Colors.red.shade300,
                                  width: selectedTeam == "Team A" ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    teamAvailability['Team A']! ? Icons.group : Icons.block,
                                    size: 40,
                                    color: selectedTeam == "Team A"
                                        ? Colors.blue.shade600
                                        : teamAvailability['Team A']!
                                            ? Colors.grey.shade600
                                            : Colors.red.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Team A",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: selectedTeam == "Team A"
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  if (!teamAvailability['Team A']!)
                                    Text(
                                      "FULL",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Opacity(
                          opacity: teamAvailability['Team B']! ? 1.0 : 0.5,
                          child: InkWell(
                            onTap: teamAvailability['Team B']!
                                ? () {
                                    setState(() {
                                      selectedTeam = "Team B";
                                    });
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: selectedTeam == "Team B"
                                    ? Colors.green.shade100
                                    : teamAvailability['Team B']!
                                        ? Colors.grey.shade100
                                        : Colors.red.shade50,
                                border: Border.all(
                                  color: selectedTeam == "Team B"
                                      ? Colors.green.shade600
                                      : teamAvailability['Team B']!
                                          ? Colors.grey.shade300
                                          : Colors.red.shade300,
                                  width: selectedTeam == "Team B" ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    teamAvailability['Team B']! ? Icons.group : Icons.block,
                                    size: 40,
                                    color: selectedTeam == "Team B"
                                        ? Colors.green.shade600
                                        : teamAvailability['Team B']!
                                            ? Colors.grey.shade600
                                            : Colors.red.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Team B",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: selectedTeam == "Team B"
                                          ? Colors.green.shade600
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  if (!teamAvailability['Team B']!)
                                    Text(
                                      "FULL",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: selectedTeam != null
                      ? () async {
                          Navigator.pop(context);
                          await _updateBookingStatusWithTeam(
                            booking.id!,
                            'approved',
                            selectedTeam!,
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text("Approve & Assign"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateBookingStatusWithTeam(
    String bookingId,
    String status,
    String team,
  ) async {
    try {
      // Find the booking from all lists
      Booking? booking;
      booking = _pendingBookings.where((b) => b.id == bookingId).firstOrNull;
      booking ??= _approvedBookings.where((b) => b.id == bookingId).firstOrNull;
      booking ??= _completedBookings
          .where((b) => b.id == bookingId)
          .firstOrNull;
      booking ??= _cancelledBookings
          .where((b) => b.id == bookingId)
          .firstOrNull;
      if (booking == null) return;

      // Check capacity before approving
      if (status == 'approved') {
        final count = await BookingManager.getTeamBookingsCountForTimeSlot(
          team: team,
          timeSlot: booking.scheduledDateTime,
        );

        if (count >= 2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Cannot assign - $team already has 2 bookings at this time slot',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      // Update booking status with team assignment
      await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(bookingId)
          .update({
            'status': status,
            'assignedTeam': team,
            'teamCommission': booking.totalAmount * 0.35, // 35% commission
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await BookingManager.updateBookingStatus(bookingId, status);
      // Real-time listener will handle the update automatically

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking $status and assigned to $team'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating booking: $e')));
      }
    }
  }

  Future<void> _updateBookingStatus(String bookingId, String status) async {
    if (_isProcessingBooking) return;

    setState(() => _isProcessingBooking = true);

    try {
      // Find the booking from all lists
      Booking? booking;
      booking = _pendingBookings.where((b) => b.id == bookingId).firstOrNull;
      booking ??= _approvedBookings.where((b) => b.id == bookingId).firstOrNull;
      booking ??= _completedBookings
          .where((b) => b.id == bookingId)
          .firstOrNull;
      booking ??= _cancelledBookings
          .where((b) => b.id == bookingId)
          .firstOrNull;

      if (booking == null) return;

      // Update booking status
      await BookingManager.updateBookingStatus(bookingId, status);

      // If marking as completed, add commission and create transaction
      if (status == 'completed') {
        // Calculate and add team commission (35%)
        final commission =
            booking.assignedTeam != null && booking.assignedTeam!.isNotEmpty
            ? booking.totalAmount * 0.35
            : 0.0;

        await FirebaseFirestore.instance
            .collection('Bookings')
            .doc(bookingId)
            .update({
              'teamCommission': commission,
              'completedAt': FieldValue.serverTimestamp(),
            });

        // Create transaction for ALL customer-app bookings (even if transactionId exists)
        // This ensures completed bookings always appear in mobile app
        if (booking.source == 'customer-app') {
          await _createTransactionFromBooking(booking);
        }
      }

      // Real-time listener will handle the update automatically
      if (mounted) {
        String message = 'Booking status updated to $status';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating booking: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingBooking = false);
      }
    }
  }

  Future<void> _markAsPaid(Booking booking) async {
    if (_isProcessingBooking) return;

    try {
      if (booking.id == null) return;

      // Show payment confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(
            'Confirm Payment',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${booking.userName}'),
              Text('Amount: ₱${booking.totalAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              const Text('Has the customer paid for this booking?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Yes, Paid',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => _isProcessingBooking = true);

      try {
        // Update payment status to 'paid' and change status to 'approved'
        await FirebaseFirestore.instance
            .collection('Bookings')
            .doc(booking.id)
            .update({
              'paymentStatus': 'paid',
              'status': 'approved',
              'updatedAt': FieldValue.serverTimestamp(),
            });

        // DON'T create transaction yet - only when marked as complete
        // Transaction should only be created when service is actually completed

        // Real-time listener will handle the update automatically

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment confirmed. Booking moved to Approved.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isProcessingBooking = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingBooking = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error marking as paid: $e')));
      }
    }
  }

  Future<void> _createTransactionFromBooking(Booking booking) async {
    try {
      final existingTransaction = await TransactionManager.getTransactionByBookingId(booking.id!);
      if (existingTransaction != null) {
        return;
      }

      final transactionId = await TransactionManager.createFromBooking(
        bookingId: booking.id!,
        customerName: booking.userName,
        customerEmail: booking.userEmail,
        customerId: booking.customerId,
        vehiclePlateNumber: booking.plateNumber,
        contactNumber: booking.contactNumber,
        vehicleType: booking.vehicleType,
        services: booking.services
            .map((bs) => TransactionService(
                  serviceCode: bs.serviceCode,
                  serviceName: bs.serviceName,
                  vehicleType: bs.vehicleType,
                  price: bs.price,
                  quantity: bs.quantity,
                ))
            .toList(),
        total: booking.totalAmount,
        scheduledDateTime: booking.scheduledDateTime,
        assignedTeam: booking.assignedTeam,
        teamCommission: 0.0,
      );

      await FirebaseFirestore.instance
          .collection('Bookings')
          .doc(booking.id)
          .update({
            'transactionId': transactionId,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Transaction created: ${transactionId.substring(0, 8)}...',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      throw Exception('Failed to create transaction from booking: $e');
    }
  }


  Future<void> _fixExistingPOSBookingsPaymentStatus() async {
    try {
      // Find all POS bookings that don't have paymentStatus or have paymentStatus as 'unpaid'
      final query = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('source', isEqualTo: 'pos')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int updateCount = 0;

      for (final doc in query.docs) {
        final data = doc.data();
        final currentPaymentStatus = data['paymentStatus'];

        // If paymentStatus is missing or is 'unpaid', update it to 'paid'
        if (currentPaymentStatus == null || currentPaymentStatus == 'unpaid') {
          batch.update(doc.reference, {'paymentStatus': 'paid'});
          updateCount++;
        }
      }

      if (updateCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      // Ignore batch commit errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          // Header with filters only
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Today', 'today'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBookings,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildKanbanColumn(
                          'Pending Approval',
                          _pendingBookings,
                          Colors.orange,
                          Icons.schedule,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildKanbanColumn(
                          'Approved',
                          _approvedBookings,
                          Colors.blue,
                          Icons.check_circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildKanbanColumn(
                          'Completed',
                          _completedBookings,
                          Colors.green,
                          Icons.done_all,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildKanbanColumn(
                          'Cancelled',
                          _cancelledBookings,
                          Colors.red,
                          Icons.cancel,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanColumn(
    String title,
    List<Booking> bookings,
    Color color,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Column Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    bookings.length.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Column Content
          Expanded(
            child: (bookings.isEmpty)
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No bookings',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      if (index >= bookings.length) {
                        return const SizedBox.shrink();
                      }
                      final booking = bookings[index];
                      return _buildKanbanCard(booking);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
        _bookingsSubscription?.cancel();
        _setupRealtimeListener();
      },
      selectedColor: Colors.yellow.shade700,
      checkmarkColor: Colors.black,
    );
  }

  Widget _buildKanbanCard(Booking booking) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Customer name
            Text(
              booking.userName.isNotEmpty
                  ? booking.userName
                  : 'Unknown Customer',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            // Date and Time - Highlighted
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat(
                      'MMM dd, yyyy',
                    ).format(booking.scheduledDateTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    TimeOfDay.fromDateTime(
                      booking.scheduledDateTime,
                    ).format(context),
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Plate number and Vehicle type
            Row(
              children: [
                Icon(Icons.directions_car, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  booking.plateNumber,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (booking.vehicleType != null && booking.vehicleType!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '•',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    booking.vehicleType!,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Services with codes
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: booking.services.map((service) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.yellow.shade700),
                  ),
                  child: Text(
                    service.serviceCode,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.yellow.shade900,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            // Source and Team Assignment Indicators
            Row(
              children: [
                // Source indicator (POS vs App)
                if (booking.source == 'pos')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Text(
                      'POS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.shade300),
                    ),
                    child: Text(
                      'APP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                // Team assignment indicator
                if (booking.assignedTeam != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: booking.assignedTeam == 'Team A'
                          ? Colors.indigo.shade100
                          : Colors.teal.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: booking.assignedTeam == 'Team A'
                            ? Colors.indigo.shade300
                            : Colors.teal.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group,
                          size: 12,
                          color: booking.assignedTeam == 'Team A'
                              ? Colors.indigo.shade700
                              : Colors.teal.shade700,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          booking.assignedTeam!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: booking.assignedTeam == 'Team A'
                                ? Colors.indigo.shade700
                                : Colors.teal.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                // Auto-cancelled indicator
                if (booking.status == 'cancelled' && booking.autoCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade400),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'AUTO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Total amount and payment status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₱${booking.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.green,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: booking.paymentStatus == 'paid'
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: booking.paymentStatus == 'paid'
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                    ),
                  ),
                  child: Text(
                    booking.paymentStatus == 'paid' ? 'PAID' : 'UNPAID',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: booking.paymentStatus == 'paid'
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Action buttons (compact)
            _buildKanbanCardActions(booking),
          ],
        ),
      ),
    );
  }

  Widget _buildKanbanCardActions(Booking booking) {
    if (booking.status == 'pending') {
      // All pending bookings - approve with team assignment (payment not required)
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: booking.id != null
                  ? () => _showTeamSelectionForApproval(booking)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Approve & Assign'),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: booking.id != null
                      ? () => _updateBookingStatus(booking.id!, 'cancelled')
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (booking.status == 'approved') {
      // Check if this is a mobile app booking (needs payment) or POS booking (already paid)
      final bool isPOSBooking = booking.source == 'pos';
      final bool isPaid = booking.paymentStatus == 'paid';

      return Column(
        children: [
          if (!isPaid && !isPOSBooking) ...[
            // Mobile app booking - needs payment first
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: booking.id != null
                    ? () => _markAsPaid(booking)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Mark as Paid'),
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (isPaid || isPOSBooking) ...[
            // Can mark complete once paid
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: booking.id != null
                    ? () => _updateBookingStatus(booking.id!, 'completed')
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Mark Complete'),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      );
    } else if (booking.status == 'completed') {
      // Completed - no actions needed
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Service Completed',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.green.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    } else {
      // Cancelled - no actions needed
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Booking Cancelled',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.red.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
  }
}
