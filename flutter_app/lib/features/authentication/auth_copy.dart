import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';

const _copy = <String, List<String>>{
  'authHero': [
    'Go somewhere that stays with you.',
    'ធ្វើដំណើរទៅកន្លែងដែលដក់ជាប់ក្នុងចិត្ត។',
  ],
  'authCompanion': [
    'YOUR CAMBODIA COMPANION',
    'ដៃគូធ្វើដំណើររបស់អ្នកនៅកម្ពុជា',
  ],
  'authHeading': ['A world awaits.', 'ពិភពលោកកំពុងរង់ចាំ។'],
  'authIntro': [
    'Make room for your next story.',
    'ត្រៀមខ្លួនសម្រាប់រឿងរ៉ាវថ្មីរបស់អ្នក។',
  ],
  'authName': ['Your name', 'ឈ្មោះរបស់អ្នក'],
  'authEmail': ['Email address', 'អាសយដ្ឋានអ៊ីមែល'],
  'authPassword': ['Password', 'ពាក្យសម្ងាត់'],
  'authNewPassword': ['New password', 'ពាក្យសម្ងាត់ថ្មី'],
  'authConfirmPassword': ['Confirm new password', 'បញ្ជាក់ពាក្យសម្ងាត់ថ្មី'],
  'authMismatch': ['Passwords must match.', 'ពាក្យសម្ងាត់ត្រូវតែដូចគ្នា។'],
  'authSignIn': ['Sign in', 'ចូលគណនី'],
  'authRegister': ['Create account', 'បង្កើតគណនី'],
  'authForgot': ['Forgot password?', 'ភ្លេចពាក្យសម្ងាត់?'],
  'authRecover': ['Reset your password', 'កំណត់ពាក្យសម្ងាត់ឡើងវិញ'],
  'authSendReset': ['Send reset email', 'ផ្ញើអ៊ីមែលកំណត់ឡើងវិញ'],
  'authRecoverySent': [
    'If an account exists for this email, reset instructions have been queued. Check your inbox and spam folder.',
    'ប្រសិនបើមានគណនីសម្រាប់អ៊ីមែលនេះ សេចក្ដីណែនាំកំណត់ឡើងវិញត្រូវបានដាក់ក្នុងជួរផ្ញើ។ សូមពិនិត្យប្រអប់សារ និងសារឥតបានការ។',
  ],
  'authVerifyHeading': ['Check your inbox.', 'សូមពិនិត្យប្រអប់សាររបស់អ្នក។'],
  'authVerifyInfo': [
    'Enter the code from your latest email. Codes expire after 15 minutes. Verification does not sign you in automatically.',
    'បញ្ចូលលេខកូដពីអ៊ីមែលចុងក្រោយ។ លេខកូដផុតកំណត់ក្រោយ ១៥ នាទី។ ការផ្ទៀងផ្ទាត់មិនធ្វើឱ្យអ្នកចូលគណនីដោយស្វ័យប្រវត្តិទេ។',
  ],
  'authCode': ['Email verification code', 'លេខកូដផ្ទៀងផ្ទាត់អ៊ីមែល'],
  'authVerify': ['Verify email', 'ផ្ទៀងផ្ទាត់អ៊ីមែល'],
  'authResend': ['Resend email', 'ផ្ញើអ៊ីមែលម្តងទៀត'],
  'authVerified': [
    'Email verified. You can now sign in.',
    'អ៊ីមែលបានផ្ទៀងផ្ទាត់។ ឥឡូវអ្នកអាចចូលគណនីបាន។',
  ],
  'authReset': ['Save new password', 'រក្សាទុកពាក្យសម្ងាត់ថ្មី'],
  'authResetComplete': [
    'Password updated. Sign in with your new password.',
    'ពាក្យសម្ងាត់បានប្ដូរ។ សូមចូលដោយពាក្យសម្ងាត់ថ្មី។',
  ],
  'authBack': ['Back to sign in', 'ត្រឡប់ទៅចូលគណនី'],
  'authHaveCode': [
    'I already have an email code',
    'ខ្ញុំមានលេខកូដអ៊ីមែលរួចហើយ',
  ],
  'authShowPassword': ['Show password', 'បង្ហាញពាក្យសម្ងាត់'],
  'authHidePassword': ['Hide password', 'លាក់ពាក្យសម្ងាត់'],
  'authPasswordRule': [
    'Use 12–72 characters, at most 72 UTF-8 bytes. Khmer characters may use several bytes each.',
    'ប្រើ ១២–៧២ តួអក្សរ និងមិនលើស ៧២ បៃ UTF-8។ តួអក្សរខ្មែរមួយអាចប្រើច្រើនបៃ។',
  ],
  'authEmailInvalid': [
    'Enter a valid email address.',
    'បញ្ចូលអាសយដ្ឋានអ៊ីមែលត្រឹមត្រូវ។',
  ],
  'authNameInvalid': [
    'Enter your name (up to 120 characters).',
    'បញ្ចូលឈ្មោះរបស់អ្នក (មិនលើស ១២០ តួអក្សរ)។',
  ],
  'authCodeInvalid': [
    'Enter the six-digit code from your email.',
    'បញ្ចូលលេខកូដ ៦ ខ្ទង់ពីអ៊ីមែលរបស់អ្នក។',
  ],
  'authValidation': [
    'Please check the form fields and consent.',
    'សូមពិនិត្យព័ត៌មាន និងការយល់ព្រមក្នុងទម្រង់។',
  ],
  'authConsent': [
    'I have read and agree to the Terms and Privacy Policy.',
    'ខ្ញុំបានអាន និងយល់ព្រមតាមលក្ខខណ្ឌ និងគោលការណ៍ឯកជនភាព។',
  ],
  'authTerms': ['Terms', 'លក្ខខណ្ឌ'],
  'authPrivacy': ['Privacy Policy', 'គោលការណ៍ឯកជនភាព'],
  'authLegalUnavailable': [
    'Account creation is unavailable until Terms and Privacy links are configured.',
    'មិនអាចបង្កើតគណនីបានទេ រហូតដល់បានកំណត់តំណលក្ខខណ្ឌ និងឯកជនភាព។',
  ],
  'authGuest': ['Explore as a guest', 'ស្វែងយល់ជាភ្ញៀវ'],
  'authGuestInfo': [
    'Guest exploration • no account signed in. Browse this bundled Cambodia introduction. Saving trips and live services require sign-in.',
    'ស្វែងយល់ជាភ្ញៀវ • មិនទាន់ចូលគណនី។ អានការណែនាំអំពីកម្ពុជាដែលមានក្នុងកម្មវិធី។ ការរក្សាទុកដំណើរ និងសេវាផ្ទាល់ត្រូវការចូលគណនី។',
  ],
  'authGuestPlace': ['Angkor, Cambodia', 'អង្គរ កម្ពុជា'],
  'authGuestDescription': [
    'Start with Cambodia’s temple landscapes. This is an editorial introduction, not live opening hours, prices, weather, or availability.',
    'ចាប់ផ្ដើមពីទេសភាពប្រាសាទកម្ពុជា។ នេះជាការណែនាំទូទៅ មិនមែនម៉ោងបើក តម្លៃ អាកាសធាតុ ឬភាពទំនេរបច្ចុប្បន្នទេ។',
  ],
  'authProviderUnavailable': [
    'Google and Apple sign-in are not configured yet.',
    'ការចូលតាម Google និង Apple មិនទាន់បានកំណត់រចនាសម្ព័ន្ធទេ។',
  ],
  'authUnavailable': [
    'Email delivery is not configured yet. Existing verified accounts can still sign in.',
    'ការផ្ញើអ៊ីមែលមិនទាន់បានកំណត់ទេ។ គណនីដែលបានផ្ទៀងផ្ទាត់រួចអាចចូលបាន។',
  ],
  'authNetwork': [
    'Cannot reach the server. Check your connection and try again. You have not been signed in.',
    'មិនអាចភ្ជាប់ម៉ាស៊ីនមេបាន។ សូមពិនិត្យការតភ្ជាប់ ហើយព្យាយាមម្ដងទៀត។ អ្នកមិនទាន់បានចូលគណនីទេ។',
  ],
  'authInvalidCredentials': [
    'Email or password is incorrect.',
    'អ៊ីមែល ឬពាក្យសម្ងាត់មិនត្រឹមត្រូវ។',
  ],
  'authUnverified': [
    'Verify your email before signing in.',
    'សូមផ្ទៀងផ្ទាត់អ៊ីមែល មុនចូលគណនី។',
  ],
  'authInvalidCode': [
    'This code or link is invalid or expired. Request a new email and use its latest code.',
    'លេខកូដ ឬតំណនេះមិនត្រឹមត្រូវ ឬផុតកំណត់។ ស្នើសុំអ៊ីមែលថ្មី ហើយប្រើលេខកូដចុងក្រោយ។',
  ],
  'authRateLimit': [
    'Too many attempts. Please wait before trying again.',
    'បានព្យាយាមច្រើនដងពេក។ សូមរង់ចាំមុនព្យាយាមម្ដងទៀត។',
  ],
  'authRetryAt': ['Try again after', 'ព្យាយាមម្ដងទៀតក្រោយ'],
  'authRegistrationFailed': [
    'Account creation could not be completed. Try signing in or recovering your password.',
    'មិនអាចបញ្ចប់ការបង្កើតគណនីបាន។ សាកល្បងចូល ឬកំណត់ពាក្យសម្ងាត់ឡើងវិញ។',
  ],
  'authFailed': [
    'That could not be completed. Please try again.',
    'មិនអាចបញ្ចប់បាន។ សូមព្យាយាមម្ដងទៀត។',
  ],
  'authCancelled': [
    'Sign-in was cancelled. You are not signed in.',
    'ការចូលត្រូវបានបោះបង់។ អ្នកមិនទាន់ចូលគណនីទេ។',
  ],
  'authExpired': [
    'Your session expired. Please sign in again.',
    'សម័យចូលរបស់អ្នកផុតកំណត់។ សូមចូលម្ដងទៀត។',
  ],
  'authLogoutOffline': [
    'Signed out on this device. The server could not be reached to revoke the session.',
    'បានចេញពីគណនីលើឧបករណ៍នេះ។ មិនអាចភ្ជាប់ម៉ាស៊ីនមេដើម្បីលុបសម័យចូលបានទេ។',
  ],
  'authRestoring': ['Restoring your session…', 'កំពុងស្ដារសម័យចូលរបស់អ្នក…'],
  'authWorking': ['Please wait…', 'សូមរង់ចាំ…'],
  'authRetry': ['Retry connection', 'ព្យាយាមភ្ជាប់ម្ដងទៀត'],
  'authLinkFailed': ['Could not open this link.', 'មិនអាចបើកតំណនេះបាន។'],
};

extension AuthCopy on BuildContext {
  String a(String key) => _copy[key]?[isKhmer ? 1 : 0] ?? t(key);
}
