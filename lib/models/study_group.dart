// 6/9 Sofa 启发：学习小组（创业者 / 学生可用）
import 'package:flutter/material.dart';
import 'models.dart';

class StudyGroup {
  final String id;
  final String name;
  final String topic; // 例: "OKR 周复盘" / "高考数学"
  final Set<UserType> allowedRoles; // 哪些角色可以加入
  final List<String> memberIds; // 简化：用 nickname 列表
  final int currentContentIndex; // 组当前在读第几条
  final List<String> contentQueue; // 候选内容 id 列表
  final DateTime createdAt;
  final DateTime? lastSessionAt;

  const StudyGroup({
    required this.id,
    required this.name,
    required this.topic,
    required this.allowedRoles,
    this.memberIds = const [],
    this.currentContentIndex = 0,
    this.contentQueue = const [],
    required this.createdAt,
    this.lastSessionAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'topic': topic,
    'allowedRoles': allowedRoles.map((r) => r.name).toList(),
    'memberIds': memberIds,
    'currentContentIndex': currentContentIndex,
    'contentQueue': contentQueue,
    'createdAt': createdAt.toIso8601String(),
    'lastSessionAt': lastSessionAt?.toIso8601String(),
  };

  factory StudyGroup.fromJson(Map<String, dynamic> m) => StudyGroup(
    id: m['id'] as String,
    name: m['name'] as String,
    topic: m['topic'] as String,
    allowedRoles: (m['allowedRoles'] as List)
        .map((n) => UserType.values.firstWhere(
              (e) => e.name == n,
              orElse: () => UserType.student,
            ))
        .toSet(),
    memberIds: List<String>.from(m['memberIds'] ?? const []),
    currentContentIndex: (m['currentContentIndex'] ?? 0) as int,
    contentQueue: List<String>.from(m['contentQueue'] ?? const []),
    createdAt: DateTime.parse(m['createdAt'] as String),
    lastSessionAt: m['lastSessionAt'] != null
        ? DateTime.tryParse(m['lastSessionAt'] as String)
        : null,
  );
}
