
import "package:flutter_test/flutter_test.dart";
import "package:fragment_time/services/content_aggregator.dart";
import "package:fragment_time/services/quote_related_engine.dart";
import "package:fragment_time/models/models.dart";
import "package:fragment_time/models/quote.dart";

void main() {
  test("8/16 莫愁前路 query 搜结果", () async {
    final agg = ContentAggregator();
    final r = await agg.searchContent("莫愁");
    print("\n=== searchContent 莫愁 ===");
    print("Count: ${r.length}");
    for (final it in r) {
      print("  ${it.title} (${it.source})");
    }
    
    print("\n=== QuoteRelatedEngine.findRelated 莫愁 ===");
    final quote = Quote(
      text: "莫愁前路无知己，天下谁人不识君。",
      author: "高适",
      source: "别董大",
      createdAt: DateTime(2026, 1, 1),
    );
    final related = await QuoteRelatedEngine.findRelated(
      quote: quote,
      userType: UserType.officeWorker,
      scene: Scene.learn,
      isEn: false,
      limit: 5,
    );
    print("Count: ${related.length}");
    for (final r in related) {
      print("  ${r.title} (${r.source}) score=${r.score} fromLlm=${r.fromLlm}");
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
