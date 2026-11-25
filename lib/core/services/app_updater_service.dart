import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const String kAppVersion = '3.6.7';
const String kGithubReleasesLatestApi =
    'https://api.github.com/repos/quydnvocvach/ChemNote/releases/latest';
const String kGithubReleasesFallbackUrl =
    'https://github.com/quydnvocvach/ChemNote/releases/latest';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String downloadUrl;
  final String htmlUrl;
  final String? errorMessage;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.releaseNotes = '',
    this.downloadUrl = kGithubReleasesFallbackUrl,
    this.htmlUrl = kGithubReleasesFallbackUrl,
    this.errorMessage,
  });
}

/// Kiểm tra phiên bản APK mới nhất trên GitHub Releases (`quydnvocvach/ChemNote`)
/// và mở link tải `ChemNote-MatePad-11.5s-release.apk` trực tiếp trên MatePad 11.5"S.
class AppUpdaterService {
  static Future<AppUpdateInfo> checkForUpdate({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final response = await httpClient.get(
        Uri.parse(kGithubReleasesLatestApi),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return const AppUpdateInfo(
          hasUpdate: false,
          currentVersion: kAppVersion,
          latestVersion: kAppVersion,
          errorMessage: 'Không thể kết nối máy chủ cập nhật GitHub.',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTag = (json['tag_name'] as String? ?? kAppVersion).trim();
      final latestVersion = rawTag.startsWith('v') || rawTag.startsWith('V')
          ? rawTag.substring(1)
          : rawTag;
      final htmlUrl =
          (json['html_url'] as String?) ?? kGithubReleasesFallbackUrl;
      final body = (json['body'] as String?) ?? '';

      String downloadUrl = htmlUrl;
      final assets = json['assets'] as List<dynamic>? ?? const [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final browserUrl = asset['browser_download_url'] as String?;
          if (name.endsWith('.apk') && browserUrl != null) {
            downloadUrl = browserUrl;
            break;
          }
        }
      }

      return AppUpdateInfo(
        hasUpdate: compareSemver(latestVersion, kAppVersion) > 0,
        currentVersion: kAppVersion,
        latestVersion: latestVersion,
        releaseNotes: body,
        downloadUrl: downloadUrl,
        htmlUrl: htmlUrl,
      );
    } catch (e) {
      return AppUpdateInfo(
        hasUpdate: false,
        currentVersion: kAppVersion,
        latestVersion: kAppVersion,
        errorMessage: 'Lỗi kiểm tra cập nhật: $e',
      );
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }

  /// So sánh phiên bản dạng `major.minor.patch`. Trả về `> 0` nếu `a > b`.
  static int compareSemver(String a, String b) {
    final pa = a
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pb = b
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final maxLen = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < maxLen; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static Future<bool> openDownloadUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
