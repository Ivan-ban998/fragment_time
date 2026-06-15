// lib/widgets/quiz_panel.dart
// 6/11 B2: 测一测面板
// 老人小孩友好: 大按钮 / 中文 / 点开看答案
// 用法: 在 content_reader_screen 文章底部塞入

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/llm_service.dart';
import '../theme/app_theme.dart';

class QuizPanel extends StatefulWidget {
  final ContentItem item;
  final double scale;
  final String languageCode;

  const QuizPanel({
    super.key,
    required this.item,
    this.scale = 1.0,
    this.languageCode = 'zh',
  });

  @override
  State<QuizPanel> createState() => _QuizPanelState();
}

class _QuizPanelState extends State<QuizPanel> {
  List<QuizQuestion>? _questions;
  String? _error;
  bool _loading = false;
  final Set<int> _revealed = {}; // 已展示答案的题号

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final qs = await LlmService.generateQuiz(
        title: widget.item.title,
        description: widget.item.description,
        languageCode: widget.languageCode,
      );
      if (!mounted) return;
      setState(() {
        _questions = qs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final isEn = widget.languageCode == 'en';
    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header
          Row(
            children: [
              Icon(Icons.quiz, size: 20 * scale, color: Colors.amber.shade700),
              SizedBox(width: 8 * scale),
              Text(
                isEn ? 'Quick Check' : '测一测',
                style: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade900,
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            isEn
                ? 'AI makes 3 questions to help you remember.'
                : 'AI 出 3 道题，测一下你读进去了多少。',
            style: TextStyle(fontSize: 12 * scale, color: AppTheme.textLight),
          ),
          SizedBox(height: 12 * scale),
          // 折叠 / 加载
          if (_loading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * scale),
              child: Row(
                children: [
                  SizedBox(
                    width: 16 * scale,
                    height: 16 * scale,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8 * scale),
                  Text(
                    isEn ? 'AI is making questions...' : 'AI 出题中...',
                    style: TextStyle(fontSize: 13 * scale, color: AppTheme.textLight),
                  ),
                ],
              ),
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isEn ? 'Failed' : '出题失败'}：$_error',
                  style: TextStyle(fontSize: 12 * scale, color: Colors.red),
                ),
                SizedBox(height: 8 * scale),
                ElevatedButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(isEn ? 'Retry' : '重试'),
                ),
              ],
            )
          else if (_questions == null)
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(isEn ? 'Generate 3 questions' : '生成 3 道题'),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < _questions!.length; i++)
                  _buildQuestion(i, _questions![i], scale, isEn),
                SizedBox(height: 8 * scale),
                TextButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(isEn ? 'Regenerate' : '换一题'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuestion(int idx, QuizQuestion q, double scale, bool isEn) {
    final revealed = _revealed.contains(idx);
    return Container(
      margin: EdgeInsets.only(bottom: 12 * scale),
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${idx + 1}. ${q.question}',
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          SizedBox(height: 8 * scale),
          for (int c = 0; c < q.choices.length; c++)
            _buildChoice(idx, c, q, scale, isEn, revealed),
          if (revealed && q.explanation != null) ...[
            SizedBox(height: 8 * scale),
            Container(
              padding: EdgeInsets.all(8 * scale),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 14 * scale, color: Colors.green.shade700),
                  SizedBox(width: 4 * scale),
                  Expanded(
                    child: Text(
                      q.explanation!,
                      style: TextStyle(fontSize: 12 * scale, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoice(int qIdx, int cIdx, QuizQuestion q, double scale, bool isEn, bool revealed) {
    final isCorrect = cIdx == q.correctIndex;
    Color? bg;
    Color? borderColor;
    Widget? trailing;
    if (revealed) {
      if (isCorrect) {
        bg = Colors.green.withOpacity(0.1);
        borderColor = Colors.green;
        trailing = Icon(Icons.check_circle, size: 18 * scale, color: Colors.green);
      } else {
        borderColor = Colors.grey.shade300;
      }
    }
    return InkWell(
      onTap: revealed
          ? null
          : () {
              setState(() {
                _revealed.add(qIdx);
              });
            },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: EdgeInsets.only(bottom: 4 * scale),
        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
        decoration: BoxDecoration(
          color: bg ?? Colors.transparent,
          border: Border.all(color: borderColor ?? Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Container(
              width: 22 * scale,
              height: 22 * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: revealed && isCorrect
                    ? Colors.green
                    : Colors.grey.shade200,
              ),
              child: Text(
                String.fromCharCode(65 + cIdx), // A B C D
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: revealed && isCorrect ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                q.choices[cIdx],
                style: TextStyle(fontSize: 13 * scale, height: 1.3),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
