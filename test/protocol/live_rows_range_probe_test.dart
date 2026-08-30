import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zlinker/protocol/connection_params.dart';
import 'package:zlinker/state/device_session.dart';

/// Live rowsRange probe: connect, subscribe the first workspace's
/// sessions-index, then call conversationRowsRangeV4 with beforeRowId =
/// current window head and print the RAW response. Skipped unless
/// ZLINKER_PROBE_URL is set.
void main() {
  final url = Platform.environment['ZLINKER_PROBE_URL'];
  test('live rowsRange probe', () async {
    if (url == null || url.isEmpty) {
      // ignore: avoid_print
      print('ZLINKER_PROBE_URL not set — skipping');
      return;
    }
    final params = RemoteConnectionParams.parse(url);
    if (params == null) throw StateError('bad url');
    final session = DeviceSession(
      deviceId: 'probe2',
      params: params,
    );
    try {
      await session.connect();
      expect(session.status, DeviceStatus.connected,
          reason: session.error);
      final taskId = session.relayTasks
          .map((t) => '${t['taskId']}')
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      expect(taskId, isNotEmpty, reason: 'no tasks in relay overview');
      final handle = await session.subscribe(taskId);
      final sub = handle.state;
      for (var i = 0; i < 20 && sub.rows.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // ignore: avoid_print
      print('PROBE rows in window: ${sub.rows.length}, '
          'firstRowId=${sub.firstRowId}, totalCount=${sub.totalCount}, '
          'canLoadOlder=${sub.canLoadOlder}');
      final head = sub.rows.first['rowId'];
      // ignore: avoid_print
      print('PROBE head rowId=$head (${head.runtimeType})');
      final res = await session.callChannel('zcode-agent',
          'conversationRowsRangeV4', [
        {
          ...session.offPeakScope,
          'sessionId': taskId,
          'beforeRowId': head,
          'limit': 5,
        }
      ]);
      // ignore: avoid_print
      print('PROBE rowsRange response: $res');
    } finally {
      await session.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
