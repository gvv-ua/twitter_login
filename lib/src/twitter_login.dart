import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:twitter_login/entity/auth_result.dart';
import 'package:twitter_login/entity/user.dart';
import 'package:twitter_login/schemes/access_token.dart';
import 'package:twitter_login/schemes/request_token.dart';
import 'package:twitter_login/src/auth_browser.dart';
import 'package:twitter_login/src/exception.dart';

/// The status after a Twitter login flow has completed.
enum TwitterLoginStatus {
  /// The login was successful and the user is now logged in.
  loggedIn,

  /// The user cancelled the login flow.
  cancelledByUser,

  /// The Twitter login completed with an error
  error,
}

///
class TwitterLogin {
  /// Consumer API key
  final String apiKey;

  /// Consumer API secret key
  final String apiSecretKey;

  /// Callback URL
  final String redirectURI;

  static const _channel = const MethodChannel('twitter_login');
  static final _eventChannel = EventChannel('twitter_login/event');
  static final Stream<dynamic> _eventStream = _eventChannel.receiveBroadcastStream();

  /// constructor
  TwitterLogin({
    required this.apiKey,
    required this.apiSecretKey,
    required this.redirectURI,
  });

  /// Logs the user
  /// Forces the user to enter their credentials to ensure the correct users account is authorized.
  Future<AuthResult> login({bool forceLogin = false}) async {
    String resultURI;
    RequestToken requestToken;
    try {
      requestToken = await RequestToken.getRequestToken(
        apiKey,
        apiSecretKey,
        redirectURI,
        forceLogin,
      );
    } on Exception {
      throw PlatformException(
        code: "400",
        message: "Failed to generate request token.",
        details: "Please check your APIKey or APISecret.",
      );
    }

    final uri = Uri.parse(redirectURI);
    final completer = Completer<String>();
    late StreamSubscription subscribe;

    if (Platform.isAndroid) {
      await _channel.invokeMethod('setScheme', uri.scheme);
      subscribe = _eventStream.listen((data) async {
        if (data['type'] == 'url') {
          completer.complete(data['url']?.toString());
        }
      });
    }

    final authBrowser = AuthBrowser(
      onClose: () {
        if (!completer.isCompleted) {
          completer.complete('');
        }
      },
    );

    try {
      if (Platform.isIOS) {
        /// Login to Twitter account with SFAuthenticationSession or ASWebAuthenticationSession.
        resultURI = await authBrowser.doAuth(requestToken.authorizeURI, uri.scheme);
      } else if (Platform.isAndroid) {
        // Login to Twitter account with chrome_custom_tabs.
        await authBrowser.open(requestToken.authorizeURI, uri.scheme);
        resultURI = await completer.future;

        if (resultURI.isEmpty) {
          throw CanceledByUserException();
        }
        subscribe.cancel();
      } else {
        throw UnsupportedError('Not supported by this os.');
      }
      // The user closed the browser
      if (resultURI.isEmpty) {
        throw CanceledByUserException();
      }
      final queries = Uri.splitQueryString(Uri.parse(resultURI).query);
      if (queries['error'] != null) {
        throw Exception('Error Response: ${queries['error']}');
      }

      // The user cancelled the login flow.
      if (queries['denied'] != null) {
        throw CanceledByUserException();
      }

      final accessToken = await AccessToken.getAccessToken(
        apiKey,
        apiSecretKey,
        queries,
      );

      final userData = await User.getUserData(
        apiKey,
        apiSecretKey,
        accessToken.authToken,
        accessToken.authTokenSecret,
      );

      return AuthResult(
        authToken: accessToken.authToken,
        authTokenSecret: accessToken.authTokenSecret,
        status: TwitterLoginStatus.loggedIn,
        errorMessage: '',
        user: userData,
      );
    } on CanceledByUserException {
      return AuthResult(
        authToken: null,
        authTokenSecret: null,
        status: TwitterLoginStatus.cancelledByUser,
        errorMessage: 'The user cancelled the login flow.',
        user: null,
      );
    } catch (error) {
      return AuthResult(
        authToken: null,
        authTokenSecret: null,
        status: TwitterLoginStatus.error,
        errorMessage: error.toString(),
        user: null,
      );
    }
  }
}
