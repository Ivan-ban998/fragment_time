// ignore_for_file: avoid_print
// 8/28 P40-4 沿 SOUL #189: ContentItem toJson/fromJson 单元测试
//   验证 P31 字段完整性 + round-trip 不丢字段
// 跑法: flutter test test/content_item_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fragment_time/models/models.dart';

void main() {
  test('ContentItem.toJson 包含所有 14 字段', () {
    final item = ContentItem(
      id: 'student_learn_1',
      title: '高考冲刺',
      description: '5 分钟真题拆解',
      duration: '5min',
      source: 'sspai',
      sourceType: ContentSource.news36kr,
      contentType: ContentType.article,
    );
    final json = item.toJson();
    print('ContentItem.toJson keys: ${json.keys.toList()}');
    expect(json['id'], 'student_learn_1');
    expect(json['title'], '高考冲刺');
    expect(json['description'], '5 分钟真题拆解');
    expect(json['source'], 'sspai');
    expect(json['contentType'], 'article');
  });

  test('ContentItem.fromJson 兜底默认值', () {
    // 8/28 P40-4: 缺失字段用默认值 (沿 #137 真凶链, 旧数据兼容)
    final item = ContentItem.fromJson({});
    print('empty json → id="${item.id}" title="${item.title}"');
    expect(item.id, '');
    expect(item.title, '');
    expect(item.contentType, ContentType.article); // default
    expect(item.sourceType, ContentSource.news36kr); // default
    expect(item.priceType, ContentPriceType.free); // default
    expect(item.progress, 0);
  });

  test('ContentItem round-trip 不丢字段', () {
    final orig = ContentItem(
      id: 'office_relax_3',
      title: '午休冥想',
      description: '放松一下',
      duration: '5min',
      source: '36氪',
      sourceType: ContentSource.news36kr,
      contentType: ContentType.audio,
      progress: 75,
      externalUrl: 'https://example.com/podcast',
      priceType: ContentPriceType.free,
    );
    final json = orig.toJson();
    final back = ContentItem.fromJson(json);
    expect(back.id, orig.id);
    expect(back.title, orig.title);
    expect(back.duration, orig.duration);
    expect(back.source, orig.source);
    expect(back.contentType, orig.contentType);
    expect(back.progress, orig.progress);
    expect(back.externalUrl, orig.externalUrl);
    print('✓ round-trip OK');
  });
}