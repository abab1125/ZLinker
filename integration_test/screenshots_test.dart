// Store screenshot capture: pumps the real pages with seeded fake data and
// captures full-screen shots for App Store / Play listings.
//
// Run on a device/simulator via flutter drive (writes PNGs through the
// test_driver/integration_test.dart onScreenshot callback):
//
//   ZLINKER_SHOT_DIR=docs/screenshots flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart -d <device> \
//     --dart-define=SHOT_LOCALE=en-US
//
// SHOT_LOCALE picks the app UI language AND the seeded data language
// (zh-CN default, en-US for the English set); each capture is suffixed
// -zh / -en. Resize to store sizes afterwards (see docs/store/SCREENSHOTS.md).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zlinker/state/device_session.dart';
import 'package:zlinker/state/device_store.dart';
import 'package:zlinker/state/scheduled_store.dart';
import 'package:zlinker/ui/automations_page.dart';
import 'package:zlinker/ui/chat/chat_page.dart';
import 'package:zlinker/ui/devices_page.dart';
import 'package:zlinker/ui/task_list_page.dart';
import 'package:zlinker/ui/theme.dart';
import 'package:zlinker/ui/ui_settings.dart';

import '../test/helpers/fake_device_session.dart';

const _shotLocale = String.fromEnvironment('SHOT_LOCALE', defaultValue: 'zh-CN');
final _isEn = _shotLocale.startsWith('en');
final _suffix = _isEn ? '-en' : '-zh';

const _urlA =
    'https://zcode.z.ai/remote/v4?sid=abc&hash=xyz&t=123&mid=m1&name=Mac%20Studio&app_version=3.8.1';
const _urlB =
    'https://zcode.z.ai/remote/v4?sid=def&hash=uvw&t=124&mid=m2&name=ThinkPad&app_version=3.8.1';

final _now = DateTime.now().millisecondsSinceEpoch;

final _sessions = _isEn
    ? [
        {
          'sessionId': 'sess_shot_1',
          'title': 'ZLinker store copy & screenshots',
          'phase': 'running',
          'lastAssistantPreview':
              'Screenshot tests passed — generating bilingual store assets…',
          'lastActivityAt': _now - 1000 * 62,
          'pinned': true,
        },
        {
          'sessionId': 'sess_shot_2',
          'title': 'Deep dive: GitHub description generation',
          'phase': 'completedSuccess',
          'lastAssistantPreview':
              'Full analysis delivered, three conclusions.',
          'lastActivityAt': _now - 1000 * 60 * 41,
        },
        {
          'sessionId': 'sess_shot_3',
          'title': 'Off-peak: daily build patrol report',
          'phase': 'completedSuccess',
          'lastAssistantPreview': 'Report generated, 4 findings.',
          'lastActivityAt': _now - 1000 * 60 * 60 * 5,
        },
      ]
    : [
        {
          'sessionId': 'sess_shot_1',
          'title': 'ZLinker 商店页文案与截图',
          'phase': 'running',
          'lastAssistantPreview': '截图测试已通过，正在生成双语言商店素材…',
          'lastActivityAt': _now - 1000 * 62,
          'pinned': true,
        },
        {
          'sessionId': 'sess_shot_2',
          'title': '深度解析 GitHub 描述生成',
          'phase': 'completedSuccess',
          'lastAssistantPreview': '完整分析已输出，共三个结论。',
          'lastActivityAt': _now - 1000 * 60 * 41,
        },
        {
          'sessionId': 'sess_shot_3',
          'title': '闲时任务：每日构建巡检报告',
          'phase': 'completedSuccess',
          'lastAssistantPreview': '巡检报告已生成，共 4 项结论。',
          'lastActivityAt': _now - 1000 * 60 * 60 * 5,
        },
      ];

final _workspaces = [
  {'workspacePath': '/Users/dev/ZLinker', 'workspaceIdentity': 'ZLinker'},
];

/// Second workspace + relay overview tasks (`Dg`): feed the merged task
/// data source (non-active workspace rows, archive view, tags).
final _workspacesRich = [
  {'workspacePath': '/Users/dev/ZLinker', 'workspaceIdentity': 'ZLinker'},
  {
    'workspacePath': '/Users/dev/api-server',
    'workspaceIdentity': 'api-server',
    'workspacePurpose': 'project',
  },
];

final _relayTasks = _isEn
    ? [
        {
          'taskId': 'sess_shot_1',
          'title': 'ZLinker store copy & screenshots',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'running',
          'pinned': true,
          'updatedAt': _now - 1000 * 62,
        },
        {
          'taskId': 'sess_shot_2',
          'title': 'Deep dive: GitHub description generation',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 41,
        },
        {
          'taskId': 'sess_shot_3',
          'title': 'Off-peak: daily build patrol report',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 60 * 5,
        },
        {
          'taskId': 'sess_await',
          'title': 'Deploy staging after review',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'idle',
          'updatedAt': _now - 1000 * 60 * 12,
        },
        {
          'taskId': 'sess_unread',
          'title': 'Refactor the notifier registry',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'unreadAt': _now - 1000 * 60 * 30,
          'updatedAt': _now - 1000 * 60 * 30,
        },
        {
          'taskId': 'relay_task_1',
          'title': 'Rate-limit middleware for the public API',
          'workspacePath': '/Users/dev/api-server',
          'workspaceIdentity': 'api-server',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 90,
        },
        {
          'taskId': 'relay_task_2',
          'title': 'Migrate webhook logs to the cold table',
          'workspacePath': '/Users/dev/api-server',
          'workspaceIdentity': 'api-server',
          'displayStatus': 'idle',
          'archived': true,
          'updatedAt': _now - 1000 * 60 * 60 * 26,
        },
        {
          'taskId': 'relay_task_3',
          'title': 'Audit CI cache keys',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'error',
          'archived': true,
          'updatedAt': _now - 1000 * 60 * 60 * 40,
        },
      ]
    : [
        {
          'taskId': 'sess_shot_1',
          'title': 'ZLinker 商店页文案与截图',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'running',
          'pinned': true,
          'updatedAt': _now - 1000 * 62,
        },
        {
          'taskId': 'sess_shot_2',
          'title': '深度解析 GitHub 描述生成',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 41,
        },
        {
          'taskId': 'sess_shot_3',
          'title': '闲时任务：每日构建巡检报告',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 60 * 5,
        },
        {
          'taskId': 'sess_await',
          'title': '评审后部署到预发环境',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'idle',
          'updatedAt': _now - 1000 * 60 * 12,
        },
        {
          'taskId': 'sess_unread',
          'title': '重构通知器注册表',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'completed',
          'unreadAt': _now - 1000 * 60 * 30,
          'updatedAt': _now - 1000 * 60 * 30,
        },
        {
          'taskId': 'relay_task_1',
          'title': '公网 API 限流中间件',
          'workspacePath': '/Users/dev/api-server',
          'workspaceIdentity': 'api-server',
          'displayStatus': 'completed',
          'updatedAt': _now - 1000 * 60 * 90,
        },
        {
          'taskId': 'relay_task_2',
          'title': 'Webhook 日志迁移到冷表',
          'workspacePath': '/Users/dev/api-server',
          'workspaceIdentity': 'api-server',
          'displayStatus': 'idle',
          'archived': true,
          'updatedAt': _now - 1000 * 60 * 60 * 26,
        },
        {
          'taskId': 'relay_task_3',
          'title': '审计 CI 缓存键',
          'workspacePath': '/Users/dev/ZLinker',
          'workspaceIdentity': 'ZLinker',
          'displayStatus': 'error',
          'archived': true,
          'updatedAt': _now - 1000 * 60 * 60 * 40,
        },
      ];

/// Live-index extras: a task waiting for permission confirmation and an
/// unread one — the official 等待确认 tag + unread dot.
final _extraSessions = _isEn
    ? [
        {
          'sessionId': 'sess_await',
          'title': 'Deploy staging after review',
          'phase': 'completedInterrupted',
          'pendingInteraction': {'kind': 'permission'},
          'lastActivityAt': _now - 1000 * 60 * 12,
        },
        {
          'sessionId': 'sess_unread',
          'title': 'Refactor the notifier registry',
          'phase': 'completedSuccess',
          'unreadAt': _now - 1000 * 60 * 30,
          'lastActivityAt': _now - 1000 * 60 * 30,
        },
      ]
    : [
        {
          'sessionId': 'sess_await',
          'title': '评审后部署到预发环境',
          'phase': 'completedInterrupted',
          'pendingInteraction': {'kind': 'permission'},
          'lastActivityAt': _now - 1000 * 60 * 12,
        },
        {
          'sessionId': 'sess_unread',
          'title': '重构通知器注册表',
          'phase': 'completedSuccess',
          'unreadAt': _now - 1000 * 60 * 30,
          'lastActivityAt': _now - 1000 * 60 * 30,
        },
      ];

/// Seeded server-side automations for the automations page capture.
final _automations = _isEn
    ? [
        {
          'automationId': 'auto-1',
          'title': 'Daily build patrol',
          'prompt': 'Inspect last night\'s build artifacts, summarize failing cases and post the report.',
          'cronExpr': '0 2 * * *',
          'enabled': true,
          'nextRunAt': _now + 1000 * 60 * 60 * 3,
          'lastRunAt': _now - 1000 * 60 * 60 * 21,
          'runCount': 42,
        },
        {
          'automationId': 'auto-2',
          'title': 'Weekly review digest',
          'prompt': 'Compile finished sessions of the week into a highlights brief.',
          'cronExpr': '0 16 * * 5',
          'enabled': true,
          'nextRunAt': _now + 1000 * 60 * 60 * 30,
          'lastRunAt': _now - 1000 * 60 * 60 * 24 * 4,
          'runCount': 12,
        },
        {
          'automationId': 'auto-3',
          'title': 'Dependency security sweep',
          'prompt': 'Scan pubspec.lock for advisories and open follow-up tasks.',
          'cronExpr': '0 9 * * 1',
          'enabled': false,
          'lastRunAt': _now - 1000 * 60 * 60 * 24 * 9,
          'runCount': 3,
        },
      ]
    : [
        {
          'automationId': 'auto-1',
          'title': '每日构建巡检',
          'prompt': '巡检昨晚的构建产物，汇总失败用例并生成报告。',
          'cronExpr': '0 2 * * *',
          'enabled': true,
          'nextRunAt': _now + 1000 * 60 * 60 * 3,
          'lastRunAt': _now - 1000 * 60 * 60 * 21,
          'runCount': 42,
        },
        {
          'automationId': 'auto-2',
          'title': '每周回顾摘要',
          'prompt': '把本周完成的会话整理成要点简报。',
          'cronExpr': '0 16 * * 5',
          'enabled': true,
          'nextRunAt': _now + 1000 * 60 * 60 * 30,
          'lastRunAt': _now - 1000 * 60 * 60 * 24 * 4,
          'runCount': 12,
        },
        {
          'automationId': 'auto-3',
          'title': '依赖安全巡检',
          'prompt': '扫描 pubspec.lock 的安全通告并创建跟进任务。',
          'cronExpr': '0 9 * * 1',
          'enabled': false,
          'lastRunAt': _now - 1000 * 60 * 60 * 24 * 9,
          'runCount': 3,
        },
      ];

final _chatTitle =
    _isEn ? 'ZLinker store copy & screenshots' : 'ZLinker 商店页文案与截图';

final _chatRows = _isEn
    ? [
        {'rowId': 1, 'kind': 'userInput', 'text': 'Regroup the task list by pinned section'},
        {
          'rowId': 2,
          'kind': 'assistantText',
          'text': 'Done:\n\n- **Pinned** group now leads the list\n- Each group sorted by latest activity\n- Running tasks show a live status dot',
        },
        {
          'rowId': 3,
          'kind': 'turnHeader',
          'state': 'completedSuccess',
          'activeMs': 48000,
          'fileChanges': {'files': 2, 'additions': 64, 'deletions': 11},
        },
      ]
    : [
        {'rowId': 1, 'kind': 'userInput', 'text': '帮我把任务列表按置顶分组重排'},
        {
          'rowId': 2,
          'kind': 'assistantText',
          'text': '已完成重排：\n\n- **已置顶** 分组现在排在最前\n- 每组内按最近活动时间排序\n- 运行中的任务带实时状态点',
        },
        {
          'rowId': 3,
          'kind': 'turnHeader',
          'state': 'completedSuccess',
          'activeMs': 48000,
          'fileChanges': {'files': 2, 'additions': 64, 'deletions': 11},
        },
      ];

final _captureKey = GlobalKey();

Widget _wrap(Widget child, ThemeController theme, UiSettings ui) =>
    // The boundary wraps the WHOLE MaterialApp: modal sheets, dialogs and
    // popup menus render in the navigator's overlay, above `home`.
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.dark,
        builder: (context, child) =>
            UiSettingsProvider(settings: ui, child: child!),
        home: child,
      ),
    );

final _phoneKey = GlobalKey();

/// Rasterize the phone-shaped viewport ([_phoneKey]).
Future<void> _capturePhone(WidgetTester tester, String name) async {
  final boundary =
      _phoneKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir =
      Directory(Platform.environment['ZLINKER_SHOT_DIR'] ?? 'docs/screenshots');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.png').writeAsBytes(data!.buffer.asUint8List());
  await tester.pump(const Duration(milliseconds: 100));
}

/// Desktop fallback for `binding.takeScreenshot` (its platform channel is
/// mobile-only): rasterize the app RepaintBoundary and write the PNG.
Future<void> _capture(WidgetTester tester, String name) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final boundary =
        _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory(Platform.environment['ZLINKER_SHOT_DIR'] ?? 'docs/screenshots');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
        .takeScreenshot(name);
  }
}

/// Hub that answers from injected fakes and never opens a real relay —
/// otherwise DeviceSessionHub connects to the seeded (bogus) URLs and its
/// retry loop keeps scheduling frames forever.
class _ShotHub extends DeviceSessionHub {
  final Map<String, DeviceSession> fakes;
  _ShotHub(this.fakes) : super(nativeListEnabled: () => true);

  @override
  void syncWith(List<Device> devices) {}
  @override
  DeviceSession? ensure(Device device) => fakes[device.id];
  @override
  DeviceSession? sessionOf(String deviceId) => fakes[deviceId];
  @override
  Future<void> suspend(String deviceId) async {}
  @override
  void scheduleResume(Device device) {}
  @override
  Future<void> disconnectAll() async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture store screenshots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController();
    final ui = UiSettings()..locale = _shotLocale;
    final store = DeviceStore();
    await store.load();
    await store.addUrl(_urlA);
    await store.addUrl(_urlB);
    final deviceA = store.devices.first;

    final session = FakeDeviceSession(
      deviceId: deviceA.id,
      params: deviceA.params!,
      entries: _sessions,
      workspaces: _workspaces,
      chatRows: _chatRows,
      channelHandler: (channel, method, args) async =>
          (channel == 'zcode-agent' &&
                  (method == 'listAllAutomations' ||
                      method == 'listAutomations'))
              ? _automations
              : null,
    );
    final sessionB = FakeDeviceSession(
      deviceId: store.devices[1].id,
      params: store.devices[1].params!,
      entries: _sessions,
    );
    final hub = _ShotHub({
      deviceA.id: session,
      store.devices[1].id: sessionB,
    });

    // 1. Device list
    await tester.pumpWidget(_wrap(
      DevicesPage(
        store: store,
        theme: theme,
        ui: ui,
        hub: hub,
        scheduled: ScheduledStore(),
      ),
      theme,
      ui,
    ));
    await tester.pumpAndSettle();

    // Android renders Flutter into an external surface; convert it to an
    // image so takeScreenshot can read pixels (required before the 1st shot).
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await _capture(tester, '01-devices$_suffix');

    // 2. Native task list. In image-surface mode the rasterizer keeps
    // scheduling frames, so pumpAndSettle never returns — pump real time
    // instead and let implicit transitions finish.
    await tester.pumpWidget(_wrap(
      TaskListPage(
        store: store,
        hub: hub,
        device: deviceA,
        sessionOverride: session,
      ),
      theme,
      ui,
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    await _capture(tester, '02-tasks$_suffix');

    // 2a-2d. Task list parity captures: merged relay data (non-active
    // workspace rows), official tags (等待确认 / unread), the long-press
    // action sheet, the delete confirmation and the archive view.
    final sessionRich = FakeDeviceSession(
      deviceId: deviceA.id,
      params: deviceA.params!,
      entries: [..._sessions, ..._extraSessions],
      workspaces: _workspacesRich,
      relayTasks: _relayTasks,
      chatRows: _chatRows,
    );
    // Phone-shaped viewport with a NESTED navigator: the parity target is
    // the official mobile layout (the Windows window itself is a wide
    // desktop surface), and modal sheets/dialogs/menus must render inside
    // the captured frame, so they resolve against the nested navigator.
    const phoneBox = Size(400, 850);
    Future<void> pumpTasks() async {
      await tester.pumpWidget(_wrap(
        Center(
          child: RepaintBoundary(
            key: _phoneKey,
            child: SizedBox(
              width: phoneBox.width,
              height: phoneBox.height,
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => TaskListPage(
                    store: store,
                    hub: hub,
                    device: deviceA,
                    sessionOverride: sessionRich,
                  ),
                ),
              ),
            ),
          ),
        ),
        theme,
        ui,
      ));
      await tester.pump(const Duration(milliseconds: 1200));
    }

    await pumpTasks();
    await _capturePhone(tester, '02a-tasks-merge$_suffix');

    // Scrolled view: bring the non-active workspace into view (a
    // ListView.builder never builds offscreen children), expand it
    // (official default has only the active one expanded) and capture its
    // relay-sourced rows.
    await tester.scrollUntilVisible(
      find.text('api-server'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('api-server'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _capturePhone(tester, '02a2-tasks-scrolled$_suffix');
    // reset scroll for the following captures
    await tester.drag(find.byType(ListView).first, const Offset(0, 600));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await pumpTasks();
    await tester.longPress(find.text(
        _isEn ? 'Deploy staging after review' : '评审后部署到预发环境'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _capturePhone(tester, '02b-task-actions$_suffix');

    // Same open sheet: tap 删除 → official confirm dialog, then cancel and
    // dismiss (the scrim lives in the navigator overlay, one fresh pump set
    // fully closes the stack before the archive capture).
    await tester.tap(find.text(_isEn ? 'Delete' : '删除'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _capturePhone(tester, '02c-task-delete-confirm$_suffix');

    await tester.tap(find.text(_isEn ? 'Cancel' : '取消'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tapAt(const Offset(20, 60));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await pumpTasks();
    await tester.tap(find.byIcon(Icons.more_vert));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text(_isEn ? 'View archive' : '查看归档'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _capturePhone(tester, '02d-archive$_suffix');
    sessionRich.dispose();

    // 3. Conversation
    await tester.pumpWidget(_wrap(
      ChatPage(
        gateway: session,
        sessionId: 'sess_shot_1',
        title: _chatTitle,
      ),
      theme,
      ui,
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    await _capture(tester, '03-chat$_suffix');

    // 4. Automations (server-side cron list with seeded items). Prewarm the
    // automation port so the pane's in-build fetch hits an already-resolved
    // method instead of racing the capture.
    final prewarm = await session.automation.list();
    // ignore: avoid_print
    print('prewarm automations: ${prewarm.length}');
    await tester.pumpWidget(_wrap(
      AutomationsPage(store: store, hub: hub, initialDeviceId: deviceA.id),
      theme,
      ui,
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // ignore: avoid_print
    print('auto card found: '
        '${find.text(_isEn ? 'Daily build patrol' : '每日构建巡检').evaluate().length}');
    await _capture(tester, '04-automations$_suffix');

    // 5. Tablet dual-pane (runs only when the device surface is ≥768dp wide,
    // i.e. the simulator has a tablet profile):
    // TaskListPage's desktop layout with a task pre-opened in the right pane.
    if (MediaQuery.of(tester.element(find.byType(Scaffold))).size.width >=
        768) {
      await tester.pumpWidget(_wrap(
        TaskListPage(
          store: store,
          hub: hub,
          device: deviceA,
          theme: theme,
          sessionOverride: session,
          initialPaneSessionId: 'sess_shot_1',
          initialPaneTitle: _chatTitle,
        ),
        theme,
        ui,
      ));
      // Repeated short pumps: the pane's conversation subscription lands
      // between frames, so give the rasterizer several frames to pick it up.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await _capture(tester, '05-dualpane$_suffix');
    }
  });
}
