import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import 'package:docuscan_pro/core/constants/app_constants.dart';

/// Cloud export service providing both the system share sheet and direct
/// uploads to Google Drive and Dropbox.
///
/// Both direct integrations are pure Dart (no custom platform channel):
/// - Google Drive: `google_sign_in` + `googleapis` Drive v3 with the
///   least-privilege `drive.file` scope (the app only sees files it created).
/// - Dropbox: OAuth2 PKCE via `flutter_web_auth_2` and the Dropbox HTTP API.
///   The long-lived refresh token is kept in `flutter_secure_storage`.
///
/// When the provider keys in [AppConstants] are still placeholders the
/// `is…Configured` getters return false and the UI should fall back to
/// [shareViaSystemSheet].
class CloudExportService {
  CloudExportService._();

  static const _storage = FlutterSecureStorage();

  /// Share a file using the OS system share sheet.
  /// This covers iCloud, OneDrive, and any app that registers as a share target.
  static Future<void> shareViaSystemSheet(
    String filePath, {
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(filePath)], subject: subject),
    );
  }

  // ===========================================================================
  // Google Drive
  // ===========================================================================

  static const List<String> _driveScopes = [drive.DriveApi.driveFileScope];
  static Future<void>? _googleInit;

  /// Whether Google Sign-In has real (non-placeholder) client configuration.
  /// iOS needs the iOS OAuth client ID; Android needs the *web* client ID as
  /// `serverClientId` for Credential Manager.
  static bool get isGoogleDriveConfigured => Platform.isIOS
      ? !AppConstants.isPlaceholder(AppConstants.googleIosClientId)
      : !AppConstants.isPlaceholder(AppConstants.googleServerClientId);

  static Future<void> _ensureGoogleInitialized() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? AppConstants.googleIosClientId : null,
      serverClientId:
          AppConstants.isPlaceholder(AppConstants.googleServerClientId)
              ? null
              : AppConstants.googleServerClientId,
    );
  }

  /// Signs in (silently if possible, otherwise interactively) and returns a
  /// Drive client authorised for [_driveScopes].
  static Future<drive.DriveApi> _driveApi({required bool interactive}) async {
    await _ensureGoogleInitialized();
    final signIn = GoogleSignIn.instance;

    var account = await signIn.attemptLightweightAuthentication();
    if (account == null) {
      if (!interactive) {
        throw const CloudExportException('Not signed in to Google');
      }
      account = await signIn.authenticate(scopeHint: _driveScopes);
    }

    var authorization =
        await account.authorizationClient.authorizationForScopes(_driveScopes);
    if (authorization == null) {
      if (!interactive) {
        throw const CloudExportException('Google Drive access not granted');
      }
      authorization =
          await account.authorizationClient.authorizeScopes(_driveScopes);
    }

    return drive.DriveApi(authorization.authClient(scopes: _driveScopes));
  }

  /// Upload a file directly to Google Drive, into a "DocuScan Pro" folder
  /// that is created on first use and reused afterwards.
  /// Signs the user in interactively if needed.
  static Future<CloudUploadResult> uploadToGoogleDrive(
    String filePath, {
    String? folderName,
  }) async {
    if (!isGoogleDriveConfigured) {
      return const CloudUploadResult(
        success: false,
        provider: CloudProvider.googleDrive,
        error: 'Google Drive is not configured in this build',
        notConfigured: true,
      );
    }

    try {
      final api = await _driveApi(interactive: true);
      final folderId =
          await _findOrCreateDriveFolder(api, folderName ?? AppConstants.cloudExportFolderName);

      final file = File(filePath);
      final length = await file.length();
      final metadata = drive.File()
        ..name = file.uri.pathSegments.last
        ..parents = [folderId];

      final created = await api.files.create(
        metadata,
        uploadMedia: drive.Media(
          file.openRead(),
          length,
          contentType: lookupMimeType(filePath) ?? 'application/octet-stream',
        ),
        $fields: 'id, webViewLink',
      );

      return CloudUploadResult(
        success: true,
        provider: CloudProvider.googleDrive,
        remoteId: created.id,
        remoteUrl: created.webViewLink,
      );
    } on GoogleSignInException catch (e) {
      return CloudUploadResult(
        success: false,
        provider: CloudProvider.googleDrive,
        error: e.code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in cancelled'
            : (e.description ?? e.code.name),
        cancelled: e.code == GoogleSignInExceptionCode.canceled,
      );
    } catch (e) {
      return CloudUploadResult(
        success: false,
        provider: CloudProvider.googleDrive,
        error: e.toString(),
      );
    }
  }

  static Future<String> _findOrCreateDriveFolder(
    drive.DriveApi api,
    String name,
  ) async {
    const folderMime = 'application/vnd.google-apps.folder';
    final escaped = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final existing = await api.files.list(
      q: "mimeType = '$folderMime' and name = '$escaped' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
      pageSize: 1,
    );
    final id = existing.files?.firstOrNull?.id;
    if (id != null) return id;

    final folder = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = folderMime,
      $fields: 'id',
    );
    return folder.id!;
  }

  /// Whether the user is already signed in to Google with Drive access
  /// (checked without showing any UI).
  static Future<bool> isGoogleDriveAvailable() async {
    if (!isGoogleDriveConfigured) return false;
    try {
      await _driveApi(interactive: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sign in to Google Drive interactively. Returns true on success.
  static Future<bool> signInToGoogleDrive() async {
    if (!isGoogleDriveConfigured) return false;
    try {
      await _driveApi(interactive: true);
      return true;
    } catch (e) {
      debugPrint('Google Drive sign-in failed: $e');
      return false;
    }
  }

  static Future<void> signOutOfGoogleDrive() async {
    if (!isGoogleDriveConfigured) return;
    await _ensureGoogleInitialized();
    await GoogleSignIn.instance.signOut();
  }

  // ===========================================================================
  // Dropbox
  // ===========================================================================

  static const _dropboxRefreshTokenKey = 'dropbox_refresh_token';
  static const _dropboxAuthorizeUrl = 'https://www.dropbox.com/oauth2/authorize';
  static const _dropboxTokenUrl = 'https://api.dropboxapi.com/oauth2/token';
  static const _dropboxUploadUrl = 'https://content.dropboxapi.com/2/files/upload';
  static const _dropboxApiBase = 'https://api.dropboxapi.com/2';

  /// Single-request upload limit of /files/upload (larger files would need
  /// an upload session).
  static const int _dropboxMaxSimpleUploadBytes = 150 * 1024 * 1024;

  static String? _dropboxAccessToken;
  static DateTime? _dropboxAccessTokenExpiry;

  static bool get isDropboxConfigured =>
      !AppConstants.isPlaceholder(AppConstants.dropboxAppKey);

  /// Whether a Dropbox refresh token is stored (the user linked Dropbox).
  static Future<bool> isDropboxAvailable() async {
    if (!isDropboxConfigured) return false;
    try {
      return (await _storage.read(key: _dropboxRefreshTokenKey)) != null;
    } catch (_) {
      return false;
    }
  }

  /// Runs the OAuth2 PKCE flow in a browser tab. Returns true on success.
  static Future<bool> signInToDropbox() async {
    if (!isDropboxConfigured) return false;
    try {
      final verifier = generatePkceVerifier();
      final state = generatePkceVerifier(length: 32);
      final authUri = Uri.parse(_dropboxAuthorizeUrl).replace(queryParameters: {
        'client_id': AppConstants.dropboxAppKey,
        'response_type': 'code',
        'code_challenge': pkceChallengeFor(verifier),
        'code_challenge_method': 'S256',
        'token_access_type': 'offline', // => refresh token
        'redirect_uri': AppConstants.dropboxRedirectUri,
        'scope': 'files.content.write sharing.write',
        'state': state,
      });

      final callback = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme: AppConstants.dropboxRedirectScheme,
      );

      final params = Uri.parse(callback).queryParameters;
      if (params['state'] != state) {
        throw const CloudExportException('OAuth state mismatch');
      }
      final code = params['code'];
      if (code == null) {
        throw CloudExportException(
            params['error_description'] ?? params['error'] ?? 'No auth code');
      }

      final response = await http.post(Uri.parse(_dropboxTokenUrl), body: {
        'code': code,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
        'client_id': AppConstants.dropboxAppKey,
        'redirect_uri': AppConstants.dropboxRedirectUri,
      });
      if (response.statusCode != 200) {
        throw CloudExportException('Token exchange failed: ${response.body}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _storeDropboxAccessToken(json);
      final refresh = json['refresh_token'] as String?;
      if (refresh != null) {
        await _storage.write(key: _dropboxRefreshTokenKey, value: refresh);
      }
      return true;
    } catch (e) {
      debugPrint('Dropbox sign-in failed: $e');
      return false;
    }
  }

  static Future<void> signOutOfDropbox() async {
    final token = _dropboxAccessToken;
    _dropboxAccessToken = null;
    _dropboxAccessTokenExpiry = null;
    await _storage.delete(key: _dropboxRefreshTokenKey);
    if (token != null) {
      // Best effort revoke.
      try {
        await http.post(Uri.parse('$_dropboxApiBase/auth/token/revoke'),
            headers: {'Authorization': 'Bearer $token'});
      } catch (_) {}
    }
  }

  static void _storeDropboxAccessToken(Map<String, dynamic> json) {
    _dropboxAccessToken = json['access_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 14400;
    // Refresh a minute early to avoid racing the expiry.
    _dropboxAccessTokenExpiry =
        DateTime.now().add(Duration(seconds: expiresIn - 60));
  }

  /// Returns a valid short-lived access token, refreshing it if needed.
  static Future<String> _dropboxToken() async {
    final cached = _dropboxAccessToken;
    final expiry = _dropboxAccessTokenExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return cached;
    }

    final refresh = await _storage.read(key: _dropboxRefreshTokenKey);
    if (refresh == null) {
      throw const CloudExportException('Not signed in to Dropbox');
    }
    final response = await http.post(Uri.parse(_dropboxTokenUrl), body: {
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
      'client_id': AppConstants.dropboxAppKey,
    });
    if (response.statusCode != 200) {
      // Refresh token revoked or invalid — force a new sign-in next time.
      if (response.statusCode == 400 || response.statusCode == 401) {
        await _storage.delete(key: _dropboxRefreshTokenKey);
      }
      throw CloudExportException('Dropbox token refresh failed: ${response.body}');
    }
    _storeDropboxAccessToken(jsonDecode(response.body) as Map<String, dynamic>);
    return _dropboxAccessToken!;
  }

  /// Upload a file directly to Dropbox (signing in first if needed) and
  /// return a shared link.
  static Future<CloudUploadResult> uploadToDropbox(
    String filePath, {
    String? folderPath,
  }) async {
    if (!isDropboxConfigured) {
      return const CloudUploadResult(
        success: false,
        provider: CloudProvider.dropbox,
        error: 'Dropbox is not configured in this build',
        notConfigured: true,
      );
    }

    try {
      if (!await isDropboxAvailable()) {
        final ok = await signInToDropbox();
        if (!ok) {
          return const CloudUploadResult(
            success: false,
            provider: CloudProvider.dropbox,
            error: 'Dropbox sign-in was cancelled or failed',
            cancelled: true,
          );
        }
      }

      final file = File(filePath);
      final length = await file.length();
      if (length > _dropboxMaxSimpleUploadBytes) {
        throw const CloudExportException(
            'File is larger than 150 MB — use the share sheet instead');
      }

      final token = await _dropboxToken();
      final folder = folderPath ?? '/${AppConstants.cloudExportFolderName}';
      final remotePath = '$folder/${file.uri.pathSegments.last}';

      final upload = await http.post(
        Uri.parse(_dropboxUploadUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': dropboxApiArg({
            'path': remotePath,
            'mode': 'add',
            'autorename': true,
            'mute': false,
          }),
        },
        body: await file.readAsBytes(),
      );
      if (upload.statusCode != 200) {
        throw CloudExportException('Upload failed (${upload.statusCode}): ${upload.body}');
      }
      final uploaded = jsonDecode(upload.body) as Map<String, dynamic>;
      final storedPath = uploaded['path_lower'] as String? ?? remotePath;

      String? link;
      try {
        link = await _dropboxSharedLink(token, storedPath);
      } catch (e) {
        // The file is uploaded; a missing link is not fatal.
        debugPrint('Dropbox shared link failed: $e');
      }

      return CloudUploadResult(
        success: true,
        provider: CloudProvider.dropbox,
        remoteId: uploaded['id'] as String?,
        remoteUrl: link,
      );
    } catch (e) {
      return CloudUploadResult(
        success: false,
        provider: CloudProvider.dropbox,
        error: e.toString(),
      );
    }
  }

  static Future<String?> _dropboxSharedLink(String token, String path) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await http.post(
      Uri.parse('$_dropboxApiBase/sharing/create_shared_link_with_settings'),
      headers: headers,
      body: jsonEncode({'path': path}),
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as Map<String, dynamic>)['url'] as String?;
    }
    // 409 shared_link_already_exists → look the existing link up.
    if (response.statusCode == 409) {
      final existing = await http.post(
        Uri.parse('$_dropboxApiBase/sharing/list_shared_links'),
        headers: headers,
        body: jsonEncode({'path': path, 'direct_only': true}),
      );
      if (existing.statusCode == 200) {
        final links = (jsonDecode(existing.body) as Map<String, dynamic>)['links'] as List?;
        return (links?.firstOrNull as Map?)?['url'] as String?;
      }
    }
    throw CloudExportException('Shared link failed (${response.statusCode}): ${response.body}');
  }

  // ===========================================================================
  // Helpers (public for testing)
  // ===========================================================================

  static const _pkceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// RFC 7636 code verifier: 43–128 unreserved characters.
  static String generatePkceVerifier({int length = 64}) {
    final random = Random.secure();
    return List.generate(
        length, (_) => _pkceChars[random.nextInt(_pkceChars.length)]).join();
  }

  /// RFC 7636 S256 challenge: base64url(sha256(verifier)) without padding.
  static String pkceChallengeFor(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Encodes the `Dropbox-API-Arg` header. HTTP headers must be ASCII, so
  /// Dropbox requires non-ASCII characters (e.g. in file names) to be
  /// escaped as `\uXXXX`.
  static String dropboxApiArg(Map<String, dynamic> arg) {
    final json = jsonEncode(arg);
    final buffer = StringBuffer();
    for (final unit in json.codeUnits) {
      if (unit > 0x7E) {
        buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }
}

class CloudExportException implements Exception {
  final String message;
  const CloudExportException(this.message);

  @override
  String toString() => message;
}

enum CloudProvider {
  googleDrive,
  dropbox,
  iCloud,
  oneDrive,
  systemShare,
}

class CloudUploadResult {
  final bool success;
  final CloudProvider provider;
  final String? remoteId;
  final String? remoteUrl;
  final String? error;

  /// The provider has placeholder keys in this build; callers should fall
  /// back to the system share sheet.
  final bool notConfigured;

  /// The user cancelled sign-in; callers should not show an error.
  final bool cancelled;

  const CloudUploadResult({
    required this.success,
    required this.provider,
    this.remoteId,
    this.remoteUrl,
    this.error,
    this.notConfigured = false,
    this.cancelled = false,
  });
}
