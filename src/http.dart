import 'dart:async';
import 'dart:convert';
import 'dart:io';

final Authenticator authenticator = new Authenticator();

class Authenticator {
  static const clientId = 'mobileapp';
  static const clientSecret = 'secret';
  static const authority = 'fastpayidsbeta-staging.azurewebsites.net';

  String _token;
  String _sessionToken;

  final HttpClient _client = new HttpClient();

  String get sessionToken => _sessionToken;

  Future<String> _getToken(String formData) async {
    var req = await _client.postUrl(new Uri.https(authority, '/connect/token'));
    req
      ..headers.contentType = new ContentType(
          'application', 'x-www-form-urlencoded',
          charset: 'utf-8')
      ..write(formData);

    var resp = await req.close();

    Map data = await _parseData(resp);
    return data["access_token"];
  }

  Future<Map> _parseData(HttpClientResponse response) async {
    if (response.statusCode == HttpStatus.NOT_FOUND) {
      throw 'User does not exist';
    }

    if (response.statusCode >= 400) {
      print(response.reasonPhrase);
      Map error = await _extractJsonObject(response);
      String errorMessage = error['error'] == 'invalid_grant'
          ? 'Invalid PIN'
          : 'Unable to process';
      throw '$errorMessage';
    }

    return await _extractJsonObject(response);
  }

  Future<Object> _extractJsonObject(HttpClientResponse response) =>
      response.transform(utf8.decoder).transform(json.decoder).first;

  Future<String> getToken({bool useCached: true}) async {
    if (_token != null && useCached) return _token;

    _token = await _getToken('grant_type=client_credentials&'
        'client_id=$clientId&'
        'client_secret=$clientSecret');

    return _token;
  }

  Future<String> getSessionToken(String userId, String pin, String deviceId,
      {bool useCached: true}) async {
    if (_sessionToken != null && useCached) return _sessionToken;

    _sessionToken = await _getToken('grant_type=password&'
        'client_id=$clientId&'
        'client_secret=$clientSecret&'
        'username=$userId&'
        'password=$pin&'
        'device_id=$deviceId');

    return _sessionToken;
  }
}

class HttpDataSource implements DataSource {
  static const String _authority = 'fastpayapibeta-staging.azurewebsites.net';
  static const String _baseApi = '/api/v1.0';

  var client = new HttpClient();

  @override
  Future<Map> get(String entity, String id, {String token}) async {
    Uri uri = new Uri.https(_authority, '$_baseApi/$entity/$id');
    var request = await client.getUrl(uri);

    if (token != null) {
      request.headers.add(HttpHeaders.AUTHORIZATION, 'Bearer $token');
    }

    var response = await request.close();

    _checkAndThrowError(response);

    return await _extractJson(response).first;
  }

  @override
  Future<Stream<Object>> getList(String entity,
      {String token, Map<String, String> queryParameters}) async {
    Uri uri = new Uri.https(_authority, '$_baseApi/$entity', queryParameters);
    var request = await client.getUrl(uri);

    if (token != null) {
      request.headers.add(HttpHeaders.AUTHORIZATION, 'Bearer $token');
    }

    var response = await request.close();

    _checkAndThrowError(response);

    return _extractJson(response).expand((jsonBody) => jsonBody as List);
  }

  @override
  Future<Map> post(String path,
      {String token, dynamic body, bool parseResponse: false}) async {
    Uri uri = new Uri.https(_authority, '$_baseApi/$path');
    var request =
        await client.postUrl(uri).timeout(const Duration(seconds: 90));

    if (token != null) {
      request.headers.add(HttpHeaders.AUTHORIZATION, 'Bearer $token');
    }

    if (body != null) {
      request.headers.contentType = ContentType.JSON;
      request.write(json.encode(body));
    }

    var response = await request.close();

    _checkAndThrowError(response);

    if (parseResponse) {
      return await _extractJson(response).first;
    }

    return {};
  }

  void _checkAndThrowError(HttpClientResponse response) {
    if (response.statusCode == HttpStatus.NOT_FOUND) {
      throw new ResourceNotFoundException();
    } else if (response.statusCode >= 400) {
      print(response.reasonPhrase);
      throw new HttpException('Unable to process request');
    }
  }

  Stream<Object> _extractJson(HttpClientResponse response) {
    return response.transform(utf8.decoder).transform(json.decoder);
  }
}

abstract class DataSource {
  Future<Map> get(String entity, String id, {String token});
  Future<Stream<Object>> getList(String entity,
      {String token, Map<String, String> queryParameters});
  Future<Map> post(String path, {String token});
}

class ResourceNotFoundException implements Exception {
  ResourceNotFoundException();
}
