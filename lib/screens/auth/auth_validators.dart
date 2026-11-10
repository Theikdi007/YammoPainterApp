// Form validators shared by the login and sign-up screens. Each returns null
// when the value is acceptable, or an error string for the field.

/// Loose RFC-ish email shape — enough to catch typos without rejecting valid
/// addresses. The backend is the real authority on whether an account exists.
final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Used on the sign-up screen — a name is required so `portal_users.full_name`
/// is populated. Trims whitespace and asks for at least 2 characters.
String? validateFullName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter your name';
  if (name.length < 2) return 'Enter your full name';
  return null;
}

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
  return null;
}

/// Used on the login screen — only checks presence, since the backend decides
/// whether the password is correct.
String? validatePassword(String? value) {
  if ((value ?? '').isEmpty) return 'Enter your password';
  return null;
}

/// Used on the sign-up screen — enforces Supabase's default 6-character minimum
/// up front so the user gets immediate feedback.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Choose a password';
  if (password.length < 6) return 'Use at least 6 characters';
  return null;
}

String? Function(String?) validateConfirmPassword(String Function() original) {
  return (value) {
    if ((value ?? '').isEmpty) return 'Re-enter your password';
    if (value != original()) return 'Passwords do not match';
    return null;
  };
}
