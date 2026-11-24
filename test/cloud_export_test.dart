import 'package:flutter_test/flutter_test.dart';

import 'package:docuscan_pro/core/constants/app_constants.dart';
import 'package:docuscan_pro/core/services/cloud_export_service.dart';

void main() {
  // Expected value cross-checked with Python:
  // base64.urlsafe_b64encode(hashlib.sha256(verifier).digest()).rstrip(b'=')
  test('PKCE S256 challenge is base64url(sha256(verifier)) without padding', () {
    expect(
      CloudExportService.pkceChallengeFor(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r-wW1gFWFOEjXk'),
      'NPsYzawS-__wqk67X9gyb4dr3JBo3hnlEi5MNyD5jX0',
    );
  });

  test('PKCE verifier uses only unreserved characters', () {
    final v = CloudExportService.generatePkceVerifier();
    expect(v.length, 64);
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
  });

  test('Dropbox-API-Arg header escapes non-ASCII characters', () {
    // e-acute, and U+1F4C4 (a surrogate pair in UTF-16).
    final name = 'R${String.fromCharCode(0xE9)}sum${String.fromCharCode(0xE9)} '
        '${String.fromCharCodes([0xD83D, 0xDCC4])}.pdf';
    final arg = CloudExportService.dropboxApiArg({'path': '/DocuScan Pro/$name'});
    const bs = '\\';
    expect(arg,
        '{"path":"/DocuScan Pro/R${bs}u00e9sum${bs}u00e9 ${bs}ud83d${bs}udcc4.pdf"}');
    expect(arg.codeUnits.every((c) => c < 0x80), isTrue);
  });

  test('placeholder keys are detected', () {
    expect(AppConstants.isPlaceholder(AppConstants.dropboxAppKey), isTrue);
    expect(AppConstants.isPlaceholder(''), isTrue);
    expect(AppConstants.isPlaceholder('your_revenuecat_api_key'), isTrue);
    expect(AppConstants.isPlaceholder('abc123xyz'), isFalse);
  });
}
