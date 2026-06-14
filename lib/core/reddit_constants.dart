/// Central place for Reddit OAuth + API constants.
///
/// Note: the client id, redirect uri and (optional) Giphy key are NOT compiled
/// in. They are entered by the user on the mandatory login screen and stored
/// securely at runtime. See [AppConfig] / [SecureStore].
class RedditConstants {
  RedditConstants._();

  /// App version (keep in sync with pubspec) + GitHub repo for in-app updates.
  static const String appVersion = '1.0.17';
  static const String githubRepo = 'bennybar/LuliReddit';

  // Hosts
  static const String authorizeUrl =
      'https://www.reddit.com/api/v1/authorize.compact';
  static const String accessTokenUrl =
      'https://www.reddit.com/api/v1/access_token';
  static const String oauthApiBase = 'https://oauth.reddit.com';

  // "Website session" fallback (no API key): we talk to the normal site, the
  // way a logged-in browser does. See docs/hydra-fallback.md.
  static const String webApiBase = 'https://www.reddit.com';
  static const String webLoginUrl = 'https://www.reddit.com/login';
  // A browser-like UA for the website-session mode.
  static const String webUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  // Our dedicated redirect URI. Distinct from Infinity's `infinity://localhost`.
  // The user must register this exact value at https://www.reddit.com/prefs/apps
  static const String defaultRedirectUri = 'luli://oauth';

  // Custom scheme used by flutter_web_auth_2 to capture the redirect.
  static const String callbackScheme = 'luli';


  // OAuth params
  static const String responseType = 'code';
  static const String duration = 'permanent';

  /// Scopes requested. Mirrors Infinity's full scope set so every planned
  /// feature (browsing, voting, saving, subscribing, messaging, submitting)
  /// works without re-authorization later.
  static const String scope =
      'identity edit flair history mysubreddits privatemessages read report '
      'save submit subscribe vote wikiread account';

  // Installed-app userless grant — used ONLY to validate that the entered
  // client id is a real, correctly-typed (installed app) credential before we
  // send the user through the browser login.
  static const String installedClientGrant =
      'https://oauth.reddit.com/grants/installed_client';
  static const String validationDeviceId = 'DO_NOT_TRACK_THIS_DEVICE';


  static const String grantTypeAuthorizationCode = 'authorization_code';
  static const String grantTypeRefreshToken = 'refresh_token';


  /// User-Agent. Reddit requires a unique, descriptive UA per its API rules.
  static String userAgent(String? username) {
    final who = (username == null || username.isEmpty) ? 'anonymous' : username;
    return 'android:com.bennybar.luli_for_reddit:1.0.17 (by /u/$who)';
  }
}