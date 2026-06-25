// lib/services/share_service_web.dart
// 6/8 加：内容分享（生成卡片图）
// 走 dart:html Blob + <a download> 触发浏览器下载（Web 唯一原生路径）
// 卡片图渲染 = OffscreenCanvas? Flutter web 没 — 退路：手画 CustomPainter 渲染到 Canvas

import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'analytics_service.dart';

class ShareService {
  static final ShareService instance = ShareService._();
  ShareService._();

  /// 6/8 分享：把 content item 渲染成 1080×1920 卡片图，下载到本地
  /// 失败回退：复制内容摘要到剪贴板
  Future<bool> shareContent(ContentItem item, {bool isEn = false, String handle = '@你'}) async {
    try {
      // 1. 渲染 widget 到 PNG
      final bytes = await _renderCard(item, isEn: isEn, handle: handle);
      // 2. 触发下载
      final filename = _filenameFor(item, isEn);
      _downloadBytes(bytes, filename);
      // 3. 埋点
      AnalyticsService.instance.track(
        AnalyticsService.EVT_SAVE, // 复用 EVT_SAVE 当 share? 单独 EVT_SHARE 更好
        props: {'id': item.id, 'type': item.contentType.name, 'action': 'share_card'},
      );
      return true;
    } catch (e) {
      // 失败：复制摘要到剪贴板
      await _copyFallback(item, isEn);
      return false;
    }
  }

  String _filenameFor(ContentItem item, bool isEn) {
    final safe = item.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'fragmenttime_${safe}.png';
  }

  Future<Uint8List> _renderCard(ContentItem item, {required bool isEn, String handle = '@你'}) async {
    // 渲染器：直接用 CustomPainter 画到 ui.Picture
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1080, 1920));
    _drawCard(canvas, Size(1080, 1920), item, isEn, handle);
    final picture = recorder.endRecording();
    final img = await picture.toImage(1080, 1920);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  void _drawCard(Canvas canvas, Size size, ContentItem item, bool isEn, String handle) {
    final w = size.width, h = size.height;

    // 1. 背景：紫渐变（与主 app 一致）
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6750A4), Color(0xFF8B5CF6)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bg);

    // 2. 顶部留白
    // 3. 中心白色卡
    final cardPadding = 80.0;
    final cardRect = Rect.fromLTWH(cardPadding, 200, w - 2 * cardPadding, h - 400);
    final cardPaint = Paint()..color = Colors.white;
    final cardRRect = RRect.fromRectAndRadius(cardRect, const Radius.circular(40));
    canvas.drawRRect(cardRRect, cardPaint);

    // 4. 卡片内文字布局
    // 顶部：来源 icon + 平台名
    _drawText(
      canvas,
      item.source.toUpperCase(),
      Offset(cardRect.left + 60, cardRect.top + 60),
      color: const Color(0xFF6750A4),
      size: 36,
      weight: FontWeight.w700,
    );

    // 5. 中部：title
    final titleMaxWidth = cardRect.width - 120;
    _drawTextWrapped(
      canvas,
      item.title,
      Offset(cardRect.left + 60, cardRect.top + 140),
      titleMaxWidth,
      color: const Color(0xFF222222),
      size: 64,
      weight: FontWeight.w800,
      maxLines: 4,
      lineHeight: 1.25,
    );

    // 6. 描述（如果有）
    if (item.description != null && item.description!.isNotEmpty) {
      _drawTextWrapped(
        canvas,
        item.description!,
        Offset(cardRect.left + 60, cardRect.top + 380),
        titleMaxWidth,
        color: const Color(0xFF666666),
        size: 36,
        weight: FontWeight.w400,
        maxLines: 4,
        lineHeight: 1.4,
      );
    }

    // 7. 底部水印
    // 6/25 昵称扩展: 分享者标记
    _drawText(
      canvas,
      isEn ? '$handle · Shared via Fragment Time' : '$handle · 分享自 碎片时间',
      Offset(cardPadding, h - 180),
      color: Colors.white.withOpacity(0.95),
      size: 30,
      weight: FontWeight.w600,
    );
    _drawText(
      canvas,
      isEn ? 'Fragment Time · fragmenttime.app' : '碎片时间 · fragmenttime.app',
      Offset(cardPadding, h - 130),
      color: Colors.white.withOpacity(0.9),
      size: 30,
      weight: FontWeight.w500,
    );
    _drawText(
      canvas,
      isEn ? '5-minute reads, on the go.' : '碎片时间，5分钟读完。',
      Offset(cardPadding, h - 80),
      color: Colors.white.withOpacity(0.7),
      size: 24,
      weight: FontWeight.w400,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w400,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  void _drawTextWrapped(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w400,
    int maxLines = 3,
    double lineHeight = 1.3,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          height: lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth);
    tp.paint(canvas, offset);
  }

  void _downloadBytes(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _copyFallback(ContentItem item, bool isEn) async {
    final text = '${item.title}\n${item.description ?? ''}\n${item.externalUrl ?? ''}';
    await Clipboard.setData(ClipboardData(text: text));
  }
}
