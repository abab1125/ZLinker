# ZCode 网页远控版能力清单(web-capabilities)

> 证据来源:`E:\tmp\zcode-remote-source\zcode-remote-source\`(index.html + assets 1934 个 JS 分包),
> 主入口 `assets/index-WmHF5PiK.js`(4.7MB)、relay 协议 schema `assets/src-sr4WyacM.js`、
> i18n 词汇表 `assets/IntlProvider-j7hS-kdt.js`(654KB,真实 key 集约 4600+,含 `webRemoteControl.*` 104、
> `taskList.*` 57、`taskGroup.*` 24、`settings.*` 1692、`chat.*` 863 等)。
> 整个 web 应用的 BASE_URL 即 `/remote/v4/`,即**这个 bundle 就是远控端**(zcode.z.ai/remote/v4?sid=&hash=&t=&mid=&app_version=)。
> 生成日期:2026-08-30。

---

## 0. 总体架构

### 0.1 连接链路

```
手机浏览器(web app) ──WSS──> relay ──> ZCode 桌面端(Electron)
   │                            │
   └── REST(bootstrap / view-state)─┘
```

- **Relay WebSocket**:`{relayOrigin http->ws}/ws/remote-control/window/{token}`。
- **REST(可选快捷路径,非唯一通道)**:
  - `GET /api/remote-control/windows/bootstrap/{token}` → `{workspaces, tasks, ...}`(错误体含 `error` 字段)
  - `POST /api/remote-control/windows/{token}/mobile-view-state`,
    header `X-ZCode-Mobile-Connection-Id`,body `{activeWorkspaceKey, activeTaskId?, updatedAt, deviceInfo}`
  - `GET /api/server-info`(启动探测,`cache:"no-store"`)
- 消息封包统一字段 **`zcode_type`**;请求响应靠 `requestId` 关联,但**响应不保证回带 requestId**
  (客户端用 pending-matcher 模式:每个待决 matcher 对每个到达 payload 试匹配)。

### 0.2 relay zcode_type 消息面(src-sr4WyacM.js zod schema)

| zcode_type | 方向 | 关键字段 |
|---|---|---|
| `bootstrap-request` / `bootstrap-response` | C→S / S→C | `{requestId}` / `{requestId, success, result}` |
| `workspace-list-request` / `workspace-list-response` | 同上 | result 为 workspace+task 总表 |
| `workspace-list-updated` | S→C(推送) | `{result}`(无需 requestId) |
| `workspace-bridge-open` | C→S | `{requestId, bridgeSessionId, bridgeGeneration?, recoveryId?, workspaceKey, taskId?}` |
| `workspace-bridge-ready` / `workspace-bridge-error` | S→C | ready 带 `{bridge:{bridgeSessionId, bridgeGeneration?, recoveryId?, workspaceKey, initialTaskId?...}}` |
| `workspace-reconnect-request` / `-response` | C→S / S→C | `{requestId, workspaceKey}`(恢复已开 bridge 的廉价路径) |
| `mobile-view-state-update` | C→S | `{viewState:{activeWorkspaceKey?, activeTaskId?, updatedAt}, deviceInfo}` |
| `mobile-diagnostic` | C→S | `{event: state-transition\|socket-close\|socket-error\|recover-start\|recover-scheduled\|pair-status\|failure, timestamp, ...}` |
| `platform-request` / `platform-response` | S→C / C→S | method 枚举:`isDockerAvailable, listWSLDistros, listDockerContainers, listSSHConfigAliases, loadMcpFromUserDirectory, saveMcpFromUserDirectory, migrateLegacyCommonMcp` |
| `rpc-frame` | 双向 | `{bridgeSessionId, bridgeGeneration?, recoveryId?, seq, messageSeq, fragmentIndex, fragmentCount, messageBytes, checksum, dataBase64}`(1MiB 物理帧 / 16MiB 消息 / 64 分片上限,crc32) |
| `rpc-frame-ack` | 双向 | `{bridgeSessionId, bridgeGeneration?, recoveryId?, ackMessageSeq}` |
| `bridge-degraded` | S→C | 断流原因枚举:`rpc-transport-fault, rpc-frame-gap, buffer-overflow, buffer-timeout` |
| `app-error` | S→C | `{requestId?, bridgeSessionId?, reason, error?}`,reason 枚举见 §1.1 |

### 0.3 relay 数据模型(schema `Eg`/`Dg`)

- **Workspace**:`{workspacePath, workspaceIdentity?, remoteSessionId?, label, workspacePurpose?: 'project'|'conversation', kind: 'local'|'remote', connectionState?: 'connected'|'disconnected'|'reconnecting', lastConnectionError?}`
- **Task**:`{taskId, title?, workspacePath, workspaceIdentity?, remoteSessionId?, workspaceLabel, workspaceKind, createdAt, updatedAt, provider?, unreadAt?, displayStatus?: 'idle'|'running'|'completed'|'error', pinned?, archived?}`
- **bootstrap result**:`{windowControlSessionId, workspaces, tasks, initialViewState?, mobileViewState?}`
- **deviceInfo**:`{platform:'web', version, name:'mobile-browser', userAgent?, ...}`(ZLinker 对应 name 用自己的标识)

### 0.4 bridge 内层:IPC Channel RPC

rpc-frame 载荷是 IPC 二进制:header `[reqType, reqId, channelName, name]` + 参数 value。
reqType:100 Promise / 101 PromiseCancel / 102 EventListen / 103 EventDispose;
resType:200 Initialize / 201 PromiseSuccess / 202 PromiseError / 203 PromiseErrorObj / 204 EventFire。
Channel 枚举共 **37 个**(比 ZLinker 常量表多 4 个:`window-controller`、`cua-permission`、`cua-pip-session`、`client-scenes`)。
web 端把全部 channel 构造成 service;断连前有本地 stub(`Z9/Q9/$0t`)兜底。

### 0.5 conversation V4(宿主 channel `zcode-agent`)

- 握手:`helloConversationV4()` → `{kind:'hello', protocolVersion:3, connectionId, clientMode:'desktop-continuous'|'web-remote-replayable', deliveryProfile, serverTime, capabilities:{nativeDialogs, localTerminal, binaryFrames, compression:'none'|'permessage-deflate', workspaceHookReview?}, auth:{userId?}}`;
  `initializeConversationV4({kind:'clientHello', protocolVersion:3, clientId, clientKind:'desktop'|'web', appVersion, capabilities:{workspaceHookReview?}})`
- 订阅:`subscribeConversationV4({workspacePath, workspaceIdentity?, sessionId, base?, visibility?})` → `{subscriptionId, mode:'snapshot'|'resume', logEpoch}`;
  `unsubscribeConversationV4` / `resyncConversationV4({subscriptionId, base:{logEpoch,seq}, forceSnapshot:true})`;
  sessions-index 同构:`subscribe/unsubscribe/resyncSessionsIndexV4`
- 命令:`sendConversationCommandV4({scope, envelope})` → `{commandId, status:'accepted'|'rejected'|'stale'|'duplicate'|'noop'|'failed', reasonCode?, message?, revisionAtDecision, result?}`;
  `queryConversationCommandsV4({scope, commands:[{sessionId, commandId}]})` → `{results}`
- **envelope**:`{commandId, clientId, sessionId, baseRevision?, baseLogEpoch?, type, payload, issuedAt}`(CAS 命令必带 baseRevision,row-target 命令必带 baseLogEpoch)
- **命令 type 全集**(schema `oue`):
  - `createSession {workspaceId, firstInput?:{text, attachments?}, config?, runtimeModel?, mcpServers?}`
  - `createSelectionSideSession {firstInput?}`
  - `sendText {text, attachments?, requestedDelivery?:'startNow'|'queue'|'guide', browserAmbientContext?, heldQueueDisposition?:'clearQueueAndSend'|'keepQueueAndSend', expectedHeldQueueItemIds?, turnRuntimeModel?, automationId?, offPeakTaskId?, offPeakRunType?:'init'|'resume', botDeliveryTarget?, toolDisallowlist?}`(automationId 与 offPeakTaskId 互斥)
  - `sendGoalCommand {text, displayText?, heldQueueDisposition?, expectedHeldQueueItemIds?}`
  - `stop {expectedForegroundExecutionId?}`、`compact {}`
  - `forkAssistant {target}` / `applyFileRewind {target}` / `retryTurn {target}`
  - `editUserQuery {target, newText, attachments?, workspaceMode?:'preserve'|'rewind'}`
  - `setAssistantFeedback {target, feedback:'like'|'dislike'|null}`
  - 队列:`sendQueuedNow {queueItemId}`、`editQueueItem {queueItemId, newText}`、**`reorderQueueItem {queueItemId, beforeQueueItemId|null}`**、`deleteQueueItem {queueItemId}`、`setAutoDrain {autoDrain}`
  - 交互:`resolveInteraction {interactionId, answer:{optionId?, freeText?, action?:'accept'|'decline'|'cancel', content?}}`、**`snoozeInteractionAutoResolution {interactionId}`**
  - Hook 评审:`requestWorkspaceHookReview`、`respondWorkspaceHookReview {decision}`、`toggleWorkspaceHookReviewItem {reviewItemId, enabled}`、`revokeWorkspaceHookTrust`
  - 模型/模式:`switchModelConfig {provider, model, thought, runtimeModel?}`、`switchCollaborationMode {mode:'build'|'edit'|'plan'|'yolo'}`、`setFollowupMode {mode:'queue'|'guide'}`
  - 目标/会话:`pauseGoal {}`、`resumeGoal {}`、**`cancelBackgroundWork {workId}`**、**`renameSession {title}`**、**`deleteSession {}`**
- 查询:`conversationRowsRangeV4({scope, sessionId, beforeRowId?, limit})`、`conversationPlansV4`、`conversationFileChangesV4`、`conversationFileRewindPreviewV4`
- 附件:`attachmentBeginV4/ChunkV4/CommitV4/AbortV4/ReadV4/PreviewSourceV4`
- 事件行 kind 枚举含 `turn.started {executionKind:'agent'|'controlOnly', automationId?, offPeakTaskId?, offPeakRunType?}` 等

### 0.6 window-controller V4(channel `window-controller`,任务索引实时流)

- `subscribeControllerV4({topic, base?, visibility?:'foreground'|'background'})` → `{subscriptionId, mode, logEpoch}`;`unsubscribeControllerV4` / `resyncControllerV4`
- 事件 `onDynamicControllerFrame()` → `{subscriptionId, payload:{kind:'snapshot'|'deltas', snapshot.tasks | deltas:[{op:'task.upserted', task|address}]}}`
- topic:`` `controller/workspaces` ``、`` `controller/tasks-index` ``
- zcode-task 侧另有事件 `onDynamicWorkspaceEvent` → `{type:'workspace_task_list_changed', workspacePath, workspaceIdentity?, reason:'task_created'|...}`

### 0.7 移动端 view-state 同步(双通道)

1. WS:`mobile-view-state-update`(见 0.2)——**每次**切换工作区/任务都发(`M(workspaceKey, taskId)`);
2. REST POST(见 0.1,带 `X-ZCode-Mobile-Connection-Id`)。
   桌面端据此在任务列表上显示 `mobileActive="手机正在操作此任务"` 标签。

---

## 1. 连接与全局状态(webRemoteControl.* 104 keys)

### 1.1 失败态全集(12 种,`webRemoteControl.failure.*`)

| reason | 文案要点 | relay close code(app-error reason) |
|---|---|---|
| sessionNotFound | 链接失效 → 回桌面重开 | 4004 / session-not-found |
| sessionExpired | 会话结束 | 4011 / session-expired |
| sessionConflict | 被其他页面占用 | 4009 / session-conflict |
| kicked | relay 踢出 | — |
| workspaceClosed | 桌面窗口已关 | 4012 / workspace-closed |
| desktopDisconnected | 桌面断开 | 4010 / desktop-disconnected |
| invalidMobileConnection | 刷新重连 | 4013 / invalid-mobile-connection |
| desktopBootstrapTimeout | 桌面响应超时 | desktop-bootstrap-timeout |
| connectionRecoveryTimeout | 手机恢复超时 | connection-recovery-timeout |
| relayUnavailable | relay 不可用 | relay-unavailable |
| unsupportedAction | 「当前是 Web 远程控制模式，只支持访问桌面端当前窗口已经打开的工作区。」 | unsupported-action |
| unexpectedError | 兜底 | unexpected-error |

### 1.2 重连与单页限制

- 断线恢复:`data-web-remote-control-reconnect-notice` 顶部悬浮 toast(spinner + 「正在自动重连...」,aria-live=polite),重连成功自动消失。
- `singlePageNote="当前 relay 配对同一时间只支持一个手机页面…"`(同一 token 双开会话冲突 → sessionConflict)。
- 启动/停止 toast:`webRemoteControl.startFailed/stopFailed`。
- 桌面端弹窗(`web-remote-control-dialog`):二维码状态机 idle→starting→waiting→connecting→active→error,每态 statusDetail;刷新二维码有确认弹窗(旧链接失效、已连接手机需重扫);`stopSuccess="已关闭 Web 远程控制"`;Bot Channel 四卡(weixin/feishu/lark/telegram)入口。

### 1.3 移动端外壳

- 手机首页 `mobileHome`:已连接横幅 + notice(「二维码失效后需要回到桌面端重新连接」)+ 工作区/任务汇总(`{workspaceCount} 个工作区 · {taskCount} 个任务`)+「当前设备上的工作区和任务」分区 + 整理(按工作区/时间线)+ 排序(创建/更新时间)+ 刷新 + collapseAll + 每工作区空态(`这个工作区暂无任务`)+ 更新时间戳。
- 工作区类型标签:`workspaceKind.local / conversation / remote`。
- 外壳 `mobileShell`:backHome、chatTitle、`reconnecting="正在自动重连..."`;断线态 `mobileHome.disconnected/reconnect/reconnecting`。
- 偏好持久化:localStorage `zcode-web-remote-control-mobile-task-home-preferences`,默认 `{organizeBy:'workspace', sortBy:'updated'}`。

---

## 2. 移动端任务主页(taskList.* 57 / taskGroup.* 24 / taskSearch.* 9)

- **分区**:`pinnedSection`(已置顶)/ `recentSection`(最近任务);时间线分组 `taskTimeline.today/yesterday/daysAgo/thisWeek/lastWeek/thisMonth/older`。
- **任务项操作菜单**:pin/unpin、rename(内联,placeholder「任务名称」)、delete、archive/unarchive(删除归档任务另有确认弹窗)、markAsUnread、resume、openInSplitPane、feedback、viewModelTrajectory。
- **状态标签**:`status.streaming="生成中"/restoring/ready/completed/failed`;`permissionTag/userInputTag="等待确认"`;`changeStats="+{added} -{removed}"`;`stopCountdown`(停止倒计时);`attentionCount`;特殊标记 `cronTaskLabel`(定时任务)/`offPeakTaskLabel`(闲时任务)/`mobileActive`。
- **新建任务**:`newTask/newThread` + 多 Agent 选择(claude/opencode/gemini/codex CLI);模型供应商切换中禁止切任务(`switchBlockedByModelRestart`);Codex 预热网络检测。
- **确认弹窗**(confirmDialog.*):taskDeleteTitle/Description(「删除这个任务？…现有记录无法恢复」)、archivedTaskDelete、taskArchive、projectRemove。
- **任务分组(桌面功能,移动端弱化)**:taskGroup.newGroup/rename/color(7 色)/moveToGroup/ungroup + 失败 toast。
- **搜索**:taskSearch 面板(按标题或内容搜索近期任务,recent/loading/noRecent/noResults/expandMoreSnippets)+ 侧栏内联搜索 + commandCenter(搜索操作、任务或文件,scopeTabs: all/commands/conversations/files,搜索历史)。
- **空态/加载**:`noTasks="暂无任务"`、`noArchivedTasks`、`loading="正在获取任务..."`、`syncingRemoteWorkspaces="正在加载远端任务..."`、`forkedUntitled="新任务"`。
- 任务列表数据源(桌面主界面):`zcode-task.listTaskList({kind:'timeline', workspaceScopes:[...], sortBy, limit})` → `{items, total, hasMore}`;实时:`onDynamicWorkspaceEvent(workspace_task_list_changed)` / window-controller `controller/tasks-index`。

## 3. 聊天页(chat.* 863)

### 3.1 输入区(composer)
- 占位符:新任务/移动端新任务/追问/排队中(`followUpQueue="继续输入以排队后续修改"`)/初始化中。
- 上下文触发符:`@` 提及(files/skills/subagents/whiteboards/plugins/sessions 分类 + 搜索 + 空态 + 插件冲突提示)、`/` 斜杠(命令/技能/子智能体)、`$` 技能、`#` 插入会话、拖拽引用文件。
- 附件:添加/移除/粘贴图片/拖拽,上限 `maxFiles="最多只能添加 {count} 个附件"` / maxFileSize,上传状态机(waitingSession→queued→uploading{progress}%→committing→ready/failed/retry),`runtimeRestarted`(重启附件失效)、`remoteMaterializationRequired`(远端附件未物化禁止发送本地路径),图片/视频预览。
- Toolbar:模型选择(label/description/manageModels/searchPlaceholder/empty)、切换 6 阶段(stage.settingModel→…→persistingWorkspace)、运行中锁定;模式切换;**思考强度 9 档** `off/noThink/on/low/medium/high/xhigh/max`;电脑操作(CUA)tooltip 五态(macOS 权限引导)。
- 提示词增强 `chat.promptEnhance.*`(用当前模型润色草稿,可取消,unsupported/error/empty);建议草稿 `chat.draft.suggestedPrompt.*`(近 7 天 commit、制作 PDF、插件引导流完整状态机)。
- 后台任务指示 `composer.backgroundWorks.*`(Bash x 个、子智能体 y 个)。
- 发送语义:`⌘/Ctrl + Enter` 三语义 sendNow/addToQueue/guideCurrent(由设置 `zcodeInteractionBehavior` 决定 queue|guide);CLI 重启丢弃输入 `chat.pendingCommand.discarded`(重新发送/稍后)。

### 3.2 队列(queue/followup)
- 入队说明、`title="待发送消息（{count}）"`、**拖拽排序**、逐条 sendNow/runNow/edit/remove、编辑冲突提示、暂停三态(stopped/error/generic)+resume、发送确认弹窗(`sendConfirm.title="发送消息？…要清除之前已排队的 {count} 条消息吗？"` clear/keep)。

### 3.3 消息交互(message/history/edit/rewind)
- 行操作:edit/restore/copy(`copy.requiresFull` 需加载完整消息)/like/dislike/**fork**(边界:任务结束后才可分叉、agent 不支持、checkpoint 丢失)、大消息预览+loadFull/retry、工具分页 `toolSlice.loadMore`、工具快照 `toolSnapshot.loadAll`。
- 重试 `chat.message.retry`;状态汇总 `chat.history.workingFor="工作中 {duration}"/workedFor/stopped`。
- 编辑重发:`edit.resetConversationAndFiles`(对话+文件重置,边界:noFiles/running/unavailable「压缩中或有待处理交互时不能重置文件」);工作区冲突弹窗 workspaceConflict(conversationOnly)。
- **撤销(rewind)预检流程** `chat.changeSummary.rewindDialog.*`:loading「正在检查可撤销文件…」→ safe/unsafe/ignored 三档 → 不可撤销原因枚举(bashIgnored/checkpointMissing/externalModified/unsupportedCheckpoint)→ `cannotApply="存在不能安全撤销的文件，未写入任何文件。"`。
- 消息引用 `chat.selections.*`(加到当前任务/辅助对话;user/assistant/reasoning/tool 四类;限额:单条 8000 字符、8 条、总量 16000)。
- 回合导航器 `chat.turnNavigator.*`(跳到第 N 条问题);代码评论 chat.codeComments;网页元素 chat.webElements;幻灯片元素 chat.pptxElements。

### 3.4 权限与交互(permission/elicitation)
- `chat.permission.title="需要权限"`、`awaitingApproval="等待确认"`;操作:approve / approveAlways / allowForSession「允许本会话」/ allowForProject「始终允许本项目」/ deny / denyAlways(+各语义说明);文件变更摘要(permission.fileChange.add/update/addMany/updateMany/mixedMany);命令作用域(exactCommand「仅此命令」/commandPrefix);键盘提示 Tab/上下键/回车。
- 计划审批 elicitation:`chat.elicitation.planApproval.approveDescription`;MCP 表单 elicitation(customAnswer/submit/上下题/倒计时/展开折叠);AskQuestion `autoContinued="未回答，已自动继续"`;`snoozeInteractionAutoResolution` 对应设置「提问自动继续」(5 分钟)。
- 工作区 Hook 待审核横幅 `chat.workspaceHookPending.message/review/dismiss`。

### 3.5 工具调用展示(toolCall 292 + CUA 115)
- 状态机 pending/running/completed/failed/denied/stopped;类型 read/search/write/edit/delete/terminal/skill/sessionContext/nodeRepl/message/response/taskOutput/taskStop/todo。
- 分组聚合:executeGroup.label「终端」(N 个命令/N 失败/N 停止)、changesGroup.label「更改」、explore 桶。
- 各工具文案族(edit 8 态、execute、nodeRepl、skill、search、read、sendMessage(子智能体)、respondToCoordinator、taskOutput 8 态、taskStop 9 态、agent 后台活动流 recentRows/hiddenRows、mcp callDetails/parameters、sessionContext、todo)。
- 裁剪加载:`snapshot.notice="该工具有 {fields} 个字段被裁剪…"` + loadFull/retry。
- **CUA 电脑控制**:动作全集(listApps/getAppState/.../writeClipboard/stop 30+)、详情面板(应用/窗口/焦点/权限四项 granted/denied)、elementStale 处理、截图/放大预览。

### 3.6 面板
- 变更摘要 `chat.changeSummary.*`(「{count} 个文件已更改」、review「审查」、openInEditor、rewind/reapply/reverted、diffUnavailable)。
- 状态面板 `chat.statusPanel.*`:Git(分支/更改/提交推送/干净)、Goal、计划(打开计划:{title})、todo(折叠 N 项)、终端、智能体、后台任务;`chat.summaryPanel.*` displayModeAuto/Expanded/Collapsed、goalIterationValue「第 {count} 次迭代」。
- 上下文用量 `chat.contextUsage.*`(容量、平均缓存命中率、来源分解:消息/系统提示词/技能/工具提示词/系统工具/MCP 工具、compress 按钮)。
- 压缩 `chat.contextCompaction.*`(started/retrying/skipped/completed/completedAuto/failed/interrupted/retry)+ `chat.compact.runningBlocked/queued/duplicateBlocked`。
- 套餐用量 `chat.planUsage.*`(5 小时 Prompt 池/每周额度/MCP 工具月用量/当前会话上下文);额度警告 `chat.quota.*`(startPlan 四档、concurrentLimit、mcp.quotaExhausted、providerLimited;动作 upgrade/renew/switchModel/switchProvider/refresh)。
- Goal:`goalBanner.label`、`target.status.active/paused/budget_limited/complete`、pause/resume/clear、goalVerification(checking/incomplete/complete/cancelled)、`goal.runningBlocked`、`goal.planModeBlocked`。
- 其他:思考过程(reasoning.thinking/thought/duration)、模型切换通知、Agent 切换、Hook 卡片 6 态、预览卡片(website/htmlWebsite/markdown/docx/xlsx/pptx/pdf)、长任务面板、子智能体邮箱消息(mailbox.from「来自 {sessionId} 的新消息」)。

### 3.7 错误与空态
- `chat.error.*`:connectionLost「与代理的连接已断开」、processExited「代理进程意外退出」、重试/重新登录/切换模型/验证码/复制 TraceID/复制完整报错、`feedback="反馈问题"`→`feedbackOpened="已打开反馈，并自动带上报错现场"`、noAvailableModel/sendFailed。
- 空态:`chat.empty.title="开始对话"` + 6 时段问候语;工作区选择菜单(搜索/创建/不在项目中工作/主目录);`chat.emptyResult`(模型返回前被停止)。
- 独立 key:rewind、scrollToBottom、preparing、remoteGenerating、apiRetryStatus、captcha.verifyFailed。

## 4. 任务操作协议面(channel `zcode-task`,方法名已从源码确认)

| method | 参数 | 备注 |
|---|---|---|
| `initialize` | scope | `{available, workspaceKey, reason?}` |
| `prepareWorkspace` | scope | `{configOptions, slashCommands, currentModeId, availableModes}` |
| `releaseWorkspacePreparation` | scope | |
| `checkCodexConnectivity` | — | `{ok}` |
| `listTasks` / `listArchivedTasks` / `listPinnedTaskIds` / `listPinnedTasks` | scope | |
| `listDeletedTaskIds` | scope | 可选方法(调用点带存在性判断) |
| `listTaskList` | `{kind:'timeline', workspaceScopes:[{workspacePath, workspaceIdentity?}], sortBy, limit}` | `{items, total, hasMore}` |
| `getTaskTokenUsage` | `{taskId}` | `{sessionId, totalTokens, inputTokens, outputTokens, reasoningTokens, cacheCreationTokens, cacheReadTokens, modelRequestCount, modelErrorCount, inputBaselineBySource}` |
| `getTaskSnapshot` / `getTaskSnapshotWithEtag` / `getTaskSnapshotBody` / `getTaskSnapshotRef` / `getTaskSnapshotToolCallsSlice` | scope+taskId / ref | snapshot 增量读取族 |
| `getTaskMeta` | — | |
| `renameTask` | `{taskId, workspacePath, workspaceIdentity?, title}` | |
| `archiveTask` / `unarchiveTask` | `{taskId, workspacePath, workspaceIdentity?}` | **两个独立方法,不带布尔字段** |
| `deleteTask` | `{taskId, workspacePath, workspaceIdentity?}` | |
| `setTaskPinned` | `{..., pinned}` | |
| `setTaskUnread` | `{..., unread}` | |
| `createTaskGroup` / `renameTaskGroup` / `deleteTaskGroup` / `updateTaskGroupColor` | | 桌面任务分组 |
| `applyGroupedTaskViewOrder` / `listGroupedTaskViewStructure` | | |
| `setWorkspacePreferredModel` | `{workspacePath, workspaceIdentity?, provider, modelId, modelRef}` | |
| `restartWorkspaceProcess` | `{..., provider, resumeTaskId?}` | |
| `onDynamicWorkspaceEvent`(事件) | scope | `workspace_task_list_changed`,reason 如 task_created |

## 5. 用量统计(usage-stats channel + settings.usage 143 keys)

- channel 方法:
  - `getEntitlementSnapshot({includeSubscription, preferredProviderId, allowDisabledPreferredProvider, requirePreferredProvider, allowEnvApiKey?, organizationId?, projectId?})`(结果被缓存;断连前为 stub)
  - **`getAppUsageSnapshot({range:'7d'|'30d'|'90d'|'all', timeZone})`** → `{dailyModelUsage:[{date, models:[{modelId, totalTokens}]}], models:[{modelId}], ...}`
- 设置页两个 tab:
  - `tab.appUsage="应用用量"`(本地会话历史粗略统计 + `estimationHint` 估算提示)
  - `tab.codingPlan="个人套餐"`(供应商 monitor 接口真实 Token;`remoteTokenHint="来自当前供应商模型用量接口"`)
  - 时间范围:app all/7d/30d;codingPlan today/7d/30d/custom;指标 `codingPlanMetric.credits="积分消耗"/usage="用量消耗"`;主体 model/tool;工具调用分布图;用量趋势图。
- 权益面板 entitlement.*:有效套餐/等级/到期/下次重置/5 小时 Prompt 池/每周剩余/工具调用(月)/ZCode MCP/并发优先级/`policyHint`;状态枚举 Active/Error/Loading/LoginRequired/NoPlan/NotConfigured。
- 错误文案 `usage.error.*`(entitlement/chatPlan/stats.credential|generic);billingBanner;healthTitle(Max&Pro/Lite 高峰期平均 Decode 速度);空态/加载/lastRefreshTime/刷新/checkApiKey。
- 图表为独立分包(AppUsageDailyModelTrendChart、AppUsageModelUsagePieChart、CodingPlanUsageBarChart、CodingPlanUsageLineChart)。
- 侧栏迷你额度 `sidebar.usage.plan.*`(31 keys):剩余额度/Token 额度/时长额度/已用 {percent}%/{time} 重置/刷新 8 态/`summaryTitle="最近 30 天"`/升级续期按钮。

## 6. 模型供应商(model-provider channel)

- `getAll()` / `getAllCached()` / `save(provider)` / `delete(...)`
- **`refreshPresetProviders()`**;**`getEndpointSuggestions()` → `{suggestions}`**;**`getModelsByEndpoint(endpoint)` → models**
- `resolveWorkspaceModelSelection({zcodeProvider, workspacePath, workspaceIdentity?, modelProviders, localPreference, providersReady})` → `{selectedSupplierKey:'native:claude', isGhostSupplier, supplierMismatchReason}`
- `refreshCodingPlanApiKey(provider)`;事件 `onDidChangeProviderRegistry(cb)` → `{snapshot:{revision}}`(注册表变更实时推送)
- 配套设置键:`modelProviderFamilySelectedKeys`、`modelProviderFamilyModes`(setting channel)
- settings.modelProvider 521 keys:自定义端点(catalog/Anthropic/OpenAI/Gemini 接口地址/connectionMode)、模型列表(上下文窗口/最大输出/输入输出模态)、Claude 模型映射(claudeMapping/slot)、testModel、拖拽排序、删除确认。
- codingPlan 372 keys:套餐状态 8 态、完整应用内购买流(purchase.*:选套餐→计费周期→确认支付→支付轮询→成功/刷新)、续费政策、团队席位、150% 配额活动、startPlan 26 keys(体验套餐)。

## 7. 设置(setting channel + settings.* 1692 keys)

- channel 方法:`get()`(完整设置对象)、`update({KEY: value})`、`updateDataBaseDir()`;主包确认可 update 的 key:`terminalInheritSystemProfile、terminalFontFamily、integratedTerminalShell、httpProxy、httpProxyNoProxy、httpProxyCaCertPath、taskAutoArchiveEnabled、taskAutoArchiveOlderThanDays、closeToTrayOnWindows、desktopChromiumHardwareAccelerationEnabled、embeddedBrowserAllowInsecureCertificates、modelProviderFamilySelectedKeys、modelProviderFamilyModes、recentProjects`;broadcast 同步 topic `settings:app-runtime-preferences`。
- 分区(侧栏):基础设置 / Agent 能力 / 数据与统计;子分类按 key 数:modelProvider 521、plugins 226、usage 143、skills 125、mcp 100、subagents 85、commands 66、hooks 60、migration 46、browser 44、memory 38、mcpServers 29、computerUse 12、indexing 6、taskAutoArchive 5、根级 ~100(界面语言/主题/字号/代码设置/集成终端/HTTP 代理/数据路径/任务通知/保持电脑运行/关闭到托盘/更新/显示思考过程/工具分组/提问自动继续/完整保留模型 I/O/性能模式/优化体验/remoteSync/`zcodeInteractionBehavior`)。
- 桌面专用提示:`skills.userScopeDesktopOnly`、`migration.unsupported.desktopOnly`、`memory.viewer.localOnly`、`browser.desktopOnly`。
- 远控相关性:外观/通知/交互行为类可在远控页读写;memory/migration 是 desktop-only。

## 8. 其他域(远控相关性标注)

| 域 | 概述 | 远控页相关性 |
|---|---|---|
| feedback(287) | 应用内工单系统:四类型(bug/usage/feature/performance)、12 模块下拉、状态机 9 态、补充信息、后台提交;入口在 quickPick/标题栏/chat.error/taskList | **可用**(手机可提反馈) |
| bots(257) | 外部聊天渠道机器人(telegram/weixin/feishu/lark + 规划中 dingding/discord/wecom/webhook),四步向导、绑定码、回复颗粒度 4 档 | 桌面配置为主;远控弹窗仅入口 |
| terminal(10) | 终端面板(create/write/resize/dispose + onDynamicData/Exit) | 桌面;web app 有,移动端远控不暴露 |
| git(154) | Git 审查面板(getChanges/getIdentity/refresh/提交对话框/推送对话框/分支切换器/上一轮更改) | 桌面;web app 有 |
| diff(10) | Diff 面板,当前是占位壳(placeholder 说明「真实 Git service 后续接入」) | 桌面 |
| browser(41) | 内置浏览器(地址栏/视口/元素选择器/证书) | `browser.desktopOnly` |
| todo/whiteboard/treemapping(4/15/16) | 待办面板/画板/文件活动地图 | 桌面 |
| codeViewer(67)/modelTrajectory(51)/repoWiki(46)/gitGraph(27) | 代码查看器/模型调用轨迹/仓库 Wiki/提交图谱 | 桌面 |
| quickPick(57)/commandCenter(20)/sidePane(34) | 命令面板/全局命令中心/右侧面板 | 桌面;web app 有 |
| mode(47) | 各 CLI Agent 权限模式名映射(Claude/Codex/Gemini/OpenCode/GLM) | 全局(模式 chip 文案) |
| notification(11) | 桌面通知(任务完成/出错/等待确认/需要回复/计划等待确认) | 桌面;手机侧对应 ZLinker 本地通知 |
| update 系列(~30) | 应用更新流 + forceUpdate 封锁页 | 桌面 |
| onboarding/login/logout/welcome(62/31/5/6) | 首启向导/OAuth+APIKey 登录/断开确认 | 桌面 |
| server/wsl/docker/workspace/forms(12/11/9/13/17) | 远程工作区连接向导(remote.* 51 keys 同族) | 桌面 |
| zcode(24) | AI 代理错误码文案(TASK_OWNED_BY_OTHER_HOST/媒体预算/providerBusiness 1006/1005/3006/3002+429/3007/3008-3010/2007) | 全局错误映射 |
| appError(11) | 分区级错误边界(白屏防护/重试此区域/组件堆栈) | 全局 |
| client-scenes channel | `list()` → `{code, msg, data:[]}` | 桌面场景管理 |

## 9. 输入约定与快捷键

- 全应用硬编码组合键仅 `⌘ + Enter` / `Ctrl + Enter`(发送/入队/引导三语义);权限与 elicitation 弹窗:Tab / 上下键 / 回车 / 空格;输入区触发符 `@ / # / $ /` 四键;Ctrl+N 新建、Ctrl+K 命令面板(桌面侧栏)。
- 移动端 composer 有 `isMobileTextInputViewport` 分支;index.html viewport 无 user-scalable 限制;theme-color `#161616`。
