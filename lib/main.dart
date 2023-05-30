import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:simple_gravatar/simple_gravatar.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final FlutterAppAuth appAuth = FlutterAppAuth();
const FlutterSecureStorage secureStorage = FlutterSecureStorage();

/// For a real-world app, this should be an Internet-facing URL to FusionAuth.
/// If you are running FusionAuth locally and just want to test the app, you can
/// specify a local IP address (if the device is connected to the same network
/// as the computer running FusionAuth) or even use ngrok to expose your
/// instance to the Internet temporarily.
const String FUSIONAUTH_DOMAIN = 'your-fusionauth-public-url';
const String FUSIONAUTH_SCHEME = 'https';
const String FUSIONAUTH_CLIENT_ID = 'e9fdb985-9173-4e01-9d73-ac2d60d1dc8e';

const String FUSIONAUTH_REDIRECT_URI =
    'com.fusionauth.flutterdemo://login-callback';
const String FUSIONAUTH_LOGOUT_REDIRECT_URI =
    'com.fusionauth.flutterdemo://logout-callback';
const String FUSIONAUTH_ISSUER = '$FUSIONAUTH_SCHEME://$FUSIONAUTH_DOMAIN';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String? errorMessage;
  String? name;
  String? picture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FusionAuth on Flutter ',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('FusionAuth on Flutter Demo'),
        ),
        body: Center(
          child: isBusy
              ? const CircularProgressIndicator()
              : isLoggedIn
                  ? Profile(logoutAction, name, picture)
                  : Login(loginAction, errorMessage),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> getUserDetails(String accessToken) async {
    final http.Response response = await http.get(
      Uri.parse('$FUSIONAUTH_SCHEME://$FUSIONAUTH_DOMAIN/oauth2/userinfo'),
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user details');
    }
  }

  Future<void> loginAction() async {
    setState(() {
      isBusy = true;
      errorMessage = '';
    });

    try {
      final AuthorizationTokenResponse? result = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          FUSIONAUTH_CLIENT_ID,
          FUSIONAUTH_REDIRECT_URI,
          issuer: FUSIONAUTH_ISSUER,
          scopes: <String>['openid', 'offline_access'],
          // promptValues: ['login']
        ),
      );
      if (result != null) {
        // final Map<String, Object> idToken = parseIdToken(result.idToken);
        final Map<String, dynamic> profile = await getUserDetails(result.accessToken!);

        debugPrint('response: $profile');
        await secureStorage.write(
            key: 'refresh_token', value: result.refreshToken);
        await secureStorage.write(
            key: 'id_token', value: result.idToken);
        var gravatar = Gravatar(profile['email']! as String);
        var url = gravatar.imageUrl(
          size: 100,
          defaultImage: GravatarImage.retro,
          rating: GravatarRating.pg,
          fileExtension: true,
        );
        setState(() {
          isBusy = false;
          isLoggedIn = true;
          name = profile['given_name']! as String;
          picture = url;
        });
      }
    } on Exception catch (e, s) {
      debugPrint('login error: $e - stack: $s');

      setState(() {
        isBusy = false;
        isLoggedIn = false;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> initAction() async {
    final String? storedRefreshToken =
        await secureStorage.read(key: 'refresh_token');
    if (storedRefreshToken == null) {
      return;
    }

    setState(() {
      isBusy = true;
    });

    try {
      final TokenResponse? response = await appAuth.token(TokenRequest(
        FUSIONAUTH_CLIENT_ID,
        FUSIONAUTH_REDIRECT_URI,
        issuer: FUSIONAUTH_ISSUER,
        refreshToken: storedRefreshToken,
      ));

      if (response != null) {
        // final Map<String, Object> idToken = parseIdToken(response.idToken);
        final Map<String, dynamic> profile = await getUserDetails(response.accessToken!);

        await secureStorage.write(key: 'refresh_token', value: response.refreshToken);
        var gravatar = Gravatar(profile['email']! as String);
        var url = gravatar.imageUrl(
          size: 100,
          defaultImage: GravatarImage.retro,
          rating: GravatarRating.pg,
          fileExtension: true,
        );
        setState(() {
          isBusy = false;
          isLoggedIn = true;
          name = profile['given_name']! as String;
          picture = url;
        });
      }
    } on Exception catch (e, s) {
      debugPrint('error on refresh token: $e - stack: $s');
      await logoutAction();
    }
  }

  Future<void> logoutAction() async {
    final String? storedIdToken = await secureStorage.read(key: 'id_token');
    if (storedIdToken == null) {
      debugPrint(
          'Could not retrieve id_token for actual logout. Deleting local cookies only...');
    } else {
      try {
        await appAuth.endSession(EndSessionRequest(
            idTokenHint: storedIdToken,
            postLogoutRedirectUrl: FUSIONAUTH_LOGOUT_REDIRECT_URI,
            issuer: FUSIONAUTH_ISSUER,
            allowInsecureConnections: FUSIONAUTH_SCHEME != 'https'));
      } catch (err) {
        debugPrint('logout error: $err');
      }
    }
    await secureStorage.deleteAll();
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }
}

class Login extends StatelessWidget {
  final Future<void> Function() loginAction;
  final String? loginError;

  const Login(this.loginAction, this.loginError, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ElevatedButton(
          onPressed: () async {
            await loginAction();
          },
          child: const Text('Login'),
        ),
        Text(loginError ?? ''),
      ],
    );
  }
}

class Profile extends StatelessWidget {
  final Future<void> Function() logoutAction;
  final String? name;
  final String? picture;

  const Profile(this.logoutAction, this.name, this.picture, {Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange, width: 4),
            shape: BoxShape.circle,
            image: (picture == null) ? null : DecorationImage(
              fit: BoxFit.fill,
              image: NetworkImage(picture!),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Name: $name'),
        const SizedBox(height: 48),
        ElevatedButton(
          onPressed: () async {
            await logoutAction();
          },
          child: const Text('Logout'),
        ),
      ],
    );
  }
}
