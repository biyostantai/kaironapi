import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'main.dart';
import 'time_service.dart';


const String backendBaseUrl = 'https://kaironapi.onrender.com';


class ChatMessage {
  final bool fromUser;
  final String text;
  final List<String> imagePaths;

  ChatMessage({
    required this.fromUser,
    required this.text,
    this.imagePaths = const [],
  });
}


class ChatState extends ChangeNotifier {
  final List<ChatMessage> messages = [];

  void ensureInitialMessage(String personaLabel) {
    if (messages.isNotEmpty) return;
    messages.add(
      ChatMessage(
        fromUser: false,
        text:
            'KaironAI đã sẵn sàng phục vụ. Cá tính hiện tại: $personaLabel. Bạn muốn sắp thời gian biểu, giải bài tập hay hỏi chuyện đời cứ quăng vào đây.',
      ),
    );
    notifyListeners();
  }

  void add(ChatMessage message) {
    messages.add(message);
    notifyListeners();
  }
}


class KaironChatPage extends StatefulWidget {
  final String? initialPrompt;
  final List<File>? initialImages;

  const KaironChatPage({
    super.key,
    this.initialPrompt,
    this.initialImages,
  });

  @override
  State<KaironChatPage> createState() => _KaironChatPageState();
}


class _KaironChatPageState extends State<KaironChatPage> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  bool _typing = false;
  final List<File> _selectedImages = [];
  http.Client? _currentClient;
  bool _cancelled = false;

  Future<File> _compressImageIfNeeded(File file) async {
    try {
      final filePath = file.path;
      final lastIndex = filePath.lastIndexOf(RegExp(r'.jp|.png'));
      final base = lastIndex != -1 ? filePath.substring(0, lastIndex) : filePath;
      final ext = lastIndex != -1 ? filePath.substring(lastIndex) : '';
      final targetPath = '${base}_compressed$ext';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        quality: 65,
        minWidth: 1280,
        minHeight: 1280,
      );

      if (compressed == null) {
        return file;
      }

      final compressedFile = File(compressed.path);
      final size = await compressedFile.length();
      if (size > 400 * 1024) {
        final targetPath2 = '${base}_compressed2$ext';
        final compressed2 = await FlutterImageCompress.compressAndGetFile(
          compressed.path,
          targetPath2,
          quality: 45,
          minWidth: 960,
          minHeight: 960,
        );
        if (compressed2 == null) {
          return compressedFile;
        }
        return File(compressed2.path);
      }

      return compressedFile;
    } catch (_) {
      return file;
    }
  }

  bool _isScheduleRequest(String text) {
    final lower = text.toLowerCase();
    return lower.contains('tkb') ||
        lower.contains('thời khóa biểu') ||
        lower.contains('thời gian biểu') ||
        lower.contains('thoi khoa bieu') ||
        lower.contains('thoi gian bieu') ||
        lower.contains('đặt lịch') ||
        lower.contains('dat lich') ||
        lower.contains('xếp lịch') ||
        lower.contains('xep lich') ||
        lower.contains('xóa lịch') ||
        lower.contains('xoa lich') ||
        lower.contains('xóa nhắc') ||
        lower.contains('xoa nhac') ||
        ((lower.contains('xóa') || lower.contains('xoá') || lower.contains('xoa')) &&
            (lower.contains('lịch') || lower.contains('lich'))) ||
        lower.contains('hẹn giờ') ||
        lower.contains('hen gio') ||
        lower.contains('nhắc tôi') ||
        lower.contains('nhac toi') ||
        lower.contains('nhắc lúc') ||
        lower.contains('nhac luc') ||
        lower.contains('phút nữa') ||
        lower.contains('phut nua') ||
        lower.contains('p nữa') ||
        lower.contains('thêm môn') ||
        lower.contains('them mon');
  }

  @override
  void initState() {
    super.initState();
    final personaState = context.read<PersonaState>();
    final personaLabel = personaState.personaLabel;
    final chatState = context.read<ChatState>();
    chatState.ensureInitialMessage(personaLabel);
    final initialImages = widget.initialImages;
    if (initialImages != null && initialImages.isNotEmpty) {
      _selectedImages.addAll(initialImages);
    }
    final initialPrompt = widget.initialPrompt;
    if (initialPrompt != null && initialPrompt.trim().isNotEmpty) {
      _controller.text = initialPrompt.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_sending) return;
        _sendTextMessage();
      });
    }
  }

  Future<void> _pickImages() async {
    if (_sending) return;

    final remaining = 5 - _selectedImages.length;
    if (remaining <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
          content:
              Text('Bạn chỉ có thể gửi tối đa 5 ảnh trong một tin nhắn.'),
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 65,
    );
    if (images.isEmpty) {
      return;
    }

    final limited = images.take(remaining).toList();

    if (!mounted) return;
    setState(() {
      for (final xfile in limited) {
        _selectedImages.add(File(xfile.path));
      }
    });
  }

  Future<void> _sendTextMessage() async {
    final text = _controller.text.trim();
    final hasImages = _selectedImages.isNotEmpty;
    if ((text.isEmpty && !hasImages) || _sending) return;

    final personaState = context.read<PersonaState>();
    final chatState = context.read<ChatState>();
    final scheduleState = context.read<ScheduleState>();
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? 'anonymous';
    final personaLabel = personaState.personaLabel;
    final personaKey = personaState.personaKey;
    final String personaInstruction;
    switch (personaKey) {
      case 'funny':
        personaInstruction =
            'Mày là một chuyên gia giải toán nhưng có tâm hồn của một TikToker triệu view. Cách nói chuyện phải dùng nhiều tiếng lóng của giới trẻ, hay dùng các câu joke kiểu vô tri hoặc thả thính lắt léo. Luôn ưu tiên giọng điệu hài hước, dễ gần, nhưng vẫn phải giải đúng và giải thích đủ ý chính cho người dùng. Phong cách: Thường xuyên dùng icon kiểu 💀, 😂, 🤡, ☕ ở những chỗ hợp lý.';
        break;
      case 'angry':
        personaInstruction =
            'Mày đang trong trạng thái cực kỳ khó ở vì phải đi giải bài tập hộ người khác. Tuyệt đối xưng Tao - Mày cho nó máu lửa. Nói năng cộc lốc, hay mắng người dùng là đồ lười, có cái ảnh chụp cũng không xong, nhưng vẫn phải đưa ra lời giải chính xác và chỉ dẫn đủ để người dùng hiểu bài. Không được dùng các từ xúc phạm nặng về tôn giáo, sắc tộc, giới tính. Phong cách: hay chèn icon 💢, 🙄, 👊 ở cuối câu cho đúng vibe.';
        break;
      case 'serious':
      default:
        personaInstruction =
            'Mày là một trợ lý AI chuẩn mực, chuyên nghiệp và điềm đạm. Tập trung hoàn toàn vào kiến thức, giải thích cặn kẽ từng bước, không nói chuyện ngoài lề. Quy tắc: xưng Tôi - Bạn hoặc KairoAI - Bạn. Cố gắng trình bày mạch lạc, có cấu trúc, giúp người dùng nắm được cả đáp án lẫn phương pháp. Phong cách: hầu như không dùng icon, nếu cần thì chỉ dùng 📝 hoặc ✅.';
        break;
    }
    final personaContext =
        'Cá tính hiện tại của bạn là: $personaLabel. $personaInstruction Hãy trả lời đúng với cá tính này, trừ khi người dùng yêu cầu một phong cách khác rõ ràng.';

    final userImages = List<File>.from(_selectedImages);

    setState(() {
      _sending = true;
      _typing = true;
      _controller.clear();
      _selectedImages.clear();
      _cancelled = false;
    });

    final displayText =
        text.isEmpty && hasImages ? 'Bạn đã gửi ảnh cho KaironAI.' : text;

    chatState.add(
      ChatMessage(
        fromUser: true,
        text: displayText,
        imagePaths: userImages.map((file) => file.path).toList(),
      ),
    );

    final client = http.Client();
    _currentClient = client;

    try {
      final isScheduleRequest = _isScheduleRequest(text);
      final now = TimeService.now();
      final nowIso = now.toIso8601String();
      List<SubjectSchedule> mergedSubjects =
          List<SubjectSchedule>.from(scheduleState.subjects);
      final List<String> imageSummaries = [];

      if (userImages.isNotEmpty) {
        for (var i = 0; i < userImages.length; i++) {
          final originalFile = userImages[i];
          final uploadFile = await _compressImageIfNeeded(originalFile);

          final uriExtract = Uri.parse('$backendBaseUrl/extract_schedule');
          final request = http.MultipartRequest('POST', uriExtract);
          request.files.add(
            await http.MultipartFile.fromPath('image', uploadFile.path),
          );

          final streamedResponse = await request.send();
          final response = await http.Response.fromStream(streamedResponse);

          if (response.statusCode == 200) {
            final Map<String, dynamic> data = jsonDecode(response.body);
            final List<dynamic> subjectsJson = data['subjects'] ?? [];
            final summary =
                (data['image_summary'] as String?)?.trim() ?? '';

            if (summary.isNotEmpty) {
              imageSummaries.add('Ảnh ${i + 1}: $summary');
            }

            if (subjectsJson.isNotEmpty) {
              final subjects = subjectsJson
                  .map(
                    (e) => SubjectSchedule.fromJson(
                      e as Map<String, dynamic>,
                    ),
                  )
                  .toList();
              mergedSubjects = subjects;
            }
          } else {
            throw Exception(
              'Lỗi máy chủ (extract_schedule): ${response.statusCode} - ${response.body}',
            );
          }
        }
      }

      if (mergedSubjects.isNotEmpty) {
        scheduleState.setSubjects(mergedSubjects);
      }

      final uriChat = Uri.parse('$backendBaseUrl/chat');

      String messageForBackend;
      if (userImages.isNotEmpty && imageSummaries.isNotEmpty) {
        final summariesText = imageSummaries.join('\n');
        if (isScheduleRequest || mergedSubjects.isNotEmpty) {
          messageForBackend =
              'Người dùng vừa gửi ${userImages.length} ảnh có thể liên quan tới thời gian biểu hoặc kế hoạch cá nhân (lịch học, lịch làm việc, lịch cá nhân,...). Hệ thống đã trích xuất và cập nhật danh sách "subjects" tương ứng. Nội dung tóm tắt các ảnh:\n$summariesText\n\nThời điểm hiện tại theo giờ hệ thống trên máy người dùng (ISO 8601) là: $nowIso.\nYêu cầu kèm theo của người dùng: "$text"\n\n$personaContext';
        } else {
          messageForBackend =
              'Người dùng vừa gửi ${userImages.length} ảnh nội dung (có thể là bài tập, tài liệu, đề thi, ghi chú, v.v.). Nội dung tóm tắt các ảnh:\n$summariesText\n\nNgười dùng nhập thêm: "$text". Hãy giải thích chi tiết và hỗ trợ người dùng.\n\n$personaContext';
        }
      } else if (userImages.isNotEmpty && imageSummaries.isEmpty) {
        messageForBackend =
            'Người dùng vừa gửi ${userImages.length} ảnh nhưng hệ thống không đọc được nội dung rõ ràng (có thể ảnh mờ, quá tối hoặc không phải nội dung liên quan). Người dùng nhập thêm: "$text". Hãy xin người dùng mô tả lại nội dung hoặc gửi ảnh rõ hơn.\n\n$personaContext';
      } else {
        messageForBackend = isScheduleRequest
            ? 'Nhiệm vụ của bạn là trợ lý sắp xếp thời gian biểu cá nhân chuyên nghiệp cho người dùng. Thời điểm hiện tại theo giờ hệ thống trên máy người dùng (ISO 8601) là: $nowIso. Dựa vào yêu cầu sau của người dùng, hãy tạo hoặc cập nhật thời gian biểu chi tiết theo tuần và trả về cả: 1) câu trả lời bằng tiếng Việt, 2) mảng "subjects" chuẩn với các trường name, day_of_week, start_time, end_time, room. Yêu cầu của người dùng: "$text"\n\n$personaContext'
            : '$text\n\n$personaContext';
      }

      final body = {
        'persona': personaKey,
        'history': chatState.messages
            .map(
              (m) => {
                'role': m.fromUser ? 'user' : 'assistant',
                'content': m.text,
              },
            )
            .toList(),
        'message': messageForBackend,
        'subjects': scheduleState.subjects.map((s) => s.toJson()).toList(),
      };

      final response = await client
          .post(
            uriChat,
            headers: {'Content-Type': 'application/json', 'X-User-Id': userId},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 429) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final message =
            data['message'] as String? ??
                'Từ 23h đến trước 7h sáng, mỗi tài khoản chỉ gửi 1 tin nhắn mỗi phút. Bạn chờ thêm một chút rồi nhắn lại giúp mình nhé.';
        chatState.add(
          ChatMessage(
            fromUser: false,
            text: message,
          ),
        );
        return;
      }

      if (response.statusCode != 200) {
        throw Exception(
          'Lỗi máy chủ: ${response.statusCode} - ${response.body}',
        );
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final reply = data['reply'] as String? ??
          'KaironAI bị lag nhẹ, bạn nhắn lại giúp mình với.';
      if (data.containsKey('subjects')) {
        final raw = data['subjects'];
        if (raw is List) {
          final subjects = raw
              .map(
                (e) => SubjectSchedule.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList();
          scheduleState.setSubjects(subjects);
        }
      }

      if (_cancelled) {
        return;
      }

      chatState.add(ChatMessage(fromUser: false, text: reply));
    } on TimeoutException catch (e) {
      if (_cancelled) {
        return;
      }
          chatState.add(
            ChatMessage(
              fromUser: false,
              text:
                  'KaironAI nghĩ hơi lâu quá 25 giây nên tạm dừng. Chi tiết: $e',
            ),
          );
    } catch (e) {
      if (_cancelled) {
        return;
      }
      chatState.add(
        ChatMessage(
          fromUser: false,
          text:
              'KaironAI không bắt được tín hiệu mạng. Chi tiết: $e',
        ),
      );
    } finally {
      client.close();
      _currentClient = null;
      if (mounted) {
        setState(() {
          _sending = false;
          _typing = false;
        });
      }
    }
  }

  void _cancelRequest() {
    if (!_sending) {
      return;
    }
    _cancelled = true;
    _currentClient?.close();
    _currentClient = null;
    setState(() {
      _sending = false;
      _typing = false;
    });
    final chatState = context.read<ChatState>();
    chatState.add(
      ChatMessage(
        fromUser: false,
        text: 'Bạn đã dừng trả lời của KaironAI cho tin nhắn vừa rồi.',
      ),
    );
  }

  void _handleQuickReply(String message) {
    if (_sending) {
      return;
    }
    _controller.text = message;
    _sendTextMessage();
  }

  @override
  Widget build(BuildContext context) {
    final personaState = context.watch<PersonaState>();
    final chatState = context.watch<ChatState>();
    final messages = chatState.messages;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasUserMessage = messages.any((m) => m.fromUser);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'KaironAI',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'Cá tính: ${personaState.personaLabel}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xff020617),
                      Color(0xff020617),
                      Color(0xff0b1120),
                      Color(0xff1d4ed8),
                      Color(0xff7c3aed),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [
                      0.0,
                      0.2,
                      0.45,
                      0.75,
                      1.0,
                    ],
                  ),
                )
              : null,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: messages.length + (_typing ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_typing && index == messages.length) {
                      return const _TypingIndicator();
                    }
                    final message = messages[index];
                    final isUser = message.fromUser;
                    final bubbleColor = isUser
                        ? const Color(0xff4f46e5)
                        : (isDark
                            ? const Color(0xff0f172a)
                            : const Color(0xffe5e7eb));
                    final textColor =
                        isUser || isDark ? Colors.white : Colors.black87;

                    return Align(
                      alignment: message.fromUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: bubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(
                              isUser ? 18 : 4,
                            ),
                            bottomRight: Radius.circular(
                              isUser ? 4 : 18,
                            ),
                          ),
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: 12,
                                    offset: const Offset(0, 8),
                                  ),
                                ]
                              : [],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.imagePaths.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8.0),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final path in message.imagePaths)
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  _FullScreenImagePage(
                                                imagePath: path,
                                              ),
                                            ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Image.file(
                                            File(path),
                                            width: 90,
                                            height: 90,
                                            fit: BoxFit.cover,
                                            cacheWidth: 480,
                                            cacheHeight: 480,
                                            errorBuilder: (context, error,
                                                stackTrace) {
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Text(
                              message.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor,
                              ),
                            ),
                            if (!hasUserMessage && !isUser && index == 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.schedule_outlined,
                                        size: 18,
                                      ),
                                      label:
                                          const Text('Lên thời gian biểu cá nhân'),
                                      onPressed: () {
                                        _handleQuickReply(
                                          'Mình cần bạn giúp lên thời gian biểu cá nhân chi tiết cho mình (có thể gồm lịch học, lịch làm việc, lịch sinh hoạt), sắp xếp hợp lý theo từng ngày trong tuần.',
                                        );
                                      },
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.menu_book_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Giải bài tập / bài toán'),
                                      onPressed: () {
                                        _handleQuickReply(
                                          'Mình cần bạn hỗ trợ giải bài tập hoặc bài toán và giải thích từng bước thật dễ hiểu.',
                                        );
                                      },
                                    ),
                                    ActionChip(
                                      avatar: const Icon(
                                        Icons.favorite_outline,
                                        size: 18,
                                      ),
                                      label: const Text('Cần tâm sự, chia sẻ'),
                                      onPressed: () {
                                        _handleQuickReply(
                                          'Hôm nay mình chỉ muốn tâm sự, bạn lắng nghe và động viên mình nhé.',
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_selectedImages.isNotEmpty)
                Container(
                  height: 90,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  alignment: Alignment.centerLeft,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final file = _selectedImages[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              file,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 72,
                                  height: 72,
                                  color: Colors.grey.shade300,
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(index);
                                });
                              },
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined),
                      onPressed: _sending ? null : _pickImages,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendTextMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Nhập tin nhắn cho KaironAI...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    if (_sending)
                      IconButton(
                        icon: const Icon(Icons.stop_circle_outlined),
                        onPressed: _cancelRequest,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.send_rounded),
                        onPressed: _sendTextMessage,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}


class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xff0f172a),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final value = _controller.value;
                int active = (value * 3).floor() % 3;
                return Row(
                  children: List.generate(3, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(
                        opacity: index == active ? 1.0 : 0.3,
                        child: const CircleAvatar(
                          radius: 3,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(width: 8),
            const Text(
              'KaironAI đang gõ...',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}


class _FullScreenImagePage extends StatelessWidget {
  final String imagePath;

  const _FullScreenImagePage({
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: InteractiveViewer(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
