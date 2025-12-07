import {onDocumentUpdated, onDocumentDeleted, onDocumentCreated} from "firebase-functions/v2/firestore";
import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK
admin.initializeApp();

// Export migration and diagnostic functions
export {migrateBookingUserFields} from "./migrate-bookings-http";
export {checkCompletedBookings} from "./check-completed";

/**
 * Backfill customerEmail in Transactions from linked Bookings
 * This is more reliable than using Customer documents since Customer docs may be deleted
 * Call with: curl https://REGION-PROJECT.cloudfunctions.net/backfillCustomerEmails
 */
export const backfillCustomerEmails = onRequest({timeoutSeconds: 540}, async (req, res) => {
  logger.info("🔧 Backfilling customerEmail from Bookings");

  try {
    const db = admin.firestore();

    // Get all transactions WITHOUT customerEmail
    const allTransactions = await db.collection("Transactions").get();
    const missingEmail = allTransactions.docs.filter((doc) => {
      const email = doc.data().customerEmail;
      return !email || email.toString().trim() === "";
    });

    logger.info(`Total: ${allTransactions.docs.length}, Missing: ${missingEmail.length}`);

    let updated = 0;
    let failed = 0;
    let noBooking = 0;

    for (const txDoc of missingEmail) {
      const txData = txDoc.data();

      try {
        // Strategy 1: Find Booking by transactionId reference
        const bookingsWithTxId = await db.collection("Bookings")
          .where("transactionId", "==", txDoc.id)
          .limit(1)
          .get();

        if (!bookingsWithTxId.empty) {
          const booking = bookingsWithTxId.docs[0].data();
          const email = booking.userEmail;

          if (email && email.trim() !== "") {
            await txDoc.ref.update({customerEmail: email});
            logger.info(`Updated ${txDoc.id} with ${email} (via transactionId)`);
            updated++;
            continue;
          }
        }

        // Strategy 2: Find Booking by matching plate + date
        const plate = txData.vehiclePlateNumber;
        const txDate = txData.transactionAt?.toDate?.();

        if (plate && txDate) {
          const dayBefore = new Date(txDate.getTime() - 24 * 60 * 60 * 1000);
          const dayAfter = new Date(txDate.getTime() + 24 * 60 * 60 * 1000);

          const bookingsByPlate = await db.collection("Bookings")
            .where("plateNumber", "==", plate)
            .where("scheduledDateTime", ">=", admin.firestore.Timestamp.fromDate(dayBefore))
            .where("scheduledDateTime", "<=", admin.firestore.Timestamp.fromDate(dayAfter))
            .get();

          if (!bookingsByPlate.empty) {
            const booking = bookingsByPlate.docs[0].data();
            const email = booking.userEmail;

            if (email && email.trim() !== "") {
              await txDoc.ref.update({customerEmail: email});
              logger.info(`Updated ${txDoc.id} with ${email} (via plate+date)`);
              updated++;
              continue;
            }
          }
        }

        noBooking++;
        logger.warn(`No booking found for transaction ${txDoc.id}`);
      } catch (error) {
        failed++;
        logger.error(`Error processing ${txDoc.id}:`, error);
      }
    }

    const summary = {
      total: allTransactions.docs.length,
      missing: missingEmail.length,
      updated,
      noBooking,
      failed,
    };

    logger.info("Backfill complete:", summary);
    res.status(200).json({success: true, summary});
  } catch (error) {
    logger.error("Backfill failed:", error);
    res.status(500).json({success: false, error: String(error)});
  }
});

/**
 * Manual error logging endpoint for web platform
 * Call from web app when automatic Firestore logging fails
 */
export const logWebError = onRequest(async (req, res) => {
  // Allow CORS from your domain
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const {error, stackTrace, context, userId, userEmail, additionalData, fatal} = req.body;

    const db = admin.firestore();
    await db.collection("ErrorLogs").add({
      error: error || "Unknown error",
      stackTrace: stackTrace || null,
      context: context || "unknown",
      userId: userId || "anonymous",
      userEmail: userEmail || "unknown",
      platform: "web",
      fatal: fatal || false,
      additionalData: additionalData || {},
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      userAgent: req.headers["user-agent"] || "unknown",
      ip: req.headers["x-forwarded-for"] || req.socket.remoteAddress || "unknown",
    });

    logger.info(`Web error logged: ${context || "unknown"}`, {userId, error});
    res.status(200).json({success: true});
  } catch (error) {
    logger.error("Failed to log web error:", error);
    res.status(500).json({success: false, error: String(error)});
  }
});

// Preferred locale/timezone for human-readable times in messages
const DEFAULT_LOCALE = process.env.APP_LOCALE || "en-PH";
const DEFAULT_TIME_ZONE = process.env.APP_TIME_ZONE || "Asia/Manila";

/**
 * Send push notification when booking status changes
 * Triggers on any update to a booking document in Firestore
 */
export const sendBookingNotification = onDocumentUpdated(
  "Bookings/{bookingId}",
  async (event) => {
    const bookingId = event.params.bookingId;
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();
    if (!beforeData || !afterData) {
      return;
    }

    const statusChanged = beforeData.status !== afterData.status;
    const beforeTs = beforeData.scheduledDateTime as admin.firestore.Timestamp | undefined;
    const afterTs = afterData.scheduledDateTime as admin.firestore.Timestamp | undefined;
    const scheduleChanged = !!(beforeTs && afterTs && beforeTs.toMillis() !== afterTs.toMillis());

    if (!statusChanged && !scheduleChanged) {
      return;
    }

    const newStatus = afterData.status;
    const userEmail = afterData.userEmail as string | undefined;

    if (!userEmail) {
      return;
    }

    try {
      const userSnapshot = await admin.firestore()
        .collection("Users")
        .where("email", "==", userEmail)
        .limit(1)
        .get();

      if (userSnapshot.empty) {
        return;
      }

      const userData = userSnapshot.docs[0].data();
      const fcmToken = userData.fcmToken as string | undefined;

      if (!fcmToken) {
        return;
      }

      let notificationTitle = "";
      let notificationBody = "";
      let notificationType = "";

      if (statusChanged) {
        switch (newStatus) {
        case "approved":
          notificationTitle = "Booking Confirmed!";
          notificationBody = "Your booking has been successfully approved. Kindly ensure timely arrival, as bookings will be automatically cancelled if you are more than 10 minutes late.";
          notificationType = "booking_approved";
          break;
        case "in-progress":
          notificationTitle = "Service Started";
          notificationBody = "Your vehicle service is now in progress.";
          notificationType = "booking_in_progress";
          break;
        case "completed":
          notificationTitle = "Service Completed";
          notificationBody = "Your vehicle service has been completed. Thank you for choosing EC Carwash!";
          notificationType = "booking_completed";
          break;
        case "cancelled":
          notificationTitle = "Booking Cancelled";
          notificationBody = "Your booking has been cancelled.";
          notificationType = "booking_cancelled";
          break;
        default:
          return;
        }
      } else if (scheduleChanged) {
        const when = afterTs ?
          new Date(afterTs.toMillis()).toLocaleString(DEFAULT_LOCALE, {
            timeZone: DEFAULT_TIME_ZONE,
            year: "numeric",
            month: "short",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit",
            hour12: true,
          }) :
          "a new time";
        notificationTitle = "Booking Rescheduled";
        notificationBody = `Your booking has been rescheduled to ${when}.`;
        notificationType = "booking_rescheduled";
      }

      const message: any = {
        notification: {
          title: notificationTitle,
          body: notificationBody,
        },
        data: {
          bookingId: bookingId,
          status: newStatus,
          type: notificationType,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          rescheduledAt: afterTs ? afterTs.toMillis().toString() : "",
        },
        token: fcmToken,
        android: {notification: {channelId: "booking_channel", priority: "high", sound: "default"}},
        apns: {payload: {aps: {sound: "default", badge: 1}}},
      };

      await admin.messaging().send(message);
    } catch (error) {
      logger.error(`Error sending notification for booking ${bookingId}:`, error);
    }
  }
);

/**
 * Send push notification when an in-app Notification document is created
 * This covers cases like completed/cancelled/rescheduled created by the app
 */
export const sendNotificationOnCreate = onDocumentCreated(
  "Notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data() as any;
    const userEmail: string | undefined = data.userId;
    const type: string = data.type || "general";
    const title: string = data.title || "EC Carwash";
    const message: string = data.message || "You have a new notification";

    // Avoid duplicating booking_approved which is already handled by status trigger
    // Only push for generic messages; booking_* notifications are handled by Bookings trigger
    const allowed = [
      "general",
    ];
    if (!allowed.includes(type)) {
      return;
    }

    if (!userEmail) {
      return;
    }

    try {
      const userSnapshot = await admin
        .firestore()
        .collection("Users")
        .where("email", "==", userEmail)
        .limit(1)
        .get();

      if (userSnapshot.empty) {
        return;
      }

      const fcmToken = userSnapshot.docs[0].data().fcmToken as string | undefined;
      if (!fcmToken) {
        return;
      }

      const payload = {
        notification: {
          title,
          body: message,
        },
        data: {
          type,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          notificationId: event.params.notificationId,
        },
        token: fcmToken,
        android: {
          notification: {
            channelId: "booking_channel",
            priority: "high" as const,
            sound: "default",
          },
        },
        apns: {
          payload: {aps: {sound: "default", badge: 1}},
        },
      };

      await admin.messaging().send(payload as any);
    } catch (e) {
      logger.error(`Error pushing notification ${event.params.notificationId}:`, e);
    }
  }
);

/**
 * Clean up FCM token when user logs out
 * Optional: Triggers when a user document is deleted
 */
export const cleanupUserToken = onDocumentDeleted(
  "Users/{userId}",
  async () => {
    // Cleanup handler for user deletion
  }
);

/**
 * Handle token refresh
 * Optional: Log when tokens are updated
 */
export const logTokenUpdate = onDocumentUpdated(
  "Users/{userId}",
  async () => {
    // Token update handler
  }
);

/**
 * Gemini AI Analytics Proxy
 * Handles AI summary generation for analytics reports with retry logic
 */
export const generateAISummary = onRequest(
  {cors: true, timeoutSeconds: 120},
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method Not Allowed");
      return;
    }

    const {prompt} = request.body;

    if (!prompt) {
      response.status(400).send("Missing prompt");
      return;
    }

    // Get API key from environment variable
    const apiKey = process.env.GEMINI_API_KEY;

    if (!apiKey) {
      logger.error("GEMINI_API_KEY not configured");
      response.status(500).send("API key not configured");
      return;
    }
    const apiUrl =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

    const maxRetries = 3;
    let lastError = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          const backoffMs = Math.min(1000 * Math.pow(2, attempt), 8000);
          logger.info(`Retry attempt ${attempt + 1}/${maxRetries} after ${backoffMs}ms`);
          await new Promise((resolve) => setTimeout(resolve, backoffMs));
        }

        const geminiResponse = await fetch(`${apiUrl}?key=${apiKey}`, {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({
            contents: [{parts: [{text: prompt}]}],
          }),
        });

        if (geminiResponse.status === 503) {
          lastError = "Service temporarily unavailable (503)";
          logger.warn(`Attempt ${attempt + 1} failed: ${lastError}`);
          continue;
        }

        if (geminiResponse.status === 429) {
          lastError = "Rate limit exceeded (429)";
          logger.warn(`Attempt ${attempt + 1} failed: ${lastError}`);
          continue;
        }

        if (!geminiResponse.ok) {
          const errorText = await geminiResponse.text();
          logger.error("Gemini API error:", errorText);
          response.status(500).send(`Gemini API error: ${errorText}`);
          return;
        }

        const data = await geminiResponse.json();
        const summary = data.candidates?.[0]?.content?.parts?.[0]?.text;

        if (!summary) {
          response.status(500).send("No summary generated");
          return;
        }

        response.status(200).json({summary});
        return;
      } catch (error: any) {
        lastError = error.message;
        logger.error(`Attempt ${attempt + 1} error:`, error);

        if (attempt === maxRetries - 1) {
          response.status(500).send(`Error after ${maxRetries} attempts: ${lastError}`);
          return;
        }
      }
    }

    response.status(503).send(
      `Service unavailable after ${maxRetries} retries. Please try again later.`
    );
  }
);
