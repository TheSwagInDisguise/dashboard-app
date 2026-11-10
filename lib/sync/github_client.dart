import 'dart:convert';

import 'package:http/http.dart' as http;

enum SyncFileStatus { ok, notFound, tokenInvalid, error }
enum SyncPutStatus { ok, created, conflict, tokenInvalid, error }

class SyncFile {
  const SyncFile._(this.status, {this.content, this.sha, this.error});
  const SyncFile.ok(String content, String sha) : this._(SyncFileStatus.ok, content: content, sha: sha);
  const SyncFile.notFound() : this._(SyncFileStatus.notFound);
  const SyncFile.tokenInvalid() : this._(SyncFileStatus.tokenInvalid);
  const SyncFile.error(String message) : this._(SyncFileStatus.error, error: message);

  final SyncFileStatus status;
  final String? content;
  final String? sha;
  final String? error;

  bool get exists => status == SyncFileStatus.ok;
}

class SyncPutResult {
  const SyncPutResult._(this.status, {this.error});
  const SyncPutResult.ok() : this._(SyncPutStatus.ok);
  const SyncPutResult.created() : this._(SyncPutStatus.created);
  const SyncPutResult.conflict() : this._(SyncPutStatus.conflict);
  const SyncPutResult.tokenInvalid() : this._(SyncPutStatus.tokenInvalid);
  const SyncPutResult.error(String message) : this._(SyncPutStatus.error, error: message);

  final SyncPutStatus status;
  final String? error;

  bool get succeeded => status == SyncPutStatus.ok || status == SyncPutStatus.created;
}

/// Minimal GitHub REST client for the app's sync needs — Contents API only.
/// The token is passed per-call by the caller and is never stored, logged or
/// included in exceptions. dart:io is NOT used, so this compiles for Flutter
/// web too (Phase 7).
class GitHubClient {
  GitHubClient({required this.token, required this.repo});

  final String token;
  final String repo; // e.g. TheSwagInDisguise/dashboard-data

  static const _api = 'https://api.github.com';
  final http.Client _http = http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Returns the decoded file content + sha, or notFound.
  Future<SyncFile> getFile(String path) async {
    try {
      final uri = Uri.parse('$_api/repos/$repo/contents/$path');
      final response = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      switch (response.statusCode) {
        case 200:
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final encoded = (body['content'] as String?)?.replaceAll('\n', '') ?? '';
          final sha = body['sha'] as String? ?? '';
          return SyncFile.ok(utf8.decode(base64.decode(encoded)), sha);
        case 404:
          return const SyncFile.notFound();
        case 401:
        case 403:
          return const SyncFile.tokenInvalid();
        default:
          return SyncFile.error('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return SyncFile.error('network: $e');
    }
  }

  /// Creates or updates a file. Pass [sha] when updating (required by GitHub);
  /// omit it to create. A sha mismatch yields SyncPutStatus.conflict so the
  /// caller can re-read, re-merge and retry.
  Future<SyncPutResult> putFile(
    String path,
    String content, {
    String? sha,
    String? message,
  }) async {
    try {
      final uri = Uri.parse('$_api/repos/$repo/contents/$path');
      final body = <String, dynamic>{
        'message': message ?? 'daydeck sync: $path',
        'content': base64.encode(utf8.encode(content)),
      };
      if (sha != null) body['sha'] = sha;

      final response = await _http
          .put(uri, headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));

      switch (response.statusCode) {
        case 200:
          return const SyncPutResult.ok();
        case 201:
          return const SyncPutResult.created();
        case 409:
        case 422:
          return const SyncPutResult.conflict();
        case 401:
        case 403:
          return const SyncPutResult.tokenInvalid();
        default:
          return SyncPutResult.error('HTTP ${response.statusCode}');
      }
    } catch (e) {
      return SyncPutResult.error('network: $e');
    }
  }

  void close() => _http.close();
}
