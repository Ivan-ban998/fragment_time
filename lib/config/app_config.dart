import 'package:flutter/material.dart';
import '../models/models.dart';

enum BuildMode {
  domestic,
  global,
}

class AppConfig {
  final BuildMode mode;
  final String appName;
  final String packageSuffix;
  final List<ContentSource> availableSources;
  final String copyrightFooter;
  final bool showInternationalSources;

  const AppConfig({
    required this.mode,
    required this.appName,
    required this.packageSuffix,
    required this.availableSources,
    required this.copyrightFooter,
    required this.showInternationalSources,
  });

  static AppConfig get domestic => const AppConfig(
        mode: BuildMode.domestic,
        appName: '碎片时间',
        packageSuffix: '.domestic',
        availableSources: [
          ContentSource.ximalaya,
          ContentSource.lizhiFM,
          ContentSource.news36kr,
          ContentSource.zhihu,
        ],
        copyrightFooter: '©2024 碎片时间 | 内容版权归属原作者',
        showInternationalSources: false,
      );

  static AppConfig get global => const AppConfig(
        mode: BuildMode.global,
        appName: 'FragmentTime',
        packageSuffix: '.global',
        availableSources: [
          ContentSource.ximalaya,
          ContentSource.lizhiFM,
          ContentSource.news36kr,
          ContentSource.zhihu,
          ContentSource.applePodcasts,
          ContentSource.spotify,
          ContentSource.youtube,
          ContentSource.rss,
        ],
        copyrightFooter: '©2024 FragmentTime | Content copyright belongs to original creators',
        showInternationalSources: true,
      );
}
