import 'dart:io';
import 'package:flutter/material.dart';
import 'package:github_client/github_oauth_credentials.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:url_launcher/url_launcher.dart';

final _authorizationEndpoint =
    Uri.parse('https://github.com/login/oauth/authorize');
final _tokenEndpoint = Uri.parse('https://github.com/login/oauth/access_token');

typedef AuthenticatedBuilder = Widget Function(
    BuildContext context, oauth2.Client client);

class GithubLoginWidget extends StatefulWidget {
  const GithubLoginWidget(
      {required this.builder,
      required this.githubClientId,
      required this.githubClientSecret,
      required this.githubScopes,
      Key? key})
      : super(key: key);

  final AuthenticatedBuilder builder;
  final String githubClientId;
  final String githubClientSecret;
  final List<String> githubScopes;

  @override
  State<GithubLoginWidget> createState() => _GithubLoginWidgetState();
}

class _GithubLoginWidgetState extends State<GithubLoginWidget> {
  HttpServer? _redirectServer;
  oauth2.Client? _client;

  Future<void> _redirect(Uri authorizationUrl) async {
    var url = authorizationUrl.toString();
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw GithubLoginException('Could not launch $url');
    }
  }

  Future<Map<String, String>> _listen() async {
    var request = await _redirectServer!.first;
    var params = request.uri.queryParameters;

    request.response.statusCode = 200;
    request.response.headers.set('Content-type', 'text/plain');
    request.response.writeln('Authenticated! You can close this tab.');

    await request.response.close();
    await _redirectServer!.close();

    _redirectServer = null;

    return params;
  }

  Future<oauth2.Client> _getOAuth2Client(Uri redirectUrl) async {
    if (widget.githubClientId.isEmpty || githubClientSecret.isEmpty) {
      throw const GithubLoginException(
          'githubClientId and githubClientSecret must not be empty. '
          'See `lib/github_oauth_credentials.dart` for more detail.');
    }

    var grant = oauth2.AuthorizationCodeGrant(
      widget.githubClientId,
      _authorizationEndpoint,
      _tokenEndpoint,
      secret: widget.githubClientSecret,
      httpClient: _JsonAcceptingHttpClient(),
    );

    var authorizationUrl =
        grant.getAuthorizationUrl(redirectUrl, scopes: widget.githubScopes);

    await _redirect(authorizationUrl);
    var responseQueryParameters = await _listen();
    var client =
        await grant.handleAuthorizationResponse(responseQueryParameters);

    return client;
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    if (client != null) {
      return widget.builder(context, client);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Github Login'),
      ),
      body: Center(
        child: ElevatedButton(
          child: const Text('Login to Github'),
          onPressed: () async {
            await _redirectServer?.close();

            // Bind to an ephemeral port on localhost
            _redirectServer = await HttpServer.bind('localhost', 0);
            var authenticatedHttpClient = await _getOAuth2Client(
                Uri.parse('http://localhost:${_redirectServer!.port}/auth'));

            setState(() {
              _client = authenticatedHttpClient;
            });
          },
        ),
      ),
    );
  }
}

class _JsonAcceptingHttpClient extends http.BaseClient {
  final _httpClient = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Accept'] = 'application/json';
    return _httpClient.send(request);
  }
}

class GithubLoginException implements Exception {
  const GithubLoginException(this.message);
  final String message;
  @override
  String toString() => message;
}
