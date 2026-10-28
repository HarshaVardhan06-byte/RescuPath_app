import 'package:flutter/material.dart';

class LuxuryTheme {
  static const navy = Color(0xFF0A1930);
  static const navy2 = Color(0xFF102744);
  static const blue = Color(0xFF2477FF);
  static const cyan = Color(0xFF12BFEA);
  static const red = Color(0xFFFF3B4B);
  static const green = Color(0xFF14B879);
  static const amber = Color(0xFFFFA81E);
  static const ink = Color(0xFF10233F);
  static const muted = Color(0xFF68788F);
  static const bg = Color(0xFFF4F7FB);
  static const line = Color(0xFFE4EAF2);

  static ThemeData build() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light),
    appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: ink, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
    ),
  );
}

class CommandCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CommandCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: LuxuryTheme.line), boxShadow: const [BoxShadow(color: Color(0x080A1930), blurRadius: 22, offset: Offset(0, 8))]),
    child: child,
  );
}

class BrandHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const BrandHeader({super.key, required this.title, required this.subtitle, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [LuxuryTheme.navy, LuxuryTheme.navy2]), boxShadow: const [BoxShadow(color: Color(0x220A1930), blurRadius: 22, offset: Offset(0, 10))]),
    child: Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(17)), child: Icon(icon, color: Colors.white, size: 28)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .68), fontSize: 12))]))]),
  );
}
