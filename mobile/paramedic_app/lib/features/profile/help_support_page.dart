import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  Future<void> _email(BuildContext context) async {
    if (AppConfig.supportEmail.isEmpty) { _toast(context, 'Support email is not configured yet. Add SUPPORT_EMAIL when you build for production.', AppTheme.amber); return; }
    final uri = Uri(scheme: 'mailto', path: AppConfig.supportEmail, queryParameters: {'subject': 'RescuPath support request'});
    await launchUrl(uri);
  }

  Future<void> _call(BuildContext context) async {
    if (AppConfig.supportPhone.isEmpty) { _toast(context, 'Support phone is not configured yet. Add SUPPORT_PHONE when you build for production.', AppTheme.amber); return; }
    await launchUrl(Uri(scheme: 'tel', path: AppConfig.supportPhone), mode: LaunchMode.externalApplication);
  }

  void _toast(BuildContext context, String text, Color color) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(text, style: const TextStyle(fontWeight: FontWeight.w800))));

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Help & Support', style: TextStyle(fontWeight: FontWeight.w900))), body: ListView(padding: const EdgeInsets.all(18), children: [
    const PageHeader(eyebrow: 'Support', title: 'Need help?', subtitle: 'Fast answers for the responder app and a direct path to support.'),
    const SizedBox(height: 16),
    Row(children: [Expanded(child: ActionTile(icon: Icons.email_rounded, title: 'Email support', subtitle: 'Compose a ticket', color: AppTheme.blue, onTap: () => _email(context))), const SizedBox(width: 10), Expanded(child: ActionTile(icon: Icons.phone_rounded, title: 'Call support', subtitle: 'Reach the team', color: AppTheme.green, onTap: () => _call(context)))]),
    const SizedBox(height: 12),
    SurfaceCard(gradient: const [Color(0xFFFFF7E9), Colors.white], onTap: () => launchUrl(Uri(scheme: 'tel', path: '112'), mode: LaunchMode.externalApplication), child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: .13), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.phone_in_talk_rounded, color: AppTheme.amber)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Emergency services', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900)), Text('Call 112 for immediate emergency assistance.', style: TextStyle(color: AppTheme.muted, fontSize: 11))])), const Icon(Icons.chevron_right_rounded)])),
    const SizedBox(height: 18),
    const Text('COMMON QUESTIONS', style: TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 12)),
    const SizedBox(height: 10),
    _faq('How does hospital matching work?', 'The backend combines live nearby hospitals with emergency capability, patient condition fit, route ETA and the configured route policy.'),
    _faq('What does Comfort Priority mean?', 'For broken-rib responses, route alternatives are scored using available mapped road-quality data and travel time so rough-road exposure is reduced where possible.'),
    _faq('What does Traffic Priority mean?', 'For cardiac responses, traffic-aware routing is used when the configured Google Routes provider supplies live traffic. Without that key, the app clearly falls back to fastest road-network routing.'),
    _faq('Can I use Google Maps?', 'Yes. The live navigation screen has an Open in Google Maps control that passes the current location when available and the selected hospital as the destination.'),
  ]));

  Widget _faq(String q, String a) => Padding(padding: const EdgeInsets.only(bottom: 8), child: ExpansionTile(tilePadding: const EdgeInsets.symmetric(horizontal: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppTheme.line)), collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppTheme.line)), backgroundColor: Colors.white, collapsedBackgroundColor: Colors.white, title: Text(q, style: const TextStyle(color: AppTheme.ink, fontWeight: FontWeight.w800, fontSize: 13)), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [Text(a, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4))]));
}
