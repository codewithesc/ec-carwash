import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoogleSignInService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web flow (no serverClientId!)
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.setCustomParameters({'prompt': 'select_account'});

        final UserCredential userCredential = await _auth.signInWithPopup(
          googleProvider,
        );

        return userCredential.user;
      } else {
        // Android/iOS/Desktop flow
        final GoogleSignIn googleSignIn = GoogleSignIn(
          scopes: ['email'],
          serverClientId:
              '14839235089-an3b18j0b8039dnmm0at8jermsshf9e8.apps.googleusercontent.com',
        );

        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(
          credential,
        );

        return userCredential.user;
      }
    } on FirebaseAuthException catch (e) {
      // Re-throw with more details so the UI can show specific errors
      throw Exception('Firebase Auth Error [${e.code}]: ${e.message}');
    } catch (e) {
      // Re-throw the error instead of returning null so we get better error messages
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await GoogleSignIn().signOut();
    }
  }

  static User? getCurrentUser() => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
}
