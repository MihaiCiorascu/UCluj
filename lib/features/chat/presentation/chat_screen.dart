import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/theme/color_tokens.dart';
import '../../../core/theme/spacing_tokens.dart';
import '../../../core/theme/typography_tokens.dart';
import '../../../core/widgets/app_bottom_nav.dart';
import '../../../core/widgets/app_scaffold.dart';

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/config/app_config.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class _Msg {
  _Msg({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sender,
    required this.time,
    this.fileUrl,
    this.fileType,
  });

  final String id;
  final String senderId;
  final String text;
  final String sender;
  final String time;
  final String? fileUrl;
  final String? fileType;

  factory _Msg.fromJson(Map<String, dynamic> json) {
    String timeStr = _now();
    if (json['created_at'] != null) {
      try {
        final dt = DateTime.parse(json['created_at']).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return _Msg(
      id: json['id'] as String? ?? '',
      senderId: json['author_id'] as String? ?? '',
      text: json['content'] as String? ?? '',
      sender: _formatSender(json['author_name'] as String? ?? 'Unknown'),
      time: timeStr,
      fileUrl: json['file_url'] as String?,
      fileType: json['file_type'] as String?,
    );
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
  WebSocketChannel? _channel;
  
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
    _connectWebSocket();
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
    setState(() {
      _currentChannelId = id;
      _currentChannelName = name;
      _msgs.clear();
    });
    _channel?.sink.close();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    final token = widget.authState?.api.accessToken;
    if (token == null) return;

    final wsBaseUrl = AppConfig.apiBaseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsBaseUrl/chat/ws/$_currentChannelId?token=$token');

    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      (message) {
        if (!mounted) return;
        try {
          final data = jsonDecode(message);
          setState(() {
            // Check if we already have this message by ID
            final id = data['id'] as String?;
            if (id != null && _msgs.any((m) => m.id == id)) return;

            _msgs.add(_Msg.fromJson(data));
          });
          _scrollToBottom();
        } catch (e) {
          debugPrint('Error parsing message: $e');
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
      },
      onDone: () {
        debugPrint('WebSocket disconnected');
      },
    );
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
    _channel?.sink.close();
    _ctrl
      ..removeListener(_onTextChange)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'content': text,
      }));
    } else {
      // Fallback local append if WS not connected
      setState(() {
        _msgs.add(_Msg(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            senderId: widget.authState?.user?.id ?? '',
            text: text,
            sender: _senderName,
            time: _Msg._now()));
      });
      _scrollToBottom();
    }

    _ctrl.clear();
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

      final res = await api.uploadMultipart(
        '/chat/upload',
        fileBytes: file.bytes!,
        fileName: file.name,
      );

      final fileUrl = res['url'] as String?;
      final fileType = res['type'] as String?;

      if (fileUrl != null && _channel != null) {
        _channel!.sink.add(jsonEncode({
          'content': _ctrl.text.trim().isNotEmpty ? _ctrl.text.trim() : null,
          'file_url': fileUrl,
          'file_type': fileType,
        }));
        _ctrl.clear();
      }
    } catch (e) {
      debugPrint('Upload error: $e');
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
          _Header(channelName: _displayChannelName),
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
      height: 40,
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
              label: const Icon(Icons.group_add, size: 18, color: ColorTokens.accent),
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: ColorTokens.accent),
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
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(L10n.t('chat.createGroup'), style: TypographyTokens.body.copyWith(color: Colors.white, fontSize: 18)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: groupNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: L10n.t('chat.groupName'),
                      hintStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ColorTokens.accent)),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ColorTokens.accent)),
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
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          value: isSelected,
                          activeColor: ColorTokens.accent,
                          checkColor: ColorTokens.onAccent,
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
                child: Text(L10n.t('chat.cancel'), style: const TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ColorTokens.accent),
                onPressed: () async {
                  final name = groupNameCtrl.text.trim();
                  if (name.isEmpty || selectedUserIds.isEmpty) return;
                  
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
                  if (mounted) Navigator.pop(ctx);
                },
                child: Text(L10n.t('chat.create'), style: const TextStyle(color: ColorTokens.onAccent)),
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
        backgroundColor: isSelected ? ColorTokens.accent : Colors.transparent,
        labelStyle: TextStyle(
          color: isSelected ? ColorTokens.onAccent : ColorTokens.textPrimary,
        ),
        side: const BorderSide(color: ColorTokens.accent),
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
            const Icon(Icons.forum_outlined,
                size: 40, color: ColorTokens.textMuted),
            const SizedBox(height: SpacingTokens.sm),
            Text(
              L10n.t('chat.empty'),
              style: TypographyTokens.sectionLabel
                  .copyWith(color: ColorTokens.textMuted),
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
          Container(width: 2, height: 14, color: ColorTokens.accent),
          const SizedBox(width: SpacingTokens.xs),
          Text(
            '$_senderName ${L10n.t('chat.typing')}',
            style: TypographyTokens.sectionLabel
                .copyWith(color: ColorTokens.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      margin: const EdgeInsets.only(top: SpacingTokens.sm),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ColorTokens.divider, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: _uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: ColorTokens.accent))
                : const Icon(Icons.attach_file, color: ColorTokens.textMuted),
            onPressed: _uploading ? null : _pickFile,
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: TypographyTokens.body
                  .copyWith(color: ColorTokens.textPrimary, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: L10n.t('chat.writeMessage'),
                hintStyle: TypographyTokens.body
                    .copyWith(color: ColorTokens.textMuted, fontSize: 14),
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
  const _Header({required this.channelName});
  final String channelName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.t('chat.channel'),
            style: TypographyTokens.sectionLabel
                .copyWith(color: ColorTokens.accent),
          ),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(width: 3, height: 40, color: ColorTokens.accent),
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

// ─── Message bubble ───────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.isMe});
  final _Msg msg;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            right: isMe ? SpacingTokens.xxs : 0,
            left: isMe ? 0 : SpacingTokens.xxs,
          ),
          child: Text(
            '${msg.sender}  ·  ${msg.time}',
            style: TypographyTokens.sectionLabel
                .copyWith(color: ColorTokens.textMuted),
          ),
        ),
        const SizedBox(height: SpacingTokens.xxs),
        Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SpacingTokens.md,
                vertical: SpacingTokens.sm,
              ),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF0D2340) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: isMe ? const Radius.circular(8) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(8),
                ),
                border: Border(
                  right: isMe
                      ? const BorderSide(color: ColorTokens.accent, width: 2)
                      : BorderSide.none,
                  left: isMe
                      ? BorderSide.none
                      : const BorderSide(color: ColorTokens.accent, width: 2),
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
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image,
                                color: ColorTokens.textMuted),
                          ),
                        ),
                      ),
                    ),
                  if (msg.text.isNotEmpty)
                    Text(
                      msg.text,
                      style: TypographyTokens.body.copyWith(
                          color: ColorTokens.textPrimary, fontSize: 16),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _buildFileUrl(String path) {
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
        color: ColorTokens.accent,
        alignment: Alignment.center,
        child: const Icon(Icons.send_rounded,
            color: ColorTokens.onAccent, size: 20),
      ),
    );
  }
}
