import 'package:flutter/material.dart';
import '../core/models.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';

class PersonName extends StatefulWidget {
  const PersonName({
    super.key,
    required this.controller,
    required this.userId,
    this.style,
  });
  final MessengerController controller;
  final String userId;
  final TextStyle? style;
  @override
  State<PersonName> createState() => _PersonNameState();
}

class _PersonNameState extends State<PersonName> {
  late Future<Person> person;
  late int session;
  @override
  void initState() {
    super.initState();
    session = widget.controller.sessionRevision;
    person = widget.controller.person(widget.userId);
  }

  @override
  void didUpdateWidget(PersonName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.controller != widget.controller ||
        session != widget.controller.sessionRevision) {
      session = widget.controller.sessionRevision;
      person = widget.controller.person(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: FutureBuilder<Person>(
      future: person,
      builder: (context, snapshot) => Text(
        snapshot.data?.name ?? context.l10n.user,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}
