import 'package:flutter/material.dart';

class ProfileSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const ProfileSection({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(title!, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
          ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class ProfileDivider extends StatelessWidget {
  const ProfileDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: 56, color: Colors.grey.shade200);
}
