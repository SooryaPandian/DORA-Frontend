import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

// Styles class for separation of concerns
class ChatStyles {
  static const EdgeInsets messageListPadding = EdgeInsets.all(8);
  static const EdgeInsets messageBubblePadding = EdgeInsets.all(12);
  static const EdgeInsets messageBubbleMargin = EdgeInsets.symmetric(vertical: 4, horizontal: 8);
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets usernamePadding = EdgeInsets.only(bottom: 4);

  static const double messageBorderRadius = 12;
  static const double dividerHeight = 1;

  static const Color myMessageColor = Colors.blueAccent;
  static const Color otherMessageColor = Colors.grey;
  static const Color myMessageTextColor = Colors.white;
  static const Color otherMessageTextColor = Colors.black;
  static const Color sendButtonColor = Colors.blue;
  static const Color usernameColor = Colors.grey;

  static const TextStyle messageTextStyle = TextStyle(fontSize: 16);
  static const TextStyle usernameTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static const InputDecoration messageInputDecoration = InputDecoration(
    hintText: "Type a message...",
    border: InputBorder.none,
  );
}

class ChatPage extends StatefulWidget {
  final String roomCode;
  final Map<String, String> userMap; // user_id -> username

  const ChatPage({
    super.key,
    required this.roomCode,
    required this.userMap,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  IO.Socket? socket;
  List<Map<String, dynamic>> messages = [];
  String? myUserId;
  String? myUsername;
  final TextEditingController _controller = TextEditingController();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  Future<void> _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    myUserId = prefs.getString("user_id");
    myUsername = prefs.getString("username");

    socket = IO.io(server, {
      "transports": ["websocket"],
      "autoConnect": false,
      "forceNew": true,
    });

    socket!.connect();

    socket!.onConnect((_) {
      socket!.emit("join_chat_room", {
        "user_id": myUserId,
        "room_code": widget.roomCode,
      });
    });

    // Listen for chat history
    socket!.on("chat_history", (data) {
      final history = (data["messages"] as List)
          .map((m) => {
        "user_id": m["user_id"],
        "message": m["message"],
        "timestamp": m["timestamp"],
      })
          .toList();
      setState(() {
        messages = history;
        loading = false;
      });
    });

    // Listen for new messages
    socket!.on("new_message", (data) {
      setState(() {
        messages.add({
          "user_id": data["user_id"],
          "message": data["message"],
          "timestamp": data["timestamp"],
        });
      });
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final msg = _controller.text.trim();
    socket?.emit("send_message", {
      "user_id": myUserId,
      "room_code": widget.roomCode,
      "message": msg,
    });

    _controller.clear();
  }

  String _getUsernameForMessage(String userId) {
    return widget.userMap[userId] ?? "Unknown User";
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMe = message["user_id"] == myUserId;
    final username = _getUsernameForMessage(message["user_id"]);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: ChatStyles.messageBubbleMargin,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Show username only for other users
            if (!isMe)
              Padding(
                padding: ChatStyles.usernamePadding,
                child: Text(
                  username,
                  style: ChatStyles.usernameTextStyle.copyWith(
                    color: ChatStyles.usernameColor,
                  ),
                ),
              ),
            Container(
              padding: ChatStyles.messageBubblePadding,
              decoration: BoxDecoration(
                color: isMe
                    ? ChatStyles.myMessageColor
                    : ChatStyles.otherMessageColor,
                borderRadius: BorderRadius.circular(ChatStyles.messageBorderRadius),
              ),
              child: Text(
                message["message"],
                style: ChatStyles.messageTextStyle.copyWith(
                  color: isMe
                      ? ChatStyles.myMessageTextColor
                      : ChatStyles.otherMessageTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      padding: ChatStyles.messageListPadding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: ChatStyles.inputPadding,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: ChatStyles.messageInputDecoration,
                onSubmitted: (_) => _sendMessage(),
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendMessage,
              color: ChatStyles.sendButtonColor,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Chat - Room ${widget.roomCode}"),
        elevation: 1,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(child: _buildMessagesList()),
          _buildMessageInput(),
        ],
      ),
    );
  }
}