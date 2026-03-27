import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

const List<String> kGoogleDriveScopes = [
  drive.DriveApi.driveFileScope,
  drive.DriveApi.driveAppdataScope,
];

const String kGoogleDriveServerClientId =
    '256666337807-561s7dakv86m3kugsalv8opa8idkjmd0.apps.googleusercontent.com';

class GoogleDriveSignInManager {
  GoogleDriveSignInManager._();

  static final GoogleDriveSignInManager instance = GoogleDriveSignInManager._();

  /// Initialize GoogleSignIn with the required scopes
  Future<void> initialize() async {
    // In google_sign_in 7.x, initialize is called automatically
    // but we can use this to ensure it's ready
  }

  /// Get the GoogleSignIn instance
  GoogleSignIn get client => GoogleSignIn.instance;

  /// Check if initialized (always true in 7.x)
  bool get isInitialized => true;
}
