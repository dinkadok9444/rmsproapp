import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../services/app_language.dart';

class ChatScreen extends StatefulWidget {
  final String ownerID;
  final String shopID;
  const ChatScreen({super.key, required this.ownerID, required this.shopID});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  static const _chatRoot = 'rms_chat_v4';

  final _lang = AppLanguage();
  final _rtdb = FirebaseDatabase.instance;
  final _firestore = FirebaseFirestore.instance;
  final _msgController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _privateScrollController = ScrollController();

  late TabController _tabController;

  // User info
  String _currentUserId = '';
  String _currentShopName = '';
  String _currentDisplayId = '';
  String _currentState = 'kelantan';

  // State
  int _mainTab = 0; // 0=Group, 1=Personal, 2=Status
  String _activeGroupRoom = '1malaysia';
  String? _activePrivateFriend;
  Map<String, dynamic> _usersCache = {};
  Map<String, Map<String, dynamic>> _recentChats = {};

  // Messages
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _privateMessages = [];

  // Listeners
  StreamSubscription? _roomSub;
  StreamSubscription? _privateSub;
  StreamSubscription? _usersSub;
  StreamSubscription? _recentSub;

  // Status
  List<Map<String, dynamic>> _statuses = [];
  StreamSubscription? _statusSub;
  String _activeStatusRoom = '1malaysia';
  final _statusInputController = TextEditingController();

  // Search
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _privateSub?.cancel();
    _usersSub?.cancel();
    _recentSub?.cancel();
    _statusSub?.cancel();
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _privateScrollController.dispose();
    _tabController.dispose();
    _statusInputController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final staffName = prefs.getString('rms_staff_name') ?? 'SUPERVISOR';

    try {
      final shopDoc = await _firestore.collection('shops_${widget.ownerID}').doc(widget.shopID).get();
      if (shopDoc.exists) {
        final data = shopDoc.data()!;
        final shopName = (data['shopName'] ?? data['namaKedai'] ?? staffName).toString().toUpperCase();
        final negeri = (data['negeri'] ?? data['daerah'] ?? 'Kelantan').toString();

        _currentShopName = shopName;
        _currentUserId = shopName;
        _currentDisplayId = widget.shopID.toUpperCase();
        _currentState = negeri.replaceAll(' ', '').toLowerCase();
      } else {
        _currentShopName = staffName.toUpperCase();
        _currentUserId = staffName.toUpperCase();
        _currentDisplayId = widget.shopID.toUpperCase();
      }
    } catch (_) {
      _currentShopName = staffName.toUpperCase();
      _currentUserId = staffName.toUpperCase();
      _currentDisplayId = widget.shopID.toUpperCase();
    }

    // Register user in RTDB
    final userRef = _rtdb.ref('$_chatRoot/users/$_currentUserId');
    final userSnap = await userRef.get();
    final updates = <String, dynamic>{
      'name': _currentShopName,
      'displayId': _currentDisplayId,
      'lastOnline': ServerValue.timestamp,
    };
    if (!userSnap.exists || userSnap.child('logo').value == null) {
      updates['logo'] = '';
    }
    await userRef.update(updates);

    _listenToUsers();
    _listenToRoom('1malaysia');
    _listenToRecentChats();

    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════
  // LISTENERS
  // ═══════════════════════════════════════

  void _listenToUsers() {
    _usersSub = _rtdb.ref('$_chatRoot/users').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (mounted) setState(() => _usersCache = data);
      }
    });
  }

  void _listenToRoom(String roomId) {
    _roomSub?.cancel();
    _activeGroupRoom = roomId;

    final clearedTimes = _getClearedTimes();
    final clearedAt = clearedTimes[roomId] ?? 0;

    _roomSub = _rtdb.ref('$_chatRoot/rooms/$roomId').orderByChild('timestamp').onValue.listen((event) {
      final list = <Map<String, dynamic>>[];
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        data.forEach((key, val) {
          final msg = Map<String, dynamic>.from(val as Map);
          msg['key'] = key;
          final ts = msg['timestamp'] ?? 0;
          if (ts > clearedAt) list.add(msg);
        });
        list.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
      }
      if (mounted) {
        setState(() => _messages = list);
        _scrollToBottom();
      }
    });
  }

  void _listenToPrivateRoom(String friendId) {
    _privateSub?.cancel();
    _activePrivateFriend = friendId;

    final roomId = _getPrivateRoomId(friendId);
    final clearedTimes = _getClearedTimes();
    final clearedAt = clearedTimes[roomId] ?? 0;

    _privateSub = _rtdb.ref('$_chatRoot/rooms/$roomId').orderByChild('timestamp').onValue.listen((event) {
      final list = <Map<String, dynamic>>[];
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        data.forEach((key, val) {
          final msg = Map<String, dynamic>.from(val as Map);
          msg['key'] = key;
          final ts = msg['timestamp'] ?? 0;
          if (ts > clearedAt) list.add(msg);
        });
        list.sort((a, b) => (a['timestamp'] ?? 0).compareTo(b['timestamp'] ?? 0));
      }
      if (mounted) {
        setState(() => _privateMessages = list);
        _scrollToBottomPrivate();
      }
    });
  }

  void _listenToRecentChats() {
    _recentSub = _rtdb.ref('$_chatRoot/recent/$_currentUserId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final map = <String, Map<String, dynamic>>{};
        data.forEach((key, val) {
          map[key] = Map<String, dynamic>.from(val as Map);
        });
        if (mounted) setState(() => _recentChats = map);
      } else {
        if (mounted) setState(() => _recentChats = {});
      }
    });
  }

  void _listenToStatuses(String room) {
    _statusSub?.cancel();
    _activeStatusRoom = room;

    _statusSub = _rtdb.ref('$_chatRoot/status/$room').onValue.listen((event) {
      final list = <Map<String, dynamic>>[];
      final oneDay = DateTime.now().millisecondsSinceEpoch - 86400000;
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        data.forEach((key, val) {
          final s = Map<String, dynamic>.from(val as Map);
          s['key'] = key;
          if ((s['timestamp'] ?? 0) > oneDay) list.add(s);
        });
        list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
      }
      if (mounted) setState(() => _statuses = list);
    });
  }

  // ═══════════════════════════════════════
  // SEND MESSAGES
  // ═══════════════════════════════════════

  Future<void> _sendGroupMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    await _rtdb.ref('$_chatRoot/rooms/$_activeGroupRoom').push().set({
      'senderId': _currentUserId,
      'senderName': _currentShopName,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _sendPrivateMessage() async {
    if (_activePrivateFriend == null) return;
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    final roomId = _getPrivateRoomId(_activePrivateFriend!);
    await _rtdb.ref('$_chatRoot/rooms/$roomId').push().set({
      'senderId': _currentUserId,
      'senderName': _currentShopName,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });

    // Update recent chats for both users
    await _rtdb.ref('$_chatRoot/recent/$_currentUserId/$_activePrivateFriend').set({
      'lastMsg': text,
      'timestamp': ServerValue.timestamp,
      'friendName': _getUserName(_activePrivateFriend!),
    });
    await _rtdb.ref('$_chatRoot/recent/$_activePrivateFriend/$_currentUserId').set({
      'lastMsg': text,
      'timestamp': ServerValue.timestamp,
      'friendName': _currentShopName,
    });
  }

  Future<void> _postStatus() async {
    final text = _statusInputController.text.trim();
    if (text.isEmpty) return;
    _statusInputController.clear();

    await _rtdb.ref('$_chatRoot/status/$_activeStatusRoom').push().set({
      'senderId': _currentUserId,
      'senderName': _currentShopName,
      'text': text,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> _deleteStatus(String key) async {
    await _rtdb.ref('$_chatRoot/status/$_activeStatusRoom/$key').remove();
  }

  Future<void> _likeStatus(String key) async {
    final likeRef = _rtdb.ref('$_chatRoot/status/$_activeStatusRoom/$key/likes/$_currentUserId');
    final snap = await likeRef.get();
    if (snap.exists) {
      await likeRef.remove();
    } else {
      await likeRef.set(true);
    }
  }

  // ═══════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════

  String _getPrivateRoomId(String friendId) {
    final ids = [_currentUserId, friendId]..sort();
    return ids.join('_');
  }

  String _getUserName(String userId) {
    final u = _usersCache[userId];
    if (u != null) return (u['name'] ?? userId).toString();
    return userId;
  }

  String _getUserLogo(String userId) {
    final u = _usersCache[userId];
    if (u != null) return (u['logo'] ?? '').toString();
    return '';
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp is int ? timestamp : 0);
    return DateFormat('HH:mm').format(dt);
  }

  Map<String, int> _getClearedTimes() {
    // Use SharedPreferences sync would be better, but for simplicity use a static map
    return {};
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _scrollToBottomPrivate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_privateScrollController.hasClients) {
        _privateScrollController.animateTo(_privateScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final snap = await _rtdb.ref('$_chatRoot/users').get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);
    final results = <Map<String, dynamic>>[];
    data.forEach((key, val) {
      if (key == _currentUserId) return;
      final u = Map<String, dynamic>.from(val as Map);
      u['uid'] = key;
      final name = (u['name'] ?? '').toString().toLowerCase();
      final displayId = (u['displayId'] ?? '').toString().toLowerCase();
      if (name.contains(query.toLowerCase()) || displayId.contains(query.toLowerCase())) {
        results.add(u);
      }
    });
    if (mounted) setState(() => _searchResults = results);
  }

  // ═══════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_currentUserId.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Column(children: [
      // Top tabs: Group | Personal | Status
      _buildTopTabs(),
      Expanded(child: _mainTab == 0
          ? _buildGroupChat()
          : _mainTab == 1
              ? (_activePrivateFriend != null ? _buildPrivateChatView() : _buildPersonalList())
              : _buildStatusView(),
      ),
    ]);
  }

  Widget _buildTopTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        _topTab(0, FontAwesomeIcons.users, 'Group'),
        _topTab(1, FontAwesomeIcons.commentDots, 'Personal'),
        _topTab(2, FontAwesomeIcons.circleInfo, 'Status'),
      ]),
    );
  }

  Widget _topTab(int index, IconData icon, String label) {
    final isActive = _mainTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _mainTab = index;
            if (index == 0) _listenToRoom(_activeGroupRoom);
            if (index == 1) { _activePrivateFriend = null; _privateSub?.cancel(); }
            if (index == 2) _listenToStatuses(_activeStatusRoom);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isActive ? AppColors.primary : Colors.transparent, width: 3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FaIcon(icon, size: 12, color: isActive ? AppColors.primary : AppColors.textDim),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: isActive ? AppColors.primary : AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // GROUP CHAT
  // ═══════════════════════════════════════

  Widget _buildGroupChat() {
    return Column(children: [
      // Sub-tabs: 1 MALAYSIA | NEGERI
      Container(
        color: AppColors.bg,
        child: TabBar(
          controller: _tabController,
          onTap: (i) {
            final room = i == 0 ? '1malaysia' : _currentState;
            _listenToRoom(room);
          },
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textDim,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          tabs: [
            const Tab(text: '1 MALAYSIA'),
            Tab(text: _currentState.toUpperCase()),
          ],
        ),
      ),
      // Messages
      Expanded(child: Container(
        color: const Color(0xFFF0F2F5),
        child: _messages.isEmpty
            ? Center(child: Text(_lang.get('ch_tiada_mesej'), style: TextStyle(color: AppColors.textDim, fontSize: 12)))
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) => _buildMessageBubble(_messages[i]),
              ),
      )),
      // Input
      _buildChatInput(_sendGroupMessage),
    ]);
  }

  // ═══════════════════════════════════════
  // PERSONAL LIST
  // ═══════════════════════════════════════

  Widget _buildPersonalList() {
    final entries = _recentChats.entries.toList()
      ..sort((a, b) => (b.value['timestamp'] ?? 0).compareTo(a.value['timestamp'] ?? 0));

    return Stack(children: [
      entries.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              FaIcon(FontAwesomeIcons.commentSlash, size: 40, color: AppColors.textDim.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(_lang.get('ch_tiada_perbualan'), style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const SizedBox(height: 4),
              Text(_lang.get('ch_tekan_plus'), style: TextStyle(color: AppColors.textDim, fontSize: 11)),
            ]))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final friendId = entries[i].key;
                final data = entries[i].value;
                final friendName = data['friendName'] ?? _getUserName(friendId);
                final lastMsg = data['lastMsg'] ?? '';
                final time = _formatTime(data['timestamp']);
                final logo = _getUserLogo(friendId);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.border,
                    backgroundImage: logo.isNotEmpty ? MemoryImage(base64Decode(logo.split(',').last)) : null,
                    child: logo.isEmpty ? FaIcon(FontAwesomeIcons.store, size: 14, color: AppColors.textDim) : null,
                  ),
                  title: Text(friendName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  subtitle: Text(lastMsg, style: const TextStyle(fontSize: 12, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(time, style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
                  onTap: () {
                    _listenToPrivateRoom(friendId);
                    setState(() {});
                  },
                );
              },
            ),
      // FAB
      Positioned(
        bottom: 16, right: 16,
        child: FloatingActionButton(
          backgroundColor: AppColors.primary,
          onPressed: _showSearchUserDialog,
          child: const FaIcon(FontAwesomeIcons.commentMedical, size: 18, color: Colors.white),
        ),
      ),
    ]);
  }

  // ═══════════════════════════════════════
  // PRIVATE CHAT VIEW
  // ═══════════════════════════════════════

  Widget _buildPrivateChatView() {
    final friendName = _getUserName(_activePrivateFriend!);
    final friendLogo = _getUserLogo(_activePrivateFriend!);

    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              _privateSub?.cancel();
              setState(() => _activePrivateFriend = null);
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
              child: const FaIcon(FontAwesomeIcons.arrowLeft, size: 14, color: AppColors.textSub),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.border,
            backgroundImage: friendLogo.isNotEmpty ? MemoryImage(base64Decode(friendLogo.split(',').last)) : null,
            child: friendLogo.isEmpty ? FaIcon(FontAwesomeIcons.store, size: 10, color: AppColors.textDim) : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(friendName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text(_activePrivateFriend!, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontFamily: 'monospace')),
          ])),
        ]),
      ),
      // Messages
      Expanded(child: Container(
        color: const Color(0xFFF0F2F5),
        child: _privateMessages.isEmpty
            ? Center(child: Text(_lang.get('ch_mulakan'), style: TextStyle(color: AppColors.textDim, fontSize: 12)))
            : ListView.builder(
                controller: _privateScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _privateMessages.length,
                itemBuilder: (ctx, i) => _buildMessageBubble(_privateMessages[i]),
              ),
      )),
      _buildChatInput(_sendPrivateMessage),
    ]);
  }

  // ═══════════════════════════════════════
  // STATUS VIEW
  // ═══════════════════════════════════════

  Widget _buildStatusView() {
    return Column(children: [
      // Room selector
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Text(_lang.get('ch_paparan'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSub)),
          const SizedBox(width: 8),
          _statusRoomChip('1 MALAYSIA', '1malaysia'),
          const SizedBox(width: 6),
          _statusRoomChip(_currentState.toUpperCase(), _currentState),
          const SizedBox(width: 6),
          _statusRoomChip('PRIVATE', 'private'),
        ]),
      ),
      // Input
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.white,
        child: Row(children: [
          Expanded(child: TextField(
            controller: _statusInputController,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: _lang.get('ch_apa_fikir'),
              hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
              filled: true, fillColor: AppColors.bg, isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _postStatus,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: Text(_lang.get('ch_kongsi'), style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
      const Divider(height: 1),
      // Status list
      Expanded(child: _statuses.isEmpty
          ? Center(child: Text(_lang.get('ch_tiada_status'), style: TextStyle(color: AppColors.textDim, fontSize: 12)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _statuses.length,
              itemBuilder: (ctx, i) => _buildStatusCard(_statuses[i]),
            ),
      ),
    ]);
  }

  Widget _statusRoomChip(String label, String value) {
    final isActive = _activeStatusRoom == value;
    return GestureDetector(
      onTap: () {
        setState(() => _activeStatusRoom = value);
        _listenToStatuses(value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? AppColors.primary : AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isActive ? Colors.white : AppColors.textMuted)),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> status) {
    final isMe = status['senderId'] == _currentUserId;
    final senderName = status['senderName'] ?? 'Unknown';
    final text = status['text'] ?? '';
    final time = _formatTime(status['timestamp']);
    final key = status['key'] ?? '';
    final likes = status['likes'] is Map ? (status['likes'] as Map).length : 0;
    final isLiked = status['likes'] is Map && (status['likes'] as Map).containsKey(_currentUserId);
    final logo = _getUserLogo(status['senderId'] ?? '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.border,
          backgroundImage: logo.isNotEmpty ? MemoryImage(base64Decode(logo.split(',').last)) : null,
          child: logo.isEmpty ? FaIcon(FontAwesomeIcons.store, size: 12, color: AppColors.textDim) : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(senderName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            Text(time, style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
          ]),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.4)),
          const SizedBox(height: 8),
          Row(children: [
            _statusActionBtn(isLiked ? Icons.favorite : Icons.favorite_border, '$likes', isLiked ? AppColors.red : AppColors.textDim, () => _likeStatus(key)),
            if (!isMe) ...[
              const SizedBox(width: 8),
              _statusActionBtn(Icons.reply, 'Reply', AppColors.textDim, () {
                _listenToPrivateRoom(status['senderId']);
                setState(() { _mainTab = 1; });
              }),
            ],
            if (isMe) ...[
              const SizedBox(width: 8),
              _statusActionBtn(Icons.delete_outline, 'Padam', AppColors.red, () => _deleteStatus(key)),
            ],
          ]),
        ])),
      ]),
    );
  }

  Widget _statusActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════
  // MESSAGE BUBBLE
  // ═══════════════════════════════════════

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isMine = msg['senderId'] == _currentUserId;
    final senderName = msg['senderName'] ?? 'Unknown';
    final text = msg['text'] ?? '';
    final time = _formatTime(msg['timestamp']);
    final logo = _getUserLogo(msg['senderId'] ?? '');

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.border,
                backgroundImage: logo.isNotEmpty ? MemoryImage(base64Decode(logo.split(',').last)) : null,
                child: logo.isEmpty ? FaIcon(FontAwesomeIcons.store, size: 8, color: AppColors.textDim) : null,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                decoration: BoxDecoration(
                  color: isMine ? const Color(0xFFDCF8C6) : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMine ? 12 : 2),
                    bottomRight: Radius.circular(isMine ? 2 : 12),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3, offset: const Offset(0, 1))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!isMine) Text(senderName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  if (!isMine) const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary, height: 1.3)),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(time, style: const TextStyle(fontSize: 9.5, color: AppColors.textDim)),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════
  // CHAT INPUT
  // ═══════════════════════════════════════

  Widget _buildChatInput(VoidCallback onSend) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        Expanded(child: TextField(
          controller: _msgController,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: _lang.get('ch_taip_mesej'),
            hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 13),
            filled: true, fillColor: AppColors.bg, isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: const Center(child: FaIcon(FontAwesomeIcons.paperPlane, size: 14, color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════
  // SEARCH USER DIALOG
  // ═══════════════════════════════════════

  void _showSearchUserDialog() {
    _searchController.clear();
    _searchResults = [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setS) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(_lang.get('ch_cari_rakan'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Taip ID atau Nama Kedai...',
                hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textDim),
                filled: true, fillColor: AppColors.bg, isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (q) async {
                await _searchUsers(q);
                setS(() {});
              },
            ),
            const SizedBox(height: 10),
            Expanded(child: _searchResults.isEmpty
                ? Center(child: Text(_searchController.text.isEmpty ? 'Taip untuk cari...' : 'Tiada hasil', style: const TextStyle(color: AppColors.textDim, fontSize: 12)))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (ctx3, i) {
                      final u = _searchResults[i];
                      final uid = u['uid'] ?? '';
                      final name = u['name'] ?? uid;
                      final displayId = u['displayId'] ?? uid;
                      final logo = (u['logo'] ?? '').toString();

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.border,
                          backgroundImage: logo.isNotEmpty ? MemoryImage(base64Decode(logo.split(',').last)) : null,
                          child: logo.isEmpty ? FaIcon(FontAwesomeIcons.store, size: 12, color: AppColors.textDim) : null,
                        ),
                        title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        subtitle: Text(displayId, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontFamily: 'monospace')),
                        onTap: () {
                          Navigator.pop(ctx);
                          _listenToPrivateRoom(uid);
                          setState(() {});
                        },
                      );
                    },
                  ),
            ),
          ]),
        );
      }),
    );
  }
}
