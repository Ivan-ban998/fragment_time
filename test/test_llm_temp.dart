import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  test('llm api key check', () async {
    const key = 'sk-cp-…4XV4';
    try {
      final r = await http.post(
        Uri.parse('https://api.minimaxi.com/v1/text/chatcompletion_v2'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode({
          'model': 'MiniMax-M2.7',
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
          'max_tokens': 30,
        }),
      ).timeout(Duration(seconds: 10));
      print('HTTP ${r.statusCode}');
      print('body: ${r.body.substring(0, r.body.length.clamp(0, 300))}');
    } catch (e) {
      print('ERR: $e');
    }
  });
}
