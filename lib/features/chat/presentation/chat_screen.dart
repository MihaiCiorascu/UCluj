import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/primitives/app_snackbar.dart';
import '../../../core/primitives/haptics.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/player_photo_avatar.dart';

// ─── Connection status ──────────────────────────────────────────────────────

enum _ConnStatus { connecting, connected, reconnecting, offline }

// ─── Model ────────────────────────────────────────────────────────────────────

enum _MsgStatus { sending, sent }

class _Msg {
  _Msg({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sender,
    required this.time,
    this.senderAvatarUrl,
    this.fileUrl,
    this.fileType,
    this.status = _MsgStatus.sent,
  });

  final String id;
  final String senderId;
  final String text;
  final String sender;
  final String time;
  final String? senderAvatarUrl;
  final String? fileUrl;
  final String? fileType;
  final _MsgStatus status;

  /// Raw ISO-8601 timestamp kept for `since`-based reconnect gap-fill. Optimistic
  /// (local) messages carry the local send time so ordering still holds before
  /// the server echo arrives.
  final String createdAt = DateTime.now().toUtc().toIso8601String();

  _Msg copyWith({_MsgStatus? status}) => _Msg(
        id: id,
        senderId: senderId,
        text: text,
        sender: sender,
        time: time,
        senderAvatarUrl: senderAvatarUrl,
        fileUrl: fileUrl,
        fileType: fileType,
        status: status ?? this.status,
      );

  factory _Msg.fromJson(Map<String, dynamic> json) {
    return _Msg(
      id: json['id'] as String? ?? '',
      senderId: json['author_id'] as String? ?? '',
      text: json['content'] as String? ?? '',
      sender: _formatSender(json['author_name'] as String? ?? 'Unknown'),
      // KEY new wire field: the sender's avatar (snake_case author_avatar_url),
      // null when the user has no picture — rendered via PlayerPhotoAvatar with
      // an initials fallback.
      senderAvatarUrl: json['author_avatar_url'] as String?,
      time: _formatTime(json['created_at'] as String?),
      fileUrl: json['file_url'] as String?,
      fileType: json['file_type'] as String?,
      status: _MsgStatus.sent,
    );
  }

  static String _formatTime(String? iso) {
    if (iso != null) {
      try {
        final dt = DateTime.parse(iso).toLocal();
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return _now();
  }

  static String _formatSender(String raw) {
    if (raw.isEmpty) return 'UNKNOWN';
    if (raw.contains('@')) {
      String local = raw.split('@').first;
      return local.replaceAll('.', ' ').replaceAll('_', ' ').toUpperCase();
    }
    return raw.toUpperCase();
  }

  static String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.onTabSelected,
    this.authState,
    this.onProfileTap,
    super.key,
  });

  final ValueChanged<AppTab> onTabSelected;
  final AuthState? authState;
  final VoidCallback? onProfileTap;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_Msg>[];
  bool _typing = false;
  bool _uploading = false;

  // ── Live transport (API Gateway WebSocket — receive-only) ──────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  Timer? _reconnectTimer;
  _ConnStatus _status = _ConnStatus.connecting;
  // Exponential backoff: 2s → 30s. Reset to 2s on a clean connect.
  Duration _backoff = const Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(seconds: 30);
  // Monotonic generation token: any socket from an older channel selection is
  // ignored when its callbacks fire after a switch, preventing cross-channel
  // bleed and stale reconnect loops.
  int _connGen = 0;
  // Latest message timestamp seen, used as `since` for reconnect gap-fill.
  String? _lastSeenIso;

  String _currentChannelId = '';
  // Empty default — getter below resolves to localized "TEAM CHAT"/"CHAT ECHIPĂ".
  String _currentChannelName = '';

  String get _displayChannelName =>
      _currentChannelName.isNotEmpty ? _currentChannelName : L10n.t('chat.title');
  List<Map<String, dynamic>> _teamUsers = [];
  List<Map<String, dynamic>> _groups = [];

  String get _senderName {
    final user = widget.authState?.user;
    final name = user?.fullName;
    if (name != null && name.isNotEmpty) return name.toUpperCase();
    final email = user?.email ?? '';
    return email.split('@').first.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    final teamName = widget.authState?.user?.teamName ?? 'general';
    _currentChannelId = '${teamName}_general';
    _ctrl.addListener(_onTextChange);
    _fetchTeamUsers();
    _subscribe();
  }

  Future<void> _fetchTeamUsers() async {
    try {
      final api = widget.authState?.api;
      if (api == null) return;
      final resUsers = await api.getList('/chat/users');
      final resGroups = await api.getList('/chat/groups');
      if (mounted) {
        setState(() {
          _teamUsers = List<Map<String, dynamic>>.from(resUsers);
          _groups = List<Map<String, dynamic>>.from(resGroups);
        });
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    }
  }

  void _switchChannel(String id, String name) {
    if (_currentChannelId == id) return;
    AppHaptics.selection();
    setState(() {
      _currentChannelId = id;
      _currentChannelName = name;
      _msgs.clear();
      _lastSeenIso = null;
    });
    _subscribe();
  }

  // ── Subscription lifecycle ─────────────────────────────────────────────────

  /// Tear down any current socket + pending reconnect, bump the generation,
  /// back-fill history, then open a fresh receive-only socket. Called on first
  /// load and on every channel switch.
  void _subscribe() {
    _connGen++;
    _teardownSocket();
    _reconnectTimer?.cancel();
    _backoff = const Duration(seconds: 2);
    if (mounted) setState(() => _status = _ConnStatus.connecting);
    final gen = _connGen;
    _loadHistory().then((_) {
      if (gen == _connGen) _connect(gen);
    });
  }

  void _teardownSocket() {
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  /// Back-fill messages from REST. On first load (no `_lastSeenIso`) it pulls the
  /// recent history; on a reconnect it passes `since=<lastSeenIso>` so only the
  /// gap is fetched and de-duped by id.
  Future<void> _loadHistory() async {
    final api = widget.authState?.api;
    if (api == null) return;
    try {
      final since = _lastSeenIso;
      final path = since != null && since.isNotEmpty
          ? '/chat/$_currentChannelId/messages?since=${Uri.encodeQueryComponent(since)}'
          : '/chat/$_currentChannelId/messages';
      final res = await api.getList(path);
      if (!mounted) return;
      final fetched = res
          .map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      setState(() {
        for (final m in fetched) {
          _mergeMessage(m);
        }
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('History load error: $e');
    }
  }

  /// Open the API Gateway WebSocket. Receive-only: messages are SENT over REST,
  /// the socket only carries fan-out pushes. Appends ?channel=&token= with the
  /// LOCAL access JWT (the $connect Lambda validates this token, not Cognito).
  void _connect(int gen) {
    if (gen != _connGen || !mounted) return;
    final token = widget.authState?.api.accessToken;
    final wsBase = AppConfig.wsConnectUrl;
    if (token == null || wsBase.isEmpty) {
      // No live transport configured (e.g. local dev with no WS URL). History +
      // REST send still function; surface an honest offline state.
      setState(() => _status = _ConnStatus.offline);
      return;
    }

    final uri = Uri.parse(
      '$wsBase?channel=${Uri.encodeQueryComponent(_currentChannelId)}'
      '&token=${Uri.encodeQueryComponent(token)}',
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      // Mark connected optimistically; API Gateway has no explicit open event on
      // the WebSocketChannel, and the $connect handshake already gates the URL.
      setState(() => _status = _ConnStatus.connected);
      _backoff = const Duration(seconds: 2);

      _channelSub = channel.stream.listen(
        (message) {
          if (gen != _connGen || !mounted) return;
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            setState(() => _mergeMessage(_Msg.fromJson(data)));
            _scrollToBottom();
          } catch (e) {
            debugPrint('Error parsing message: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _scheduleReconnect(gen);
        },
        onDone: () {
          debugPrint('WebSocket disconnected');
          _scheduleReconnect(gen);
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('WebSocket connect error: $e');
      _scheduleReconnect(gen);
    }
  }

  /// Reconnect with exponential backoff (2s → 30s). Before re-opening the
  /// socket it gap-fills any messages missed while disconnected via `since`.
  void _scheduleReconnect(int gen) {
    if (gen != _connGen || !mounted) return;
    _teardownSocket();
    setState(() => _status = _ConnStatus.reconnecting);
    final wait = _backoff;
    _backoff = Duration(
      seconds: (_backoff.inSeconds * 2).clamp(2, _maxBackoff.inSeconds),
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () {
      if (gen != _connGen || !mounted) return;
      _loadHistory().then((_) {
        if (gen == _connGen) _connect(gen);
      });
    });
  }

  /// Insert a message, de-duping by server id. A real (sent) message also clears
  /// any matching optimistic placeholder: same id wins, and an echoed message
  /// from me replaces my still-"sending" local copy of the same content.
  void _mergeMessage(_Msg incoming) {
    // Track newest timestamp for reconnect gap-fill.
    if (incoming.status == _MsgStatus.sent) {
      if (_lastSeenIso == null ||
          incoming.createdAt.compareTo(_lastSeenIso!) > 0) {
        _lastSeenIso = incoming.createdAt;
      }
    }

    final existing = _msgs.indexWhere((m) => m.id == incoming.id);
    if (existing >= 0) {
      // Already have this id — keep the authoritative (sent) version.
      if (incoming.status == _MsgStatus.sent) _msgs[existing] = incoming;
      return;
    }

    // Server echo of one of my optimistic sends: drop the placeholder.
    if (incoming.status == _MsgStatus.sent &&
        incoming.senderId == (widget.authState?.user?.id ?? '')) {
      final optimistic = _msgs.indexWhere((m) =>
          m.status == _MsgStatus.sending &&
          m.senderId == incoming.senderId &&
          m.text == incoming.text &&
          m.fileUrl == incoming.fileUrl);
      if (optimistic >= 0) {
        _msgs[optimistic] = incoming;
        return;
      }
    }

    _msgs.add(incoming);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChange() {
    final t = _ctrl.text.isNotEmpty;
    if (t != _typing) setState(() => _typing = t);
  }

  @override
  void dispose() {
    _connGen++;
    _reconnectTimer?.cancel();
    _teardownSocket();
    _ctrl
      ..removeListener(_onTextChange)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Sending (REST + optimistic) ────────────────────────────────────────────

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    AppHaptics.light();
    _ctrl.clear();
    await _sendMessage(content: text);
  }

  /// Optimistic send: render the message immediately as "sending", POST it over
  /// REST, then swap in the persisted server object (which carries the real id +
  /// timestamp + avatar). The WebSocket echo is de-duped by id in [_mergeMessage].
  Future<void> _sendMessage({String? content, String? fileUrl, String? fileType}) async {
    final api = widget.authState?.api;
    final myId = widget.authState?.user?.id ?? '';
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = _Msg(
      id: tempId,
      senderId: myId,
      text: content ?? '',
      sender: _senderName,
      time: _Msg._now(),
      senderAvatarUrl: widget.authState?.user?.avatarUrl,
      fileUrl: fileUrl,
      fileType: fileType,
      status: _MsgStatus.sending,
    );
    setState(() => _msgs.add(optimistic));
    _scrollToBottom();

    if (api == null) return;
    try {
      final res = await api.post('/chat/$_currentChannelId/send', body: {
        'content': content,
        'file_url': fileUrl,
        'file_type': fileType,
      });
      if (!mounted) return;
      final persisted = _Msg.fromJson(res);
      setState(() {
        final idx = _msgs.indexWhere((m) => m.id == tempId);
        if (idx >= 0) {
          // If the WS echo already landed (same server id present), drop the
          // placeholder instead of duplicating.
          if (_msgs.any((m) => m.id == persisted.id)) {
            _msgs.removeAt(idx);
          } else {
            _msgs[idx] = persisted;
          }
        } else {
          _mergeMessage(persisted);
        }
        if (_lastSeenIso == null ||
            persisted.createdAt.compareTo(_lastSeenIso!) > 0) {
          _lastSeenIso = persisted.createdAt;
        }
      });
    } catch (e) {
      debugPrint('Send error: $e');
      if (!mounted) return;
      // Keep the placeholder but mark it back to a retryable state by removing
      // it and surfacing an error, so the user knows it did not go through.
      setState(() => _msgs.removeWhere((m) => m.id == tempId));
      AppSnackbar.error(context,
          L10n.instance.isRomanian ? 'Trimitere eșuată' : 'Send failed');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final api = widget.authState?.api;
      if (api == null) return;

      // The ephemeral chat-file upload endpoint is intentionally retained (see
      // backend scope note); it returns a relative URL served by FastAPI.
      final res = await api.uploadMultipart(
        '/chat/upload',
        fileBytes: file.bytes!,
        fileName: file.name,
      );

      final fileUrl = res['url'] as String?;
      final fileType = res['type'] as String?;

      if (fileUrl != null) {
        final caption = _ctrl.text.trim();
        _ctrl.clear();
        await _sendMessage(
          content: caption.isNotEmpty ? caption : null,
          fileUrl: fileUrl,
          fileType: fileType,
        );
        if (mounted) {
          AppSnackbar.success(context,
              L10n.instance.isRomanian ? 'Imagine trimisă' : 'Image sent');
        }
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        AppSnackbar.error(context,
            L10n.instance.isRomanian ? 'Încărcare eșuată' : 'Upload failed');
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      currentTab: AppTab.chat,
      onTabSelected: widget.onTabSelected,
      onProfileTap: widget.onProfileTap,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(channelName: _displayChannelName, status: _status),
          _buildChannelsList(),
          const SizedBox(height: SpacingTokens.md),
          Expanded(child: _buildList()),
          if (_typing) _buildTypingHint(),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildChannelsList() {
    final teamName = widget.authState?.user?.teamName ?? 'general';
    final genId = '${teamName}_general';
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildChannelChip(
            id: genId,
            name: L10n.t('chat.title'),
            isSelected: _currentChannelId == genId,
          ),
          ..._groups.map((g) {
            final groupId = 'group_${g['id']}';
            return _buildChannelChip(
              id: groupId,
              name: '#${g['name']}'.toUpperCase(),
              isSelected: _currentChannelId == groupId,
            );
          }),
          ..._teamUsers.map((u) {
            final otherId = u['id'] as String;
            final myId = widget.authState?.user?.id ?? '';
            final ids = [myId, otherId]..sort();
            final dmId = 'dm_${ids[0]}_${ids[1]}';
            final rawName = u['full_name']?.toString().isNotEmpty == true
                ? u['full_name']
                : u['email'].toString().split('@')[0];
            final name = '@$rawName'.toUpperCase();
            return _buildChannelChip(
              id: dmId,
              name: name,
              isSelected: _currentChannelId == dmId,
            );
          }),
          Padding(
            padding: const EdgeInsets.only(left: SpacingTokens.sm),
            child: ActionChip(
              label: Icon(Icons.group_add, size: 18, color: context.colors.accent),
              backgroundColor: Colors.transparent,
              side: BorderSide(color: context.colors.accent),
              onPressed: _showCreateGroupDialog,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final groupNameCtrl = TextEditingController();
    final selectedUserIds = <String>{};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final c = context.colors;
          return AlertDialog(
            backgroundColor: c.surfaceHigh,
            title: Text(L10n.t('chat.createGroup'), style: TypographyTokens.body.copyWith(color: c.textPrimary, fontSize: 18)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: groupNameCtrl,
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      hintText: L10n.t('chat.groupName'),
                      hintStyle: TextStyle(color: c.textMuted),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.accent)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.colors.accent)),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: _teamUsers.map((u) {
                        final id = u['id'] as String;
                        final name = u['full_name']?.toString().isNotEmpty == true
                            ? u['full_name'].toString()
                            : u['email'].toString();
                        final isSelected = selectedUserIds.contains(id);
                        return CheckboxListTile(
                          title: Text(name, style: TextStyle(color: c.textPrimary)),
                          value: isSelected,
                          activeColor: context.colors.accent,
                          checkColor: context.colors.onAccent,
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedUserIds.add(id);
                              } else {
                                selectedUserIds.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L10n.t('chat.cancel'), style: TextStyle(color: c.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent),
                onPressed: () async {
                  final name = groupNameCtrl.text.trim();
                  if (name.isEmpty || selectedUserIds.isEmpty) return;

                  // Capture the navigator before the await so no dialog
                  // BuildContext is reached across the async gap.
                  final navigator = Navigator.of(ctx);
                  try {
                    final api = widget.authState?.api;
                    if (api != null) {
                      await api.post('/chat/groups', body: {
                        'name': name,
                        'member_ids': selectedUserIds.toList(),
                      });
                      await _fetchTeamUsers();
                    }
                  } catch (e) {
                    debugPrint('Error creating group: $e');
                  }
                  navigator.pop();
                  if (!mounted) return;
                  // Safe: this is the State's own context, guarded by `mounted`.
                  AppSnackbar.success(
                      context,
                      L10n.instance.isRomanian ? 'Grup creat' : 'Group created');
                },
                child: Text(L10n.t('chat.create'), style: TextStyle(color: context.colors.onAccent)),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildChannelChip({required String id, required String name, required bool isSelected}) {
    return Padding(
      padding: const EdgeInsets.only(right: SpacingTokens.sm),
      child: ActionChip(
        label: Text(name),
        backgroundColor: isSelected ? context.colors.accent : Colors.transparent,
        labelStyle: TextStyle(
          color: isSelected ? context.colors.onAccent : context.colors.textPrimary,
        ),
        side: BorderSide(color: context.colors.accent),
        onPressed: () => _switchChannel(id, name),
      ),
    );
  }

  Widget _buildList() {
    if (_msgs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 40, color: context.colors.textMuted),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              L10n.t('chat.empty'),
              style: TypographyTokens.sectionLabel
                  .copyWith(color: context.colors.textMuted),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
      itemCount: _msgs.length,
      separatorBuilder: (_, __) => const SizedBox(height: SpacingTokens.md),
      itemBuilder: (_, i) => _Bubble(
        msg: _msgs[i],
        isMe: _msgs[i].senderId == (widget.authState?.user?.id ?? ''),
      ),
    );
  }

  Widget _buildTypingHint() {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: SpacingTokens.xs, left: SpacingTokens.xxs),
      child: Row(
        children: [
          Container(width: 2, height: 14, color: context.colors.accent),
          const SizedBox(width: SpacingTokens.xs),
          Text(
            '$_senderName ${L10n.t('chat.typing')}',
            style: TypographyTokens.sectionLabel
                .copyWith(color: context.colors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      margin: const EdgeInsets.only(top: SpacingTokens.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: _uploading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: context.colors.accent))
                : Icon(Icons.attach_file, color: context.colors.textMuted),
            onPressed: _uploading ? null : _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: TypographyTokens.body
                  .copyWith(color: context.colors.textPrimary, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: L10n.t('chat.writeMessage'),
                hintStyle: TypographyTokens.body
                    .copyWith(color: context.colors.textMuted, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: SpacingTokens.sm, vertical: 14),
              ),
            ),
          ),
          _SendButton(onTap: _send),
        ],
      ),
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.channelName, required this.status});
  final String channelName;
  final _ConnStatus status;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                L10n.t('chat.channel'),
                style: TypographyTokens.sectionLabel
                    .copyWith(color: context.colors.accent),
              ),
              const Spacer(),
              _ConnectionIndicator(status: status),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(width: 3, height: 40, color: context.colors.accent),
              const SizedBox(width: SpacingTokens.md),
              Expanded(
                child: Text(
                  channelName,
                  style: TypographyTokens.displayHero.copyWith(fontSize: 32),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Connection status indicator ───────────────────────────────────────────────

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.status});
  final _ConnStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ro = L10n.instance.isRomanian;

    late final Color dot;
    late final String label;
    switch (status) {
      case _ConnStatus.connected:
        dot = c.positive;
        label = ro ? 'CONECTAT' : 'LIVE';
        break;
      case _ConnStatus.connecting:
        dot = c.accent;
        label = ro ? 'SE CONECTEAZĂ' : 'CONNECTING';
        break;
      case _ConnStatus.reconnecting:
        dot = c.accent;
        label = ro ? 'RECONECTARE' : 'RECONNECTING';
        break;
      case _ConnStatus.offline:
        dot = c.negative;
        label = ro ? 'OFFLINE' : 'OFFLINE';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flat square status dot — no glow, no radius, per Stoic-Analyst rules.
        Container(width: 8, height: 8, color: dot),
        const SizedBox(width: SpacingTokens.xs),
        Text(
          label,
          style: TypographyTokens.sectionLabel.copyWith(color: dot),
        ),
      ],
    );
  }
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.isMe});
  final _Msg msg;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final avatar = PlayerPhotoAvatar(
      photoUrl: msg.senderAvatarUrl ?? '',
      name: msg.sender,
      ringColor: c.accent,
      size: 32,
    );

    final bubbleColumn = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            right: isMe ? SpacingTokens.xxs : 0,
            left: isMe ? 0 : SpacingTokens.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${msg.sender}  ·  ${msg.time}',
                style: TypographyTokens.sectionLabel.copyWith(color: c.textMuted),
              ),
              if (msg.status == _MsgStatus.sending) ...[
                const SizedBox(width: SpacingTokens.xs),
                Text(
                  L10n.instance.isRomanian ? 'SE TRIMITE' : 'SENDING',
                  style: TypographyTokens.sectionLabel.copyWith(color: c.accent),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SpacingTokens.xxs),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.66,
          ),
          child: Opacity(
            opacity: msg.status == _MsgStatus.sending ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
                vertical: SpacingTokens.sm,
              ),
              decoration: BoxDecoration(
                color: isMe ? c.accentStrong : c.surfaceHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: isMe ? const Radius.circular(8) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(8),
                ),
                border: Border(
                  right: isMe
                      ? BorderSide(color: context.colors.accent, width: 2)
                      : BorderSide.none,
                  left: isMe
                      ? BorderSide.none
                      : BorderSide(color: context.colors.accent, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (msg.fileUrl != null)
                    Padding(
                      padding: EdgeInsets.only(
                          bottom: msg.text.isNotEmpty ? SpacingTokens.sm : 0),
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              insetPadding: EdgeInsets.zero,
                              child: Stack(
                                children: [
                                  InteractiveViewer(
                                    child: Center(
                                      child: Image.network(
                                        _buildFileUrl(msg.fileUrl!),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 20,
                                    right: 20,
                                    child: IconButton(
                                      icon: const Icon(Icons.close,
                                          color: Colors.white, size: 30),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            _buildFileUrl(msg.fileUrl!),
                            width: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.broken_image,
                                color: context.colors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  if (msg.text.isNotEmpty)
                    Text(
                      msg.text,
                      style: TypographyTokens.body.copyWith(
                          color: context.colors.textPrimary, fontSize: 16),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    // Lay out the avatar beside the bubble: on the left for others, on the right
    // for my own messages, so the conversation reads naturally.
    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isMe
          ? [
              Flexible(child: bubbleColumn),
              const SizedBox(width: SpacingTokens.sm),
              avatar,
            ]
          : [
              avatar,
              const SizedBox(width: SpacingTokens.sm),
              Flexible(child: bubbleColumn),
            ],
    );
  }

  static String _buildFileUrl(String path) {
    // Absolute (S3 / external) URLs are used as-is; relative paths from the
    // ephemeral /chat/upload endpoint are resolved against the API host.
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = AppConfig.apiBaseUrl.replaceAll('/api/v1', '');
    return '$base$path';
  }
}

// ─── Send button ──────────────────────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 48,
        color: context.colors.accent,
        alignment: Alignment.center,
        child: Icon(Icons.send_rounded,
            color: context.colors.onAccent, size: 20),
      ),
    );
  }
}
