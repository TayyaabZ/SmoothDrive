import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smooth_drive/main.dart';

void main() {
  testWidgets('LoginScreen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SmoothDriveApp());

    // Verify the logo text is present
    expect(find.text('Smooth'), findsOneWidget);
    expect(find.text('Drive'), findsOneWidget);

    // Verify input fields are present
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    // Verify the Login button is present
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);

    // Verify the Sign Up navigation text
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('Navigate to RegistrationScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmoothDriveApp());

    // Tap "Sign Up" to navigate to registration
    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    // Verify we're on the registration screen
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Up'), findsOneWidget);
  });
}
