import 'package:flutter/material.dart';

import '../core/app_api.dart';
import '../core/luxury_theme.dart';

class HospitalLoginPage extends StatefulWidget {
  final VoidCallback onSignedIn;

  const HospitalLoginPage({super.key, required this.onSignedIn});

  @override
  State<HospitalLoginPage> createState() => _HospitalLoginPageState();
}

class _HospitalLoginPageState extends State<HospitalLoginPage> {
  final AppApi api = AppApi();
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController hospital = TextEditingController();
  final TextEditingController lat = TextEditingController(text: '12.9716');
  final TextEditingController lon = TextEditingController(text: '77.5946');
  final TextEditingController department = TextEditingController(
    text: 'Emergency Department',
  );

  bool registering = false;
  bool busy = false;
  bool obscure = true;
  String? error;

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your work email and password.');
      return;
    }

    if (registering &&
        [name, hospital, lat, lon].any((controller) => controller.text.trim().isEmpty)) {
      setState(() => error =
          'Complete operator name, facility name, latitude and longitude.');
      return;
    }

    final latitude = double.tryParse(lat.text.trim());
    final longitude = double.tryParse(lon.text.trim());
    if (registering &&
        (latitude == null || longitude == null ||
            latitude < -90 || latitude > 90 ||
            longitude < -180 || longitude > 180)) {
      setState(() => error = 'Enter valid facility latitude and longitude.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final dynamic response = registering
          ? await api.post('/coordination/hospital/register', {
              'full_name': name.text.trim(),
              'email': email.text.trim(),
              'password': password.text,
              'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
              'hospital_name': hospital.text.trim(),
              'latitude': latitude,
              'longitude': longitude,
              'department': department.text.trim().isEmpty
                  ? 'Emergency Department'
                  : department.text.trim(),
            })
          : await api.post('/auth/login', {
              'email': email.text.trim(),
              'password': password.text,
            });

      final token = response is Map ? response['access_token'] : null;
      if (token == null || token.toString().isEmpty) {
        throw Exception('The server did not return an access token.');
      }
      await api.saveToken(token.toString());
      await api.get('/coordination/hospital/board');
      if (mounted) widget.onSignedIn();
    } catch (e) {
      await api.logout();
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandHeader(
                    title: 'RescuPath Hospital',
                    subtitle: 'Emergency readiness • Live ambulance coordination',
                    icon: Icons.local_hospital_rounded,
                  ),
                  const SizedBox(height: 22),
                  CommandCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          registering ? 'Facility enrolment' : 'Hospital sign in',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: LuxuryTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          registering
                              ? 'Create a facility operator profile for local development.'
                              : 'Review approaching ambulances and respond to readiness requests.',
                          style: const TextStyle(color: LuxuryTheme.muted),
                        ),
                        const SizedBox(height: 18),
                        if (registering) ...[
                          TextField(
                            controller: name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Operator full name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: hospital,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Hospital / facility name',
                              prefixIcon: Icon(Icons.local_hospital_outlined),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: department,
                            decoration: const InputDecoration(labelText: 'Department'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Contact phone (optional)',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: lat,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Facility latitude',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: lon,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Facility longitude',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Work email',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => obscure = !obscure),
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: LuxuryTheme.red.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              error!,
                              style: const TextStyle(
                                color: LuxuryTheme.red,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: busy ? null : submit,
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(busy
                              ? 'Please wait…'
                              : registering
                                  ? 'Create hospital account'
                                  : 'Sign in'),
                          style: FilledButton.styleFrom(
                            backgroundColor: LuxuryTheme.blue,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                    registering = !registering;
                                    error = null;
                                  }),
                          child: Text(registering
                              ? 'Already registered? Sign in'
                              : 'First time? Register facility'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'For local development only. In production, hospital accounts should be provisioned and verified by an administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: LuxuryTheme.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    phone.dispose();
    hospital.dispose();
    lat.dispose();
    lon.dispose();
    department.dispose();
    super.dispose();
  }
}
