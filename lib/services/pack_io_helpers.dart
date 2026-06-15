import 'package:flutter/material.dart';
import 'local_subscription_service.dart';

/// 6/12 加: 收藏包导入/导出弹窗（提到 service 层，多处复用）
class PackIO {
  PackIO._();

  static Future<void> showExportDialog(BuildContext context, {required bool isEn}) async {
    final svc = LocalSubscriptionService.instance;
    final json = await svc.exportPack();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEn ? 'Copy this JSON' : '复制以下 JSON'),
        content: SizedBox(
          width: 600,
          child: SelectableText(json, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isEn ? 'Done' : '完成'),
          ),
        ],
      ),
    );
  }

  static Future<void> showImportDialog(BuildContext context, {required bool isEn, VoidCallback? onDone}) async {
    final controller = TextEditingController();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEn ? 'Paste JSON here' : '粘贴 JSON'),
        content: SizedBox(
          width: 600,
          child: TextField(
            controller: controller,
            maxLines: 12,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '{ "version": 1, "items": [...] }',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isEn ? 'Cancel' : '取消'),
          ),
          TextButton(
            onPressed: () async {
              final n = await LocalSubscriptionService.instance.importPack(controller.text);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(n > 0
                    ? (isEn ? 'Imported $n items' : '已导入 $n 项')
                    : (isEn ? 'Invalid JSON' : 'JSON 格式不对'))),
              );
              if (onDone != null) onDone();
            },
            child: Text(isEn ? 'Import' : '导入'),
          ),
        ],
      ),
    );
  }
}
