import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'main.dart';


class PersonaSelectionPage extends StatelessWidget {
  const PersonaSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final personaState = context.watch<PersonaState>();

    void select(PersonaMode mode) {
      personaState.setPersona(mode);
    }

    Widget buildCard({
      required PersonaMode mode,
      required String title,
      required String description,
      required IconData icon,
      required Color color,
    }) {
      final bool selected = personaState.persona == mode;
      return InkWell(
        onTap: () => select(mode),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : Colors.grey.shade800,
            ),
            color: selected ? color.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn cá tính cho KaironAI'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bạn muốn KaironAI cư xử thế nào?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              buildCard(
                mode: PersonaMode.serious,
                title: 'Nghiêm túc',
                description:
                    'Tập trung, gọn gàng, chỉ nói những gì cần cho việc học.',
                icon: Icons.shield_outlined,
                color: const Color(0xff4f46e5),
              ),
              const SizedBox(height: 12),
              buildCard(
                mode: PersonaMode.funny,
                title: 'Hài hước',
                description:
                    'Vẫn sắp lịch chuẩn nhưng hay pha trò, nói chuyện vui vẻ.',
                icon: Icons.emoji_emotions_outlined,
                color: const Color(0xff22c55e),
              ),
              const SizedBox(height: 12),
              buildCard(
                mode: PersonaMode.angry,
                title: 'Giận dữ',
                description:
                    'Nếu bạn lười, KaironAI sẽ cà khịa, nhắc nhở cực gắt.',
                icon: Icons.flash_on_outlined,
                color: const Color(0xfff97316),
              ),
              const Spacer(),
              FilledButton(
                onPressed: personaState.persona == null
                    ? null
                    : () {
                        Navigator.of(context)
                            .pushReplacementNamed('/home');
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Vào trang chủ Kairon'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
