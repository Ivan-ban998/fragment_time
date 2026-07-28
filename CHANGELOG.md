# Fragment Time Changelog

## 2026-07-28 — 听一声 8 天连环坑 治本 + GitHub 治本 + 正式上线

### 🎯 听一声 "啥也没有" / "白屏" 8 天真凶 (治本)

**问题**: Scene.listen (听一声) 24 桶 100% `ContentType.audio`, 走 `_buildAudioEntry` (喜马拉雅入口卡, 在 hero 上面)。 该 widget 卡死 → hero 不可见 = "白屏"。 学/放松/动一动 24 桶是 article/video/card 混 → 不走 `_buildAudioEntry` → 正常显示。

**真凶定位**: 7/24 14:47 Brien "看不见" → 7/25-7/27 14 次盲改 (字体/布局/ScrollView/shader/OTF/LinearGradient/BackdropFilter/Navigator/容器/路由/结构/tofu/Roboto), 全失败。 7/28 12:16 Brien 一句 "**为何其他三个可以**" = 真线索, 让小 O 真对比 4 场景代码路径 → 找到唯一物理差别 (听一声专属 widget) → 1 次改对。

**修法** (commit `13d826d`):
```dart
if (_aiContentItem != null && _aiContentItem!.contentType == ContentType.audio && widget.scene != Scene.listen) ...[
  _buildAudioEntry(_aiContentItem!),
  SizedBox(height: 8 * _scale),
],
```
Scene.listen 跳过 `_buildAudioEntry`, 走 _buildHero 跟其他 3 场景同路径。

**SOUL 加新规则** (7/28):
- **#103** 修 bug 第一步 = 真对比多个相似路径找物理差别, 不是猜真凶
- **#104** "继续干" ≠ "再盲改 1 次", 改 UI 必有真诊断依据
- **#105** 主动短问 1 次就够, 2 次 = 骚扰

### 🌐 正式上线 content.soulvag.com

- DNS: `content.soulvag.com` → CF anycast (104.21.44.167 / 172.67.201.95) ✅
- CF Tunnel: `content.soulvag.com` → `http://localhost:7080` ✅ (沿用 `haisoul-prod-v2` tunnel, 沿用 alert 7/21 修)
- HTTPS: CF 边缘自带证书 ✅
- CF Access: "soulvag.com 全域" Bypass policy for content.soulvag.com (Public) ✅ (7/28 18:46 Brien 改)
- 公开访问: `https://content.soulvag.com/` HTTP 200 4.5s ✅

### 📦 GitHub 治本

- `fix/linear-gradient-full-cleanup` → `origin/dev` 推送 (15 commit, GHub SSH 限流 70h+ 沿用 7/18 解)
- `fix/linear-gradient-full-cleanup` → `origin/main` 强推 (替换 `46b88b9` 灾难版) ✅
- GitHub `main` = `13d826d` ✅ (公共 clone 默认看到完整版)
- GitHub `dev` = `13d826d` ✅
- 别名: 之前别人分析 GitHub 看到 `46b88b9` (只剩 home_stub 占位) = 已替换

### 🧹 打磨 (能干的都干了)

- `lib/services/bilibili_service.dart` 清 4 个诊断 debugPrint (业务 catch 兜底保留) — SOUL #25 #27
- `lib/services/content_aggregator.dart` 无 stub 残留 (干净) ✅
- `lib/services/tts_service.dart` + `tts_service_web.dart` silent-fail fallback 已 ok ✅
- `lib/services/share_service.dart` 三件套 (main + stub + web) conditional import 干净 ✅

### ❌ 没干 (列 TODO)

- **听一声真音频源** = NAS 上行不通国外 (NPR/BBC/Vox/RSSHub 全 timeout), 国内 podcast RSS 缺, 需付费 API (喜马拉雅/得到/听云)
- **云端 TTS 真接** = 现在浏览器 `window.speechSynthesis` 机械音, 接 Azure/阿里云/MiniMax 是大活
- **24 桶内容扩充 24 → 100+** = 内容运营, 不是代码
- **3 个 TODO 注解**: child HARD RULE stub (content_reader:149), ContentScreen 跳转优化 (content_reader:186), 接 LLM 二次调用 (content_screen:844)

### 📜 关键 commit

- `13d826d` fix(听一声): Scene.listen 跳过 _buildAudioEntry (不凑合) ← 治本
- `5ef451f` revert(scenes): 删 v2 听一声 试用入口, 4 场景回 v1 (回滚)
- `8b71bc4` fix(听一声 7 天 真凶): content_screen hero fontFamily 'Roboto' → null (后 revert)
- `bc02bcf` fix(听一声 7 天 真凶): app_theme fontFamily 'Roboto' → null (后 revert)
- `1c2146f` fix: LinearGradient 全清 + 听一声真凶 + 收藏搜索 + 顶栏统一
- `5f7d15f` WIP: 听一声 v10 玻璃不透明 + 深色文字 (老基线)

### 📊 沿用 alert

- **cloudflared-tunnel-dns-dead** (RESOLVED 7/21 12:18) ✅
- **GHub SSH 限流** (RESOLVED 7/18 22:00) ✅
- **8100-stale-port** (沿用 7/13)
- **haisoul.com / openclaw.haisoul.com TLS RST** (沿用 7/14)
- **snipe.vagtek.com DNS 不解** (沿用 7/21)
- **odoo-wangyi-atc-missing** (沿用 7/19)