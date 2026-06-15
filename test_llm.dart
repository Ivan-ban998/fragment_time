import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const key = 'sk-cp-…4XV4';
void main() async {
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
          {'role': 'user', 'content': '你好，请用一句话回复。'}
        ],
        'max_tokens': 50,
      }),
    ).timeout(Duration(seconds: 10));
    print('HTTP ${r.statusCode}');
    print('body (first 500): ${r.body.substring(0, r.body.length.clamp(0, 500))}');
  } catch (e) {
    print('ERR: $e');
  }
}
