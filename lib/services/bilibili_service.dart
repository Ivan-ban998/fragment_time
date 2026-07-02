import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 7/2 B 站搜索结果 (视频优先 tab) 实时 API
/// 修 6/11 摆烂: 之前 search.bilibili.com/all?keyword= 跳搜索结果页 (次优)
/// 现在调 api.bilibili.com/x/web-interface/search/type?search_type=video 拿真 BV
class BilibiliVideoResult {
  final String bvid;
  final String title;
  final String author;
  final String duration; // "5:30"
  final int durationSec; // 秒
  final int play; // 播放量
  final String cover; // 封面 URL
  final String arcurl; // 视频页 URL (iframe 失败 fallback)

  const BilibiliVideoResult({
    required this.bvid,
    required this.title,
    required this.author,
    required this.duration,
    required this.durationSec,
    required this.play,
    required this.cover,
    required this.arcurl,
  });
}

class BilibiliService {
  static final BilibiliService instance = BilibiliService._();
  BilibiliService._();

  // 缓存: keyword → results (避免重复请求)
  final Map<String, List<BilibiliVideoResult>> _cache = {};
  // 缓存: keyword → 时间戳 (10 min TTL)
  final Map<String, DateTime> _cacheTime = {};

  static const _ttl = Duration(minutes: 10);
  static const _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

  /// 搜 B 站视频, 返回播放量 top N
  /// [keyword] 中文/英文都行, 内部 URL encode
  /// [limit] 默认 6 (Tinder 卡用), 上限 20 (B 站 API 单页最大)
  Future<List<BilibiliVideoResult>> searchVideos(String keyword, {int limit = 6}) async {
    if (keyword.trim().isEmpty) return [];

    final cacheKey = '$keyword|$limit';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final ts = _cacheTime[cacheKey];
      if (ts != null && DateTime.now().difference(ts) < _ttl) {
        return cached;
      }
    }

    try {
      final encoded = Uri.encodeComponent(keyword);
      final url = 'https://api.bilibili.com/x/web-interface/search/type'
          '?search_type=video&keyword=$encoded&page=1';
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('[bili] search http ${resp.statusCode}: ${keyword}');
        return _fallback(keyword);
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (data['code'] != 0) {
        debugPrint('[bili] search api err ${data['code']}: ${data['message']}');
        return _fallback(keyword);
      }

      final result = (data['data']?['result'] as List?) ?? [];
      final videos = <BilibiliVideoResult>[];
      for (final raw in result) {
        if (videos.length >= limit) break;
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final bvid = m['bvid'] as String?;
        final title = _stripHtml(m['title'] as String? ?? '');
        final author = m['author'] as String? ?? '';
        final play = (m['play'] as num?)?.toInt() ?? 0;
        if (bvid == null || bvid.isEmpty || title.isEmpty) continue;
        // 7/2: 排序按播放量 (B 站 API 默认按相关度, 实用要看播放量)
        videos.add(BilibiliVideoResult(
          bvid: bvid,
          title: title,
          author: author,
          duration: m['duration'] as String? ?? '',
          durationSec: (m['duration'] as String? ?? '0:00')
              .split(':')
              .fold<int>(0, (acc, p) => acc * 60 + (int.tryParse(p) ?? 0)),
          play: play,
          cover: _normalizeCover(m['pic'] as String? ?? ''),
          arcurl: 'https://www.bilibili.com/video/$bvid',
        ));
      }
      // 按播放量降序
      videos.sort((a, b) => b.play.compareTo(a.play));

      _cache[cacheKey] = videos;
      _cacheTime[cacheKey] = DateTime.now();
      debugPrint('[bili] search "${keyword}" → ${videos.length} videos, top: ${videos.first.title} (${videos.first.play}播放)');
      return videos;
    } catch (e) {
      debugPrint('[bili] search exception: $e');
      return _fallback(keyword);
    }
  }

  /// B 站封面 URL 是 //i2.hdslb.com 开头, Flutter 网络要 https://
  String _normalizeCover(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('http://')) return url.replaceFirst('http://', 'https://');
    return url;
  }

  /// 7/2: 过滤 B 站 API 返回的 <em class="keyword"> 标签
  String _stripHtml(String s) {
    return s
        .replaceAll('<em class="keyword">', '')
        .replaceAll('</em>', '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  /// API 失败兜底: 返回空 (让 UI 显示搜索页链接, 不卡住)
  List<BilibiliVideoResult> _fallback(String keyword) {
    debugPrint('[bili] fallback to empty for: $keyword');
    return [];
  }
}