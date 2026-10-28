import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});
  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final api = ApiClient();
  String email = '';
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await api.get('/auth/me'));
      name.text = r['full_name']?.toString() ?? '';
      phone.text = r['phone']?.toString() ?? '';
      email = r['email']?.toString() ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _save() async {
    if (name.text.trim().length < 2) {
      _toast('Enter a valid name.', AppTheme.red);
      return;
    }
    setState(() => saving = true);
    try {
      await api.put('/auth/me', {
        'full_name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
      });
      if (!mounted) return;
      _toast('Profile updated successfully.', AppTheme.green);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast(e.toString().replaceFirst('Exception: ', ''), AppTheme.red);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _toast(String text, Color color) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: color, content: Text(text, style: const TextStyle(fontWeight: FontWeight.w800))),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Personal Information', style: TextStyle(fontWeight: FontWeight.w900))),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const PageHeader(
                    eyebrow: 'Profile',
                    title: 'Personal information',
                    subtitle: 'Keep your responder identity and contact number current.',
                  ),
                  const SizedBox(height: 16),
                  SurfaceCard(
                    child: Column(
                      children: [
                        TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                          child: Text(email.isEmpty ? '—' : email, style: const TextStyle(color: AppTheme.muted)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
                        ),
                        const SizedBox(height: 18),
                        PrimaryButton(
                          label: saving ? 'Saving…' : 'Save changes',
                          icon: Icons.check_rounded,
                          background: AppTheme.blue,
                          onPressed: saving ? null : _save,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      );

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }
}
