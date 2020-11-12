import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:simple_gravatar/simple_gravatar.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final FlutterAppAuth appAuth = FlutterAppAuth();
const FlutterSecureStorage secureStorage = FlutterSecureStorage();

const String FUSION_AUTH_DOMAIN = '1a5321098cb0.ngrok.io';
const String FUSION_AUTH_CLIENT_ID = '7e3637e8-723a-42d6-9d1d-5cb36128d6f1';
const String FUSION_AUTH_CLIENT_SECRET =
    'hQ7s4MJIHIyk7iqbZ0082Q020RT9EZYtfBrah1v3a4A';
const String FUSION_AUTH_REDIRECT_URI =
    'com.fusionauth.flutterdemo://login-callback';
const String FUSION_AUTH_ISSUER = 'https://$FUSION_AUTH_DOMAIN';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String errorMessage;
  String name;
  String picture;

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

  Future<Map<String, Object>> getUserDetails(String accessToken) async {
    const String url = 'https://$FUSION_AUTH_DOMAIN/oauth2/userinfo';
    final http.Response response = await http.get(
      url,
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
      final AuthorizationTokenResponse result =
          await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          FUSION_AUTH_CLIENT_ID,
          FUSION_AUTH_REDIRECT_URI,
          clientSecret: FUSION_AUTH_CLIENT_SECRET,
          issuer: 'https://$FUSION_AUTH_DOMAIN',
          scopes: <String>['offline_access'],
          // promptValues: ['login']
        ),
      );
      log('data: $result');
      // final Map<String, Object> idToken = parseIdToken(result.idToken);
      final Map<String, Object> profile =
          await getUserDetails(result.accessToken);

      debugPrint('response: $profile');
      await secureStorage.write(
          key: 'refresh_token', value: result.refreshToken);
      var gravatar = Gravatar(profile['email']);
      var url = gravatar.imageUrl(
        size: 100,
        defaultImage: GravatarImage.retro,
        rating: GravatarRating.pg,
        fileExtension: true,
      );
      setState(() {
        isBusy = false;
        isLoggedIn = true;
        name = profile['given_name'];
        picture = url;
      });
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
    final String storedRefreshToken =
        await secureStorage.read(key: 'refresh_token');
    if (storedRefreshToken == null) return;

    setState(() {
      isBusy = true;
    });

    try {
      final TokenResponse response = await appAuth.token(TokenRequest(
        FUSION_AUTH_CLIENT_ID,
        FUSION_AUTH_REDIRECT_URI,
        issuer: FUSION_AUTH_ISSUER,
        refreshToken: storedRefreshToken,
      ));

      // final Map<String, Object> idToken = parseIdToken(response.idToken);
      final Map<String, Object> profile =
          await getUserDetails(response.accessToken);

      await secureStorage.write(
          key: 'refresh_token', value: response.refreshToken);
      var gravatar = Gravatar(profile['email']);
      var url = gravatar.imageUrl(
        size: 100,
        defaultImage: GravatarImage.retro,
        rating: GravatarRating.pg,
        fileExtension: true,
      );
      setState(() {
        isBusy = false;
        isLoggedIn = true;
        name = profile['given_name'];
        picture = url;
      });
    } on Exception catch (e, s) {
      debugPrint('error on refresh token: $e - stack: $s');
      await logoutAction();
    }
  }

  Future<void> logoutAction() async {
    await secureStorage.delete(key: 'refresh_token');
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }
}

class Login extends StatelessWidget {
  final Future<void> Function() loginAction;
  final String loginError;

  const Login(this.loginAction, this.loginError, {Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        RaisedButton(
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
  final String name;
  final String picture;

  const Profile(this.logoutAction, this.name, this.picture, {Key key})
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
            image: DecorationImage(
              fit: BoxFit.fill,
              image: NetworkImage(picture ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Name: $name'),
        const SizedBox(height: 48),
        RaisedButton(
          onPressed: () async {
            await logoutAction();
          },
          child: const Text('Logout'),
        ),
      ],
    );
  }
}
