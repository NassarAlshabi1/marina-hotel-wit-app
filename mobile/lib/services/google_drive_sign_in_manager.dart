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

  GoogleSignIn? _client;

  GoogleSignIn get client {
    _client ??= GoogleSignIn(
      scopes: kGoogleDriveScopes,
      serverClientId: kGoogleDriveServerClientId,
    );
    return _client!;
  }
}
