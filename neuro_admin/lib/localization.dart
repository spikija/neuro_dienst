import 'package:flutter/material.dart';
import 'translations.dart';

/// Presentation-only catalog. Named placeholders keep grammar out of widgets;
/// database identifiers and physician names are always passed as arguments.
class AdminStrings {
  final String language;
  const AdminStrings(this.language);
  static AdminStrings of(BuildContext context) =>
      AdminStrings(Localizations.localeOf(context).languageCode);
  String text(String key, [Map<String, Object?> args = const {}]) {
    var value = language == 'de'
        ? german[key] ?? key
        : englishLabels[key] ?? key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return value;
  }
}

class AdminText extends StatelessWidget {
  final String text;
  final Map<String, Object?> args;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  const AdminText(
    this.text, {
    super.key,
    this.args = const {},
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });
  @override
  Widget build(BuildContext context) => Text(
    AdminStrings.of(context).text(text, args),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
  );
}

class AdminTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  const AdminTooltip({super.key, required this.message, required this.child});
  @override
  Widget build(BuildContext context) =>
      Tooltip(message: AdminStrings.of(context).text(message), child: child);
}

class ActionMenuLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  const ActionMenuLabel(this.text, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 10),
      Flexible(child: AdminText(text)),
    ],
  );
}

class AdminLanguageScope extends InheritedWidget {
  final ValueChanged<Locale> onChanged;
  const AdminLanguageScope({
    super.key,
    required this.onChanged,
    required super.child,
  });
  @override
  bool updateShouldNotify(AdminLanguageScope oldWidget) =>
      onChanged != oldWidget.onChanged;
}

class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: AdminStrings.of(context).text('Language'),
    icon: const Icon(Icons.language),
    onSelected: (code) => context
        .dependOnInheritedWidgetOfExactType<AdminLanguageScope>()
        ?.onChanged(Locale(code)),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'de', child: Text('Deutsch')),
      PopupMenuItem(value: 'en', child: Text('English')),
    ],
  );
}
