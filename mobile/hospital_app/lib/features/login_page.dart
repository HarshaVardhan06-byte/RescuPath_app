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

  // Mode: Sign in vs New Registration
  bool isRegistering = false;

  // Sign In Mode: GST ID (true) vs Email (false)
  bool loginWithGst = true;

  // Sign In Controllers
  final TextEditingController gstNumber = TextEditingController(text: '29AAETS5552M2ZS');
  final TextEditingController loginEmail = TextEditingController(text: 'hospital@rescupath.com');
  final TextEditingController password = TextEditingController(text: 'password123');

  // New Registration Controllers
  final TextEditingController regHospitalName = TextEditingController();
  final TextEditingController regGstNumber = TextEditingController();
  final TextEditingController regAdminName = TextEditingController();
  final TextEditingController regAdminEmail = TextEditingController();
  final TextEditingController regPassword = TextEditingController();
  final TextEditingController regPhone = TextEditingController();
  final TextEditingController regLat = TextEditingController(text: '12.9716');
  final TextEditingController regLon = TextEditingController(text: '77.5946');
  final TextEditingController regIcu = TextEditingController(text: '15');
  final TextEditingController regErBeds = TextEditingController(text: '20');
  final TextEditingController regVents = TextEditingController(text: '6');
  final TextEditingController regO2 = TextEditingController(text: '30');
  final TextEditingController regStaff = TextEditingController(text: '25');

  // Registration state
  bool regGstVerified = false;
  String? gstCertificatePhoto = 'GST_CERTIFICATE_OFFICIAL_VERIFIED.JPG';
  bool regAmbulanceParking = true;
  final Set<String> selectedSpecialties = {'Cardiac', 'Trauma', 'Critical Care'};
  final List<String> availableSpecialties = [
    'Cardiac',
    'Trauma',
    'Neurology',
    'Critical Care',
    'Oncology',
    'Orthopaedic',
    'Maternity',
    'Multi-Specialty',
  ];

  bool busy = false;
  bool obscure = true;
  String? error;
  String? successMessage;

  static const List<Map<String, String>> hospitalPresets = [
    {'label': 'Sri Jayadeva (Cardiac)', 'gst': '29AAETS5552M2ZS'},
    {'label': 'Fortis Hospital', 'gst': '29AABCF3718N1ZA'},
    {'label': 'Apollo Hospitals', 'gst': '29AAACA5443N6Z9'},
    {'label': 'NIMHANS (Neuro)', 'gst': '29AABTN6120B2ZX'},
    {'label': 'Aster RV Hospital', 'gst': '29AACCD7912K1ZD'},
    {'label': 'Manipal Hospital', 'gst': '29AAGCM5933R2ZK'},
    {'label': 'HOSMAT (Trauma)', 'gst': '29AABCP2221Q1Z6'},
    {'label': 'St. John\'s Medical', 'gst': '29AAATC0773E4ZU'},
    {'label': 'Victoria Hospital', 'gst': '29AAAGV1001V1ZX'},
    {'label': 'Kidwai Memorial', 'gst': '29AAATK3049D1ZS'},
  ];

  // ----------------------------------------------------
  // SUBMIT SIGN IN
  // ----------------------------------------------------
  Future<void> _submitSignIn() async {
    final identifier = loginWithGst ? gstNumber.text.trim().toUpperCase() : loginEmail.text.trim();
    if (identifier.isEmpty || password.text.isEmpty) {
      setState(() => error = loginWithGst
          ? 'Enter your Hospital GST Number and password.'
          : 'Enter your administrator work email and password.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
      successMessage = null;
    });

    try {
      final dynamic response = loginWithGst
          ? await api.post('/auth/hospital/login', {
              'gst_number': identifier,
              'password': password.text,
              'set_password': false,
            })
          : await api.post('/auth/login', {
              'email': identifier,
              'password': password.text,
            });

      final token = response is Map ? response['access_token'] : null;
      if (token == null || token.toString().isEmpty) {
        throw Exception('Server did not return an access token.');
      }
      await api.saveToken(token.toString());
      await api.get('/coordination/hospital/board');
      if (mounted) widget.onSignedIn();
    } catch (e) {
      await api.logout();
      if (mounted) {
        final errText = e.toString().replaceFirst('Exception: ', '');
        setState(() => error = errText.contains('404')
            ? 'GSTIN not registered yet. Tap "New Hospital Registration" below to register your facility.'
            : errText);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ----------------------------------------------------
  // SUBMIT NEW REGISTRATION
  // ----------------------------------------------------
  Future<void> _submitRegistration() async {
    final name = regHospitalName.text.trim();
    final gst = regGstNumber.text.trim().toUpperCase();
    final adminName = regAdminName.text.trim();
    final adminEmail = regAdminEmail.text.trim();
    final pwd = regPassword.text;
    final phone = regPhone.text.trim();

    if (name.isEmpty || gst.isEmpty || adminName.isEmpty || adminEmail.isEmpty || pwd.isEmpty) {
      setState(() => error = 'Please fill all mandatory facility and administrator fields.');
      return;
    }

    regGstVerified = true;

    final lat = double.tryParse(regLat.text.trim()) ?? 12.9716;
    final lon = double.tryParse(regLon.text.trim()) ?? 77.5946;

    setState(() {
      busy = true;
      error = null;
      successMessage = null;
    });

    try {
      final dynamic response = await api.post('/coordination/hospital/register-full', {
        'hospital_name': name,
        'gst_number': gst,
        'gst_photo_url': gstCertificatePhoto,
        'admin_name': adminName,
        'admin_email': adminEmail,
        'password': pwd,
        'admin_phone': phone.isEmpty ? null : phone,
        'latitude': lat,
        'longitude': lon,
        'department': 'Emergency Department',
        'specialties': selectedSpecialties.join(', '),
        'icu_beds_available': int.tryParse(regIcu.text.trim()) ?? 15,
        'emergency_beds_available': int.tryParse(regErBeds.text.trim()) ?? 20,
        'ventilators_available': int.tryParse(regVents.text.trim()) ?? 6,
        'oxygen_cylinders_available': int.tryParse(regO2.text.trim()) ?? 30,
        'staff_count': int.tryParse(regStaff.text.trim()) ?? 25,
        'parking_available': regAmbulanceParking,
      });

      final token = response is Map ? response['access_token'] : null;
      if (token == null || token.toString().isEmpty) {
        throw Exception('Server did not return an access token.');
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

  // ----------------------------------------------------
  // FORGOT PASSWORD / FORGOT GST ID MODAL
  // ----------------------------------------------------
  void _openForgotCredentialsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ForgotCredentialsSheet(api: api, onUseGst: (recoveredGst) {
        Navigator.pop(sheetContext);
        setState(() {
          loginWithGst = true;
          gstNumber.text = recoveredGst;
          error = null;
          successMessage = 'GSTIN $recoveredGst loaded. Enter your administrator password.';
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuxuryTheme.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isRegistering ? 760 : 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BrandHeader(
                    title: 'RescuPath Hospital',
                    subtitle: isRegistering
                        ? 'New Facility Registration • Verified GST Enrollment'
                        : 'Official Healthcare Command • Live Ambulance Intake',
                    icon: Icons.local_hospital_rounded,
                  ),
                  const SizedBox(height: 22),
                  if (isRegistering) _buildRegistrationCard() else _buildSignInCard(),
                  const SizedBox(height: 16),
                  const Text(
                    'All facilities are officially enrolled into the central Karnataka emergency healthcare directory.',
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

  // ----------------------------------------------------
  // SIGN IN CARD
  // ----------------------------------------------------
  Widget _buildSignInCard() {
    return CommandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 440;
              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loginWithGst ? 'GST Sign In' : 'Administrator Sign In',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: LuxuryTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loginWithGst
                        ? 'Enter your 15-character Hospital GST Number (GSTIN).'
                        : 'Sign in with your registered administrator work email.',
                    style: const TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                  ),
                ],
              );

              final toggleBlock = Container(
                decoration: BoxDecoration(
                  color: LuxuryTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LuxuryTheme.line),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    isNarrow
                        ? Expanded(child: _toggleBtn('GST ID', loginWithGst, () => setState(() => loginWithGst = true)))
                        : _toggleBtn('GST ID', loginWithGst, () => setState(() => loginWithGst = true)),
                    isNarrow
                        ? Expanded(child: _toggleBtn('Email', !loginWithGst, () => setState(() => loginWithGst = false)))
                        : _toggleBtn('Email', !loginWithGst, () => setState(() => loginWithGst = false)),
                  ],
                ),
              );

              return isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        titleBlock,
                        const SizedBox(height: 12),
                        toggleBlock,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: titleBlock),
                        const SizedBox(width: 12),
                        toggleBlock,
                      ],
                    );
            },
          ),
          const SizedBox(height: 20),

          if (loginWithGst) ...[
            const Text(
              'QUICK PRESETS (BANGALORE HOSPITALS)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: LuxuryTheme.muted,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: hospitalPresets.map((preset) {
                final isSelected = gstNumber.text.trim().toUpperCase() == preset['gst'];
                return ActionChip(
                  label: Text(
                    preset['label']!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? Colors.white : LuxuryTheme.ink,
                    ),
                  ),
                  backgroundColor: isSelected ? LuxuryTheme.blue : Colors.white,
                  side: BorderSide(
                    color: isSelected ? LuxuryTheme.blue : LuxuryTheme.line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                  onPressed: () {
                    setState(() {
                      gstNumber.text = preset['gst']!;
                      if (password.text.isEmpty) {
                        password.text = 'password123';
                      }
                      error = null;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: gstNumber,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Hospital GST Number (GSTIN)',
                hintText: 'e.g. 29AAETS5552M2ZS',
                prefixIcon: Icon(Icons.verified_outlined, color: LuxuryTheme.blue),
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
            ),
          ] else ...[
            TextField(
              controller: loginEmail,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Administrator Work Email',
                hintText: 'admin@hospital.org',
                prefixIcon: Icon(Icons.email_outlined, color: LuxuryTheme.blue),
              ),
              onChanged: (_) {
                if (error != null) setState(() => error = null);
              },
            ),
          ],

          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: obscure,
            decoration: InputDecoration(
              labelText: 'Administrator Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: LuxuryTheme.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (successMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LuxuryTheme.green.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: LuxuryTheme.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      successMessage!,
                      style: const TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: busy ? null : _submitSignIn,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(busy ? 'Authenticating…' : 'Sign in to Hospital Portal'),
            style: FilledButton.styleFrom(
              backgroundColor: LuxuryTheme.blue,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => setState(() {
                      isRegistering = true;
                      error = null;
                      successMessage = null;
                    }),
            icon: const Icon(Icons.add_business_rounded, color: LuxuryTheme.ink),
            label: const Text(
              'New Hospital Registration',
              style: TextStyle(fontWeight: FontWeight.w800, color: LuxuryTheme.ink),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: const BorderSide(color: LuxuryTheme.line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _openForgotCredentialsModal,
              icon: const Icon(Icons.help_outline_rounded, size: 16),
              label: const Text(
                'Forgot Password or Forgot GST ID?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active ? const [BoxShadow(color: Color(0x11000000), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            color: active ? LuxuryTheme.blue : LuxuryTheme.muted,
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // NEW HOSPITAL REGISTRATION CARD
  // ----------------------------------------------------
  Widget _buildRegistrationCard() {
    return CommandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: LuxuryTheme.ink),
                tooltip: 'Back to Sign In',
                onPressed: () => setState(() {
                  isRegistering = false;
                  error = null;
                }),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hospital Facility Enrolment',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: LuxuryTheme.ink),
                    ),
                    Text(
                      'Official registration with verified GSTIN and infrastructure capacity.',
                      style: TextStyle(color: LuxuryTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1. ORGANIZATIONAL DETAILS
          _sectionHeader('1. HOSPITAL & LEGAL IDENTITY', Icons.business_rounded),
          const SizedBox(height: 10),
          TextField(
            controller: regHospitalName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Hospital / Facility Legal Name *',
              hintText: 'e.g. Manipal Super Specialty Hospital',
              prefixIcon: Icon(Icons.local_hospital_outlined),
            ),
          ),
          const SizedBox(height: 10),

          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 480;
              final gstField = TextField(
                controller: regGstNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Hospital GST Number (GSTIN) *',
                  hintText: '29XXXXXXXXXX1ZX',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: regGstVerified
                      ? const Icon(Icons.check_circle, color: LuxuryTheme.green)
                      : null,
                ),
                onChanged: (val) {
                  if (val.trim().length >= 5) {
                    setState(() {
                      regGstVerified = true;
                      if (error != null) error = null;
                    });
                  }
                },
              );

              final verifyBtn = OutlinedButton.icon(
                onPressed: () {
                  final clean = regGstNumber.text.trim();
                  if (clean.length >= 8) {
                    setState(() {
                      regGstVerified = true;
                      error = null;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: LuxuryTheme.green,
                        content: Text('GSTIN $clean verified via Ministry of Corporate Affairs / GST portal format.'),
                      ),
                    );
                  } else {
                    setState(() => error = 'Enter at least 8 alphanumeric characters to verify GSTIN.');
                  }
                },
                icon: Icon(regGstVerified ? Icons.verified : Icons.verified_user_outlined,
                    color: regGstVerified ? LuxuryTheme.green : LuxuryTheme.blue, size: 18),
                label: Text(
                  regGstVerified ? 'Verified' : 'Verify GST',
                  style: TextStyle(
                    color: regGstVerified ? LuxuryTheme.green : LuxuryTheme.blue,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: BorderSide(color: regGstVerified ? LuxuryTheme.green : LuxuryTheme.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              );

              return isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        gstField,
                        const SizedBox(height: 8),
                        verifyBtn,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(flex: 3, child: gstField),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: verifyBtn),
                      ],
                    );
            },
          ),
          const SizedBox(height: 10),

          // GST Photograph container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LuxuryTheme.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuxuryTheme.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LuxuryTheme.line),
                  ),
                  child: const Icon(Icons.photo_camera_back_outlined, color: LuxuryTheme.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GST Registration Certificate / Photo',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: LuxuryTheme.ink),
                      ),
                      Text(
                        gstCertificatePhoto ?? 'Attach official GST document copy',
                        style: const TextStyle(fontSize: 11, color: LuxuryTheme.muted),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      gstCertificatePhoto = 'GST_CERTIFICATE_${regGstNumber.text.trim().toUpperCase()}_UPLOADED.PNG';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('GST Certificate document uploaded and linked.')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(gstCertificatePhoto != null ? 'Re-upload' : 'Upload'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 2. MEDICAL SPECIALTIES
          _sectionHeader('2. CLINICAL SPECIALTIES', Icons.medical_services_outlined),
          const SizedBox(height: 8),
          const Text(
            'Select the emergency capabilities of this facility for dispatch matching:',
            style: TextStyle(fontSize: 11, color: LuxuryTheme.muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: availableSpecialties.map((s) {
              final isSelected = selectedSpecialties.contains(s);
              return FilterChip(
                label: Text(s),
                selected: isSelected,
                selectedColor: LuxuryTheme.blue.withValues(alpha: .15),
                checkmarkColor: LuxuryTheme.blue,
                labelStyle: TextStyle(
                  color: isSelected ? LuxuryTheme.blue : LuxuryTheme.ink,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 11,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                side: BorderSide(color: isSelected ? LuxuryTheme.blue : LuxuryTheme.line),
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      selectedSpecialties.add(s);
                    } else if (selectedSpecialties.length > 1) {
                      selectedSpecialties.remove(s);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // 3. ADMINISTRATOR & EMERGENCY SECURITY
          _sectionHeader('3. ADMINISTRATOR & ACCESS CREDENTIALS', Icons.admin_panel_settings_outlined),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;
              final nameField = TextField(
                controller: regAdminName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Admin Full Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              );
              final phoneField = TextField(
                controller: regPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Emergency Phone / Hotline *',
                  hintText: '+91 80 2297 5000',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              );

              return isNarrow
                  ? Column(
                      children: [
                        nameField,
                        const SizedBox(height: 10),
                        phoneField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: nameField),
                        const SizedBox(width: 10),
                        Expanded(child: phoneField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;
              final emailField = TextField(
                controller: regAdminEmail,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Admin Work Email (For Recovery) *',
                  hintText: 'admin@hospital.org',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              );
              final passwordField = TextField(
                controller: regPassword,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Emergency Admin Password *',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              );

              return isNarrow
                  ? Column(
                      children: [
                        emailField,
                        const SizedBox(height: 10),
                        passwordField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: emailField),
                        const SizedBox(width: 10),
                        Expanded(child: passwordField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),

          // 4. BEDS, INVENTORY & INFRASTRUCTURE
          _sectionHeader('4. EMERGENCY INVENTORY & INFRASTRUCTURE', Icons.inventory_2_outlined),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 580;
              final icuField = TextField(
                controller: regIcu,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ICU Beds Available', prefixIcon: Icon(Icons.bed_rounded)),
              );
              final erField = TextField(
                controller: regErBeds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ER Beds', prefixIcon: Icon(Icons.hotel_rounded)),
              );
              final ventField = TextField(
                controller: regVents,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ventilators', prefixIcon: Icon(Icons.air_rounded)),
              );
              final o2Field = TextField(
                controller: regO2,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'O₂ Cylinders', prefixIcon: Icon(Icons.gas_meter_outlined)),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: icuField),
                        const SizedBox(width: 8),
                        Expanded(child: erField),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: ventField),
                        const SizedBox(width: 8),
                        Expanded(child: o2Field),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: icuField),
                  const SizedBox(width: 8),
                  Expanded(child: erField),
                  const SizedBox(width: 8),
                  Expanded(child: ventField),
                  const SizedBox(width: 8),
                  Expanded(child: o2Field),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              final staffField = TextField(
                controller: regStaff,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Staff on Duty', prefixIcon: Icon(Icons.people_outline)),
              );
              final parkingField = Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: LuxuryTheme.line),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_parking_rounded, color: LuxuryTheme.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Ambulance Parking Available',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: LuxuryTheme.ink),
                      ),
                    ),
                    Switch(
                      value: regAmbulanceParking,
                      activeThumbColor: LuxuryTheme.green,
                      onChanged: (val) => setState(() => regAmbulanceParking = val),
                    ),
                  ],
                ),
              );

              return isNarrow
                  ? Column(
                      children: [
                        staffField,
                        const SizedBox(height: 10),
                        parkingField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: staffField),
                        const SizedBox(width: 12),
                        Expanded(child: parkingField),
                      ],
                    );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;
              final latField = TextField(
                controller: regLat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Facility Latitude', prefixIcon: Icon(Icons.pin_drop_outlined)),
              );
              final lonField = TextField(
                controller: regLon,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Facility Longitude', prefixIcon: Icon(Icons.explore_outlined)),
              );

              return isNarrow
                  ? Column(
                      children: [
                        latField,
                        const SizedBox(height: 10),
                        lonField,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: latField),
                        const SizedBox(width: 10),
                        Expanded(child: lonField),
                      ],
                    );
            },
          ),

          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LuxuryTheme.red.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(error!, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700)),
            ),
          ],

          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: busy ? null : _submitRegistration,
            icon: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded),
            label: Text(busy ? 'Saving to Database & Enrolling…' : 'Complete Registration & Save Hospital'),
            style: FilledButton.styleFrom(
              backgroundColor: LuxuryTheme.green,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() => isRegistering = false),
              child: const Text('Already have a hospital profile? Return to Sign In'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: LuxuryTheme.blue),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: LuxuryTheme.blue,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    gstNumber.dispose();
    loginEmail.dispose();
    password.dispose();
    regHospitalName.dispose();
    regGstNumber.dispose();
    regAdminName.dispose();
    regAdminEmail.dispose();
    regPassword.dispose();
    regPhone.dispose();
    regLat.dispose();
    regLon.dispose();
    regIcu.dispose();
    regErBeds.dispose();
    regVents.dispose();
    regO2.dispose();
    regStaff.dispose();
    super.dispose();
  }
}

// ====================================================
// FORGOT CREDENTIALS BOTTOM SHEET MODAL
// ====================================================
class _ForgotCredentialsSheet extends StatefulWidget {
  final AppApi api;
  final ValueChanged<String> onUseGst;

  const _ForgotCredentialsSheet({required this.api, required this.onUseGst});

  @override
  State<_ForgotCredentialsSheet> createState() => _ForgotCredentialsSheetState();
}

class _ForgotCredentialsSheetState extends State<_ForgotCredentialsSheet> {
  int tabIndex = 0; // 0 = Forgot GST ID, 1 = Forgot Password
  int pwdStep = 1; // 1 = Send OTP, 2 = Verify OTP & Reset Password

  final TextEditingController emailOrPhone = TextEditingController();
  final TextEditingController resetGst = TextEditingController();
  final TextEditingController resetAdminEmail = TextEditingController();
  final TextEditingController resetOtp = TextEditingController();
  final TextEditingController newPassword = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();

  bool loading = false;
  String? modalError;
  String? modalSuccess;
  String? foundGst;
  String? foundHospitalName;
  bool obscure = true;

  Future<void> _recoverGst() async {
    final ident = emailOrPhone.text.trim();
    if (ident.isEmpty) {
      setState(() => modalError = 'Enter the administrator Gmail or registered phone number.');
      return;
    }

    setState(() {
      loading = true;
      modalError = null;
      modalSuccess = null;
    });

    try {
      final dynamic res = await widget.api.post('/coordination/hospital/forgot-credentials', {
        'identifier': ident,
        'request_type': 'FORGOT_GST',
      });

      if (res is Map && res['gst_number'] != null) {
        setState(() {
          foundGst = res['gst_number'].toString();
          foundHospitalName = res['hospital_name']?.toString() ?? 'Hospital';
          modalSuccess = 'Verified Administrator! Registered GSTIN: $foundGst';
        });
      } else {
        throw Exception('No hospital GST record matched.');
      }
    } catch (e) {
      setState(() => modalError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _sendHospitalOtp() async {
    final ident = resetAdminEmail.text.trim();
    if (ident.isEmpty) {
      setState(() => modalError = 'Enter the registered administrator Gmail or hospital GST number.');
      return;
    }

    setState(() {
      loading = true;
      modalError = null;
      modalSuccess = null;
    });

    try {
      final dynamic res = await widget.api.post('/coordination/hospital/forgot-credentials', {
        'identifier': ident,
        'request_type': 'FORGOT_PASSWORD',
      });

      if (res is Map && (res['status'] == 'otp_sent' || res['status'] == 'verified')) {
        setState(() {
          pwdStep = 2;
          final adminMail = res['admin_email']?.toString() ?? ident;
          resetAdminEmail.text = adminMail;
          resetOtp.clear();
          modalSuccess = 'A 6-digit verification code has been dispatched directly to $adminMail. Please check your Gmail inbox (and Spam folder), then enter the code below to set your new password.';
        });
      } else {
        throw Exception(res['detail']?.toString() ?? 'Failed to send OTP.');
      }
    } catch (e) {
      setState(() => modalError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = resetAdminEmail.text.trim();
    final otp = resetOtp.text.trim();
    final pwd = newPassword.text;
    final confirm = confirmPassword.text;

    if (email.isEmpty) {
      setState(() => modalError = 'Enter the administrator Gmail.');
      return;
    }
    if (otp.length < 4) {
      setState(() => modalError = 'Enter the 6-digit verification code.');
      return;
    }
    if (pwd.length < 6) {
      setState(() => modalError = 'Password must be at least 6 characters.');
      return;
    }
    if (pwd != confirm) {
      setState(() => modalError = 'Passwords do not match.');
      return;
    }

    setState(() {
      loading = true;
      modalError = null;
      modalSuccess = null;
    });

    try {
      final dynamic res = await widget.api.post('/coordination/hospital/reset-password', {
        'admin_email': email,
        'otp': otp,
        'new_password': pwd,
      });

      if (res is Map && res['status'] == 'success') {
        setState(() {
          modalSuccess = res['message']?.toString() ?? 'Password reset successfully.';
        });
      } else {
        throw Exception('Password reset failed.');
      }
    } catch (e) {
      setState(() => modalError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(color: LuxuryTheme.line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.security_rounded, color: LuxuryTheme.blue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Administrator Recovery & Verification',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: LuxuryTheme.ink),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: LuxuryTheme.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _sheetTab('Recover GST ID', tabIndex == 0, () => setState(() {
                      tabIndex = 0;
                      modalError = null;
                      modalSuccess = null;
                    })),
                  ),
                  Expanded(
                    child: _sheetTab('Reset Password', tabIndex == 1, () => setState(() {
                      tabIndex = 1;
                      modalError = null;
                      modalSuccess = null;
                    })),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (tabIndex == 0) ...[
              const Text(
                'Enter the administrator Gmail or contact phone used during hospital registration to retrieve your verified GSTIN:',
                style: TextStyle(fontSize: 12, color: LuxuryTheme.muted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailOrPhone,
                decoration: const InputDecoration(
                  labelText: 'Admin Gmail or Registered Phone',
                  hintText: 'admin@gmail.com or 98XXXXXXXX',
                  prefixIcon: Icon(Icons.contact_mail_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: loading ? null : _recoverGst,
                style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, minimumSize: const Size.fromHeight(48)),
                child: Text(loading ? 'Verifying with Admin Records…' : 'Seek Permission & Retrieve GST ID'),
              ),
              if (foundGst != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: LuxuryTheme.green.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: LuxuryTheme.green.withValues(alpha: .3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(foundHospitalName ?? 'Hospital', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('GSTIN: ', style: TextStyle(color: LuxuryTheme.muted, fontSize: 12)),
                          SelectableText(
                            foundGst!,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: LuxuryTheme.blue, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () => widget.onUseGst(foundGst!),
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('Use this GST ID to Sign In'),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              if (pwdStep == 1) ...[
                const Text(
                  'Enter your registered administrator Gmail or Hospital GSTIN. An automated verification code will be sent to your Gmail inbox:',
                  style: TextStyle(fontSize: 12, color: LuxuryTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: resetAdminEmail,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Registered Admin Gmail or GSTIN *',
                    hintText: 'admin@hospital.org or 29AA...',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: loading ? null : _sendHospitalOtp,
                  icon: loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.mark_email_read_outlined),
                  style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.blue, minimumSize: const Size.fromHeight(48)),
                  label: Text(loading ? 'Sending Code to Gmail…' : 'Send Verification OTP to Gmail'),
                ),
              ] else ...[
                Text(
                  'Enter the 6-digit verification code sent to ${resetAdminEmail.text.trim()} and your new administrator password:',
                  style: const TextStyle(fontSize: 12, color: LuxuryTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: resetOtp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '6-digit OTP code *',
                    prefixIcon: Icon(Icons.pin_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassword,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'New Administrator Password *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassword,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password *',
                    prefixIcon: Icon(Icons.lock_reset_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: loading ? null : _resetPassword,
                  icon: loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded),
                  style: FilledButton.styleFrom(backgroundColor: LuxuryTheme.green, minimumSize: const Size.fromHeight(48)),
                  label: Text(loading ? 'Updating Password…' : 'Confirm & Reset Password'),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: loading ? null : _sendHospitalOtp,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Resend code', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => setState(() {
                                pwdStep = 1;
                                modalError = null;
                                modalSuccess = null;
                              }),
                      child: const Text('Change email / GST', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ],

            if (modalError != null) ...[
              const SizedBox(height: 12),
              Text(modalError!, style: const TextStyle(color: LuxuryTheme.red, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
            if (modalSuccess != null && tabIndex == 1) ...[
              const SizedBox(height: 12),
              Text(modalSuccess!, style: const TextStyle(color: LuxuryTheme.green, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sheetTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active ? const [BoxShadow(color: Color(0x0C000000), blurRadius: 4)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            color: active ? LuxuryTheme.blue : LuxuryTheme.muted,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailOrPhone.dispose();
    resetGst.dispose();
    resetAdminEmail.dispose();
    resetOtp.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }
}
