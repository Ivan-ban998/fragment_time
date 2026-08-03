// lib/services/web_host_stub.dart
// 6/11 条件 import stub: native 端直接 fallback
// 8/2 修正 NAS LAN IP: 192.168.1.20 → 192.168.1.2 (hostname -I 实测 第一个)
// 沿用 SOUL #127: 实际 IP 优先, fallback 兜底
String currentHostname() => '192.168.1.2';
