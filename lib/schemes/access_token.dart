import 'package:twitter_login/src/utils.dart';

/// The access token for Twitter API.
class AccessToken {
  /// The access token for using the Twitter APIs
  final String _authToken;

  /// The access token secret for using the Twitter APIs
  final String _authTokenSecret;

  final int _userId;

  String get authToken => _authToken;
  String get authTokenSecret => _authTokenSecret;
  int get userId => _userId;

  AccessToken(Map<String, dynamic>? params)
      : this._authToken = params!['oauth_token'],
        this._authTokenSecret = params['oauth_token_secret'],
        this._userId = params['user_id'] as int;

  static Future<AccessToken> getAccessToken(
    String apiKey,
    String apiSecretKey,
    Map<String, String> queries,
  ) async {
    final authParams = requestHeader(
      apiKey: apiKey,
      oauthToken: queries['oauth_token'],
      oauthVerifier: queries['oauth_verifier'],
    );
    final params = await httpPost(
      ACCESS_TOKEN_URI,
      authParams,
      apiKey,
      apiSecretKey,
    );
    final accessToken = AccessToken(params);
    return accessToken;
  }
}
