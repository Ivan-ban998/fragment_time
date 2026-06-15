// 6/9 Sofa 启发：学习小组 service
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/study_group.dart';

class StudyGroupService {
  static const String _key = 'study_groups_v1';
  static final StudyGroupService instance = StudyGroupService._();
  StudyGroupService._();

  // 预制 3 个小组（避免 0 内容空城）
  List<StudyGroup> seedGroups() {
    final now = DateTime.now();
    return [
      StudyGroup(
        id: 'g_okr_weekly',
        name: 'OKR 周复盘',
        topic: '每周回顾 OKR，找问题',
        allowedRoles: {UserType.entrepreneur, UserType.officeWorker},
        memberIds: ['@小王', '@小李', '@小张', '@你'],
        currentContentIndex: 0,
        contentQueue: ['officeWorker_learn_1', 'officeWorker_learn_3', 'officeWorker_learn_5'],
        createdAt: now.subtract(const Duration(days: 7)),
        lastSessionAt: now.subtract(const Duration(days: 2)),
      ),
      StudyGroup(
        id: 'g_gaokao_math',
        name: '高考数学冲刺',
        topic: '5 分钟 1 道经典题',
        allowedRoles: {UserType.student},
        memberIds: ['@小红', '@小绿', '@你'],
        currentContentIndex: 0,
        contentQueue: ['student_learn_2', 'student_learn_4', 'student_learn_5'],
        createdAt: now.subtract(const Duration(days: 14)),
        lastSessionAt: now.subtract(const Duration(days: 1)),
      ),
      StudyGroup(
        id: 'g_douyin_creator',
        name: '抖音创作者互助',
        topic: '算法变了怎么办',
        allowedRoles: {UserType.entrepreneur, UserType.officeWorker},
        memberIds: ['@大V', '@小白', '@你'],
        currentContentIndex: 0,
        contentQueue: ['entrepreneur_learn_1', 'entrepreneur_listen_1'],
        createdAt: now.subtract(const Duration(days: 3)),
        lastSessionAt: now,
      ),
    ];
  }

  Future<List<StudyGroup>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      final seeds = seedGroups();
      await _save(seeds);
      return seeds;
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((m) => StudyGroup.fromJson(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return seedGroups();
    }
  }

  Future<List<StudyGroup>> getForRole(UserType role) async {
    final all = await getAll();
    return all.where((g) => g.allowedRoles.contains(role)).toList();
  }

  Future<void> _save(List<StudyGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final list = groups.map((g) => g.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  Future<void> advance(StudyGroup g) async {
    final all = await getAll();
    final idx = all.indexWhere((x) => x.id == g.id);
    if (idx < 0) return;
    final old = all[idx];
    all[idx] = StudyGroup(
      id: old.id,
      name: old.name,
      topic: old.topic,
      allowedRoles: old.allowedRoles,
      memberIds: old.memberIds,
      currentContentIndex: (old.currentContentIndex + 1) % old.contentQueue.length,
      contentQueue: old.contentQueue,
      createdAt: old.createdAt,
      lastSessionAt: DateTime.now(),
    );
    await _save(all);
  }

  // 6/10 加: 创建小组
  Future<StudyGroup> create({
    required String name,
    required String topic,
    required Set<UserType> allowedRoles,
    required String myHandle, // 创建者自己的 handle
    List<String>? contentQueue, // 初始内容队列
  }) async {
    final all = await getAll();
    final id = 'g_${DateTime.now().millisecondsSinceEpoch}';
    final group = StudyGroup(
      id: id,
      name: name,
      topic: topic,
      allowedRoles: allowedRoles,
      memberIds: [myHandle],
      currentContentIndex: 0,
      contentQueue: contentQueue ?? [],
      createdAt: DateTime.now(),
      lastSessionAt: DateTime.now(),
    );
    all.add(group);
    await _save(all);
    return group;
  }

  // 6/10 加: 加入小组 (我的handle追加到成员列表)
  Future<void> join(String groupId, String myHandle) async {
    final all = await getAll();
    final idx = all.indexWhere((x) => x.id == groupId);
    if (idx < 0) return;
    final old = all[idx];
    if (old.memberIds.contains(myHandle)) return;
    final newMembers = [...old.memberIds, myHandle];
    all[idx] = StudyGroup(
      id: old.id,
      name: old.name,
      topic: old.topic,
      allowedRoles: old.allowedRoles,
      memberIds: newMembers,
      currentContentIndex: old.currentContentIndex,
      contentQueue: old.contentQueue,
      createdAt: old.createdAt,
      lastSessionAt: DateTime.now(),
    );
    await _save(all);
  }

  // 6/10 加: 退出小组
  Future<void> leave(String groupId, String myHandle) async {
    final all = await getAll();
    final idx = all.indexWhere((x) => x.id == groupId);
    if (idx < 0) return;
    final old = all[idx];
    final newMembers = old.memberIds.where((m) => m != myHandle).toList();
    all[idx] = StudyGroup(
      id: old.id,
      name: old.name,
      topic: old.topic,
      allowedRoles: old.allowedRoles,
      memberIds: newMembers,
      currentContentIndex: old.currentContentIndex,
      contentQueue: old.contentQueue,
      createdAt: old.createdAt,
      lastSessionAt: DateTime.now(),
    );
    await _save(all);
  }

  // 6/10 加: 添加内容到小组 queue
  Future<void> addContent(String groupId, String contentId) async {
    final all = await getAll();
    final idx = all.indexWhere((x) => x.id == groupId);
    if (idx < 0) return;
    final old = all[idx];
    if (old.contentQueue.contains(contentId)) return;
    final newQueue = [...old.contentQueue, contentId];
    all[idx] = StudyGroup(
      id: old.id,
      name: old.name,
      topic: old.topic,
      allowedRoles: old.allowedRoles,
      memberIds: old.memberIds,
      currentContentIndex: old.currentContentIndex,
      contentQueue: newQueue,
      createdAt: old.createdAt,
      lastSessionAt: DateTime.now(),
    );
    await _save(all);
  }
}
