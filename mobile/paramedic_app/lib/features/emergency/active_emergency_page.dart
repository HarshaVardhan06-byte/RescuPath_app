import 'package:flutter/material.dart';

import '../hospitals/hospital_selection_page.dart';

/// Backwards-compatible route used by the existing app navigation.
/// The emergency lifecycle now explicitly requires hospital selection before
/// entering the dedicated live-navigation page.
class ActiveEmergencyPage extends StatelessWidget {
  final String? emergencyId;
  final String initialSeverity;

  const ActiveEmergencyPage({
    super.key,
    this.emergencyId,
    this.initialSeverity = 'HIGH',
  });

  @override
  Widget build(BuildContext context) {
    if (emergencyId == null || emergencyId!.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No active emergency was supplied.'),
        ),
      );
    }

    return HospitalSelectionPage(
      emergencyId: emergencyId!,
      initialSeverity: initialSeverity,
    );
  }
}
