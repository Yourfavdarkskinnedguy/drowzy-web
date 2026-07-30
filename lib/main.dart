import 'dart:async'; // <-- added for unawaited
import 'dart:html' as html; // web-only: powers the lazy YouTube embed
import 'dart:math';
import 'dart:ui';
import 'dart:ui_web' as ui_web; // web-only: platform view registry

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://timbpltkylvbrsgngqhk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRpbWJwbHRreWx2YnJzZ25ncWhrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2MTI2MDUsImV4cCI6MjA4OTE4ODYwNX0.dWAmSew_eR9pPDfz5XEqP-pT6_yw4zdNDp-l1MJfEc8',
  );

  runApp(const DrowzyWeb());
}

// ─────────────────────────────────────────────────────────────────
//  DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────
const Color _bg        = Color(0xFF060B14);
const Color _bgCard    = Color(0xFF0C1628);
const Color _bgSection = Color(0xFF08101E);
const Color _teal      = Color(0xFF00E5CC);
const Color _tealDim   = Color(0xFF00BDA8);
const Color _textHigh  = Colors.white;
const Color _textMid   = Color(0xFF94A3B8);
const Color _textLow   = Color(0xFF475569);
const Color _border    = Color(0xFF1A2845);

// ─────────────────────────────────────────────────────────────────
//  EXTERNAL LINKS
// ─────────────────────────────────────────────────────────────────
const String _playStoreUrl =
    'https://play.google.com/store/apps/details?id=app.drowzy.drive&pcampaignid=web_share';
const String _youtubeVideoId = 'YfGo1URruwA';
const String _youtubeEmbedUrl =
    'https://www.youtube-nocookie.com/embed/$_youtubeVideoId?autoplay=1&rel=0&modestbranding=1&playsinline=1';
const String _youtubeThumbUrl =
    'https://img.youtube.com/vi/$_youtubeVideoId/maxresdefault.jpg';

Future<void> _openPlayStore() => launchUrl(
      Uri.parse(_playStoreUrl),
      webOnlyWindowName: '_blank',
    );

// ─────────────────────────────────────────────────────────────────
//  GLOBAL KEYS FOR SCROLL TARGETS
// ─────────────────────────────────────────────────────────────────
final _featuresKey = GlobalKey();
final _videoKey = GlobalKey();
final _howItWorksKey = GlobalKey();
final _whyDrowzyKey = GlobalKey();
final _roadmapKey = GlobalKey();
final _downloadKey = GlobalKey();

// ─────────────────────────────────────────────────────────────────
//  APP
// ─────────────────────────────────────────────────────────────────
class DrowzyWeb extends StatelessWidget {
  const DrowzyWeb({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drowzy — AI Drowsiness Alerts. Available now on Android.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        useMaterial3: true,
        fontFamily: 'Inter',
        textSelectionTheme: const TextSelectionThemeData(cursorColor: _teal),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const HomePage());
          case '/email-confirmed':
            return MaterialPageRoute(builder: (_) => const EmailConfirmedPage());
          case '/delete-account':
            return MaterialPageRoute(builder: (_) => const DeleteAccountPage());
          case '/privacy':
            return MaterialPageRoute(builder: (_) => const PrivacyPage());
          case '/terms':
            return MaterialPageRoute(builder: (_) => const TermsPage());
          case '/support':
            return MaterialPageRoute(builder: (_) => const SupportPage());
          default:
            return MaterialPageRoute(builder: (_) => const HomePage());
        }
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  WAITLIST SIGNUP RESULT
// ═════════════════════════════════════════════════════════════════
class WaitlistSignupResult {
  final bool success;
  final bool alreadyOnList;
  final int? queuePosition;
  final String? referralCode;
  final String? errorMessage;

  const WaitlistSignupResult({
    required this.success,
    this.alreadyOnList = false,
    this.queuePosition,
    this.referralCode,
    this.errorMessage,
  });
}

// ═════════════════════════════════════════════════════════════════
//  WAITLIST SERVICE  –  Supabase-backed signup, referrals, queue position
//  (Now scoped to the iOS waitlist; Android ships via Google Play.)
// ═════════════════════════════════════════════════════════════════
class WaitlistService {
  WaitlistService._();
  static final WaitlistService instance = WaitlistService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Total number of people currently on the waitlist.
  Future<int> getWaitlistCount() async {
    try {
      final res = await _client
          .from('waitlist')
          .select('id')
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  /// Generates a short, URL-safe, human-friendly referral code.
  String _generateReferralCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    final rand = Random.secure();
    return List.generate(7, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Reads the `?ref=` query parameter from the current URL, if present.
  String? readReferralCodeFromUrl() {
    final ref = Uri.base.queryParameters['ref'];
    if (ref == null || ref.trim().isEmpty) return null;
    return ref.trim();
  }

  /// Builds a shareable referral link for the given code.
  String buildReferralLink(String referralCode) {
    return 'https://drowzy.app/?ref=$referralCode';
  }

  /// Calls the `send-waitlist-email` edge function. Fire-and-forget:
  /// a failure here should never block or fail the signup itself.
  Future<void> _sendConfirmationEmail({
    required String email,
    required int queuePosition,
    required String referralCode,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'send-waitlist-email',
        body: {
          'email': email,
          'queue_position': queuePosition,
          'referral_link': buildReferralLink(referralCode),
          'referral_code': referralCode,
        },
      );

      if (res.status != 200) {
        // ignore: avoid_print
        print('send-waitlist-email non-200: ${res.status} ${res.data}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('send-waitlist-email invoke failed: $e');
    }
  }

  /// Signs an email up for the waitlist.
  Future<WaitlistSignupResult> joinWaitlist({
    required String email,
    String? referredByCode,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    var referralCode = _generateReferralCode();

    // Try inserting; on the rare chance of a referral code collision, retry.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _client.from('waitlist').insert({
          'email': normalizedEmail,
          'referral_code': referralCode,
          if (referredByCode != null && referredByCode.isNotEmpty)
            'referred_by': referredByCode,
        });

        final position = await getWaitlistCount();

        // Fire the confirmation email — don't await-block the UI on it,
        // but don't let it silently vanish either.
        unawaited(_sendConfirmationEmail(
          email: normalizedEmail,
          queuePosition: position,
          referralCode: referralCode,
        ));

        return WaitlistSignupResult(
          success: true,
          queuePosition: position,
          referralCode: referralCode,
        );
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          final isEmailConflict = e.message.contains('email');
          if (isEmailConflict) {
            return const WaitlistSignupResult(
              success: false,
              alreadyOnList: true,
              errorMessage: "You're already on the iOS waitlist!",
            );
          }
          // Referral code collision — regenerate and retry.
          referralCode = _generateReferralCode();
          continue;
        }
        return const WaitlistSignupResult(
          success: false,
          errorMessage: 'Something went wrong. Please try again.',
        );
      } catch (_) {
        return const WaitlistSignupResult(
          success: false,
          errorMessage: 'Network error. Please check your connection.',
        );
      }
    }

    return const WaitlistSignupResult(
      success: false,
      errorMessage: 'Something went wrong. Please try again.',
    );
  }

  /// Number of people a given referral code has successfully brought in.
  Future<int> getReferralCount(String referralCode) async {
    try {
      final res = await _client
          .from('waitlist')
          .select('id')
          .eq('referred_by', referralCode)
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }
}

// ═════════════════════════════════════════════════════════════════
//  DELETE ACCOUNT PAGE
// ═════════════════════════════════════════════════════════════════
class DeleteAccountPage extends StatelessWidget {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Delete Your Account'),
        backgroundColor: _bgSection,
        elevation: 0,
        foregroundColor: _textHigh,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to delete your Drowzy account',
              style: TextStyle(
                color: _textHigh,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'You can delete your Drowzy account and all associated data directly from the app. '
              'Here\'s how:',
              style: TextStyle(color: _textMid, fontSize: 16, height: 1.6),
            ),
            SizedBox(height: 20),
            _DeleteStep(
              number: '1',
              text: 'Open the Drowzy app and sign in to your account.',
            ),
            SizedBox(height: 16),
            _DeleteStep(
              number: '2',
              text: 'Tap the Profile tab in the bottom navigation bar.',
            ),
            SizedBox(height: 16),
            _DeleteStep(
              number: '3',
              text: 'Scroll down and tap "Delete Account".',
            ),
            SizedBox(height: 16),
            _DeleteStep(
              number: '4',
              text: 'Read the warning carefully. You will need to type the word DELETE to confirm.',
            ),
            SizedBox(height: 16),
            _DeleteStep(
              number: '5',
              text: 'Tap the red Delete button. Your account, trip history, safety scores, '
                  'subscription, and all associated data will be permanently erased.',
            ),
            SizedBox(height: 24),
            Text(
              'What data is deleted?',
              style: TextStyle(
                color: _textHigh,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 12),
            _BulletPoint(text: 'Your Drowzy account and login credentials'),
            _BulletPoint(text: 'All your trip history and safety scores'),
            _BulletPoint(text: 'Your subscription (no partial refund is issued)'),
            _BulletPoint(text: 'All app data stored on our servers'),
            SizedBox(height: 20),
            Text(
              'If you have any questions or need help, contact us at support@drowzy.app.',
              style: TextStyle(color: _textMid, fontSize: 16, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteStep extends StatelessWidget {
  final String number;
  final String text;
  const _DeleteStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: _teal,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: _textMid, fontSize: 16, height: 1.6)),
        ),
      ],
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•', style: TextStyle(color: _teal, fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: _textMid, fontSize: 16, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  EMAIL CONFIRMATION PAGE
// ═════════════════════════════════════════════════════════════════
class EmailConfirmedPage extends StatelessWidget {
  const EmailConfirmedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: _teal.withOpacity(0.3), width: 2),
                ),
                child: const Icon(Icons.check_circle_outline, color: _teal, size: 40),
              ),
              const SizedBox(height: 28),
              const Text(
                'Email Confirmed!',
                style: TextStyle(
                  color: _textHigh,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You\'re all set. We\'ll email you the moment Drowzy for iOS launches.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMid, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 36),
              _TealButton(
                label: 'Go to Homepage',
                onTap: () => Navigator.pushReplacementNamed(context, '/'),
                paddingH: 24,
                paddingV: 14,
                fontSize: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  HOME PAGE  –  manages scroll targets + sticky CTA bar
// ─────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scroll = ScrollController();
  double _offset = 0;

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (mounted) setState(() => _offset = _scroll.offset);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showStickyBar = _offset > 640;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _scroll,
            child: Column(
              children: [
                _Hero(onWaitlistTap: () => _scrollTo(_downloadKey)),
                const _TrustBar(),
                Container(key: _videoKey, child: const _VideoSection()),
                Container(key: _featuresKey, child: const _Features()),
                Container(key: _howItWorksKey, child: const _HowItWorks()),
                Container(key: _whyDrowzyKey, child: const _WhyDrowzy()),
                Container(key: _roadmapKey, child: const _RoadmapSection()),
                Container(key: _downloadKey, child: const _DownloadSection()),
                const _Footer(),
                SizedBox(height: showStickyBar ? 84 : 0),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _NavBar(
              offset: _offset,
              onFeaturesTap: () => _scrollTo(_featuresKey),
              onHowItWorksTap: () => _scrollTo(_howItWorksKey),
              onRoadmapTap: () => _scrollTo(_roadmapKey),
              onIosWaitlistTap: () => _scrollTo(_downloadKey),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            bottom: showStickyBar ? 0 : -120,
            left: 0,
            right: 0,
            child: _StickyCtaBar(onIosWaitlistTap: () => _scrollTo(_downloadKey)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  NAV BAR
// ─────────────────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final double offset;
  final VoidCallback onFeaturesTap;
  final VoidCallback onHowItWorksTap;
  final VoidCallback onRoadmapTap;
  final VoidCallback onIosWaitlistTap;

  const _NavBar({
    required this.offset,
    required this.onFeaturesTap,
    required this.onHowItWorksTap,
    required this.onRoadmapTap,
    required this.onIosWaitlistTap,
  });

  @override
  Widget build(BuildContext context) {
    final scrolled = offset > 30;
    final w        = MediaQuery.of(context).size.width;
    final mobile   = w < 900;
    final tiny     = w < 460;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 88,
          color: scrolled ? _bg.withOpacity(0.88) : Colors.transparent,
          padding: EdgeInsets.symmetric(horizontal: tiny ? 18 : 56),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      'https://drowzy.app/logo1.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      semanticLabel: 'Drowzy logo',
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _teal.withOpacity(0.28)),
                        ),
                        child: const Icon(Icons.remove_red_eye_outlined, color: _teal, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                      children: [
                        TextSpan(text: 'Drow', style: TextStyle(color: _textHigh)),
                        TextSpan(text: 'zy', style: TextStyle(color: _teal)),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!mobile) ...[
                _NavLink('Features', onTap: onFeaturesTap),
                const SizedBox(width: 28),
                _NavLink('How It Works', onTap: onHowItWorksTap),
                const SizedBox(width: 28),
                _NavLink('Roadmap', onTap: onRoadmapTap),
                const SizedBox(width: 20),
                TextButton(
                  onPressed: onIosWaitlistTap,
                  style: TextButton.styleFrom(foregroundColor: _textMid),
                  child: const Text('iOS Waitlist', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 20),
              ],
              Semantics(
                button: true,
                label: 'Download Drowzy on Google Play',
                child: _TealButton(
                  label: tiny ? 'Google Play' : 'Download on Google Play',
                  icon: Icons.android,
                  onTap: _openPlayStore,
                  paddingH: tiny ? 14 : 20,
                  paddingV: 10,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _NavLink(this.label, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _textMid,
        overlayColor: _teal.withOpacity(0.06),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  SHARED: TEAL BUTTON (primary CTA — supports an optional leading icon)
// ─────────────────────────────────────────────────────────────────
class _TealButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double paddingH;
  final double paddingV;
  final double fontSize;
  const _TealButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.paddingH = 26,
    this.paddingV = 14,
    this.fontSize  = 15,
  });

  @override
  State<_TealButton> createState() => _TealButtonState();
}

class _TealButtonState extends State<_TealButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: widget.paddingH,
            vertical:   widget.paddingV,
          ),
          decoration: BoxDecoration(
            color: _h ? _tealDim : _teal,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _h
                ? [BoxShadow(color: _teal.withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 4))]
                : [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 4, color: Colors.black),
                SizedBox(width: widget.fontSize * 0.5),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.fontSize,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  SHARED: OUTLINE BUTTON
// ─────────────────────────────────────────────────────────────────
class _OutlineButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.icon, required this.onTap});

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(
            color: _h ? _bgCard : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _h ? _teal.withOpacity(0.55) : _border,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20, color: _textHigh),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: const TextStyle(
                  color: _textHigh,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  SHARED: SECTION LABEL
// ─────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _teal,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 3.0,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  HERO
// ═════════════════════════════════════════════════════════════════
class _Hero extends StatelessWidget {
  final VoidCallback onWaitlistTap;
  const _Hero({required this.onWaitlistTap});

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final h      = MediaQuery.of(context).size.height;
    final mobile = w < 860;
    final hpad   = mobile ? 24.0 : 80.0;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: h * 0.94),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.35, -0.55),
          radius: 1.5,
          colors: [Color(0xFF0F2240), _bg],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80, right: -80,
            child: Container(
              width: 560, height: 560,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_teal.withOpacity(0.05), Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(hpad, 112, hpad, 88),
            child: mobile
                ? Column(
                    children: [
                      const Center(child: _EyeGraphic(size: 340)),
                      const SizedBox(height: 44),
                      _HeroCopy(centered: true, onWaitlistTap: onWaitlistTap),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 55, child: _HeroCopy(onWaitlistTap: onWaitlistTap)),
                      const SizedBox(width: 60),
                      const Expanded(flex: 45, child: Center(child: _EyeGraphic(size: 520))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  HERO COPY
// ═════════════════════════════════════════════════════════════════
class _HeroCopy extends StatelessWidget {
  final bool centered;
  final VoidCallback onWaitlistTap;
  const _HeroCopy({this.centered = false, required this.onWaitlistTap});

  @override
  Widget build(BuildContext context) {
    final ca = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final ta = centered ? TextAlign.center : TextAlign.left;
    final ma = centered ? WrapAlignment.center : WrapAlignment.start;
    final mobile = MediaQuery.of(context).size.width < 860;

    return Column(
      crossAxisAlignment: ca,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _teal.withOpacity(0.08),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: _teal.withOpacity(0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              const Text(
                'Live now on Google Play',
                style: TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Catch fatigue\nbefore it\ncatches you.',
          textAlign: ta,
          style: TextStyle(
            color: _textHigh,
            fontSize: mobile ? 42 : 58,
            fontWeight: FontWeight.w800,
            height: 1.08,
            letterSpacing: -2.0,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Drowzy watches your eyes in real time using on-device AI and sounds '
          'the alarm the instant drowsiness is detected — before you even feel it. '
          'Android is available today. iPhone users can join the waitlist.',
          textAlign: ta,
          style: const TextStyle(
            color: _textMid,
            fontSize: 17,
            height: 1.65,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 40),
        Wrap(
          alignment: ma,
          spacing: 14,
          runSpacing: 14,
          children: [
            Semantics(
              button: true,
              label: 'Download Drowzy on Google Play',
              child: _TealButton(
                label: 'Download on Google Play',
                icon: Icons.android,
                onTap: _openPlayStore,
                paddingH: 28,
                paddingV: 16,
                fontSize: 15,
              ),
            ),
            _OutlineButton(
              label: 'Join iOS Waitlist',
              icon: Icons.phone_iphone,
              onTap: onWaitlistTap,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: const [
            Icon(Icons.lock_outline, color: _textLow, size: 13),
            SizedBox(width: 6),
            Text(
              'Free to try · No sign-up required · 100% on-device',
              style: TextStyle(color: _textLow, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  WAITLIST SIGNUP FORM (iOS)  – duplicate detection, queue position, referral
// ═════════════════════════════════════════════════════════════════
class _WaitlistForm extends StatefulWidget {
  final bool centered;
  const _WaitlistForm({required this.centered});

  @override
  State<_WaitlistForm> createState() => _WaitlistFormState();
}

class _WaitlistFormState extends State<_WaitlistForm> {
  final _emailCtrl = TextEditingController();
  final _formKey   = GlobalKey<FormState>();

  bool _loading = false;
  bool _success = false;
  String? _errorMsg;
  int? _queuePosition;
  String? _referralCode;
  bool _linkCopied = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading  = true;
      _errorMsg = null;
    });

    final result = await WaitlistService.instance.joinWaitlist(
      email: _emailCtrl.text,
      referredByCode: WaitlistService.instance.readReferralCodeFromUrl(),
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _loading       = false;
        _success       = true;
        _queuePosition = result.queuePosition;
        _referralCode  = result.referralCode;
      });
    } else {
      setState(() {
        _loading  = false;
        _errorMsg = result.errorMessage ?? 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _copyReferralLink() async {
    if (_referralCode == null) return;
    final link = WaitlistService.instance.buildReferralLink(_referralCode!);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() => _linkCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 480;
    final ma = widget.centered ? MainAxisAlignment.center : MainAxisAlignment.start;
    final ca = widget.centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    if (_success) {
      final referralLink = _referralCode != null
          ? WaitlistService.instance.buildReferralLink(_referralCode!)
          : null;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        decoration: BoxDecoration(
          color: _teal.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _teal.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: ca,
          children: [
            Row(
              mainAxisAlignment: ma,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: _teal, size: 26),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _queuePosition != null
                        ? "You're #$_queuePosition on the iOS list!"
                        : "You're on the iOS list!",
                    style: const TextStyle(
                      color: _textHigh,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (referralLink != null) ...[
              const SizedBox(height: 16),
              Text(
                'Move up the list — share your link and skip the queue when friends join.',
                textAlign: widget.centered ? TextAlign.center : TextAlign.left,
                style: const TextStyle(color: _textMid, fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        referralLink,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _textMid, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _copyReferralLink,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _linkCopied ? Icons.check : Icons.copy_rounded,
                              color: _teal,
                              size: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _linkCopied ? 'Copied' : 'Copy',
                              style: const TextStyle(
                                color: _teal,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: mobile
          ? Column(
              crossAxisAlignment: ca,
              children: [
                _emailField(),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: _joinButton()),
                if (_errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
              ],
            )
          : Row(
              mainAxisAlignment: ma,
              children: [
                Flexible(child: _emailField()),
                const SizedBox(width: 12),
                _joinButton(),
                if (_errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      _errorMsg!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _emailField() {
    return SizedBox(
      width: 320,
      child: TextFormField(
        controller: _emailCtrl,
        enabled: !_loading,
        style: const TextStyle(color: _textHigh, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter your email',
          hintStyle: const TextStyle(color: _textLow, fontSize: 15),
          filled: true,
          fillColor: _bgCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _teal),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Email is required';
          }
          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
          if (!emailRegex.hasMatch(value.trim())) {
            return 'Enter a valid email';
          }
          return null;
        },
        onFieldSubmitted: (_) => _submit(),
      ),
    );
  }

  Widget _joinButton() {
    return MouseRegion(
      cursor: _loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _loading ? null : _submit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _loading ? _teal.withOpacity(0.7) : _teal,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _loading
                ? []
                : [BoxShadow(color: _teal.withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : const Text(
                  'Join Waitlist',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.1,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  EYE GRAPHIC & PAINTER
// ─────────────────────────────────────────────────────────────────
class _EyeGraphic extends StatefulWidget {
  final double size;
  const _EyeGraphic({super.key, this.size = 320});

  @override
  State<_EyeGraphic> createState() => _EyeGraphicState();
}

class _EyeGraphicState extends State<_EyeGraphic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width:  widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _EyePainter(t: _ctrl.value),
          child: Center(
            child: Icon(
              Icons.remove_red_eye_outlined,
              color: _teal,
              size: widget.size * 0.18,
            ),
          ),
        ),
      ),
    );
  }
}

class _EyePainter extends CustomPainter {
  final double t;
  const _EyePainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final c  = Offset(size.width / 2, size.height / 2);
    final r  = size.width / 2;

    const ringR = [0.27, 0.42, 0.57, 0.73, 0.92];
    for (int i = 0; i < ringR.length; i++) {
      canvas.drawCircle(
        c,
        r * ringR[i],
        Paint()
          ..color       = _teal.withOpacity((0.16 - i * 0.024).clamp(0.02, 0.18))
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    canvas.drawCircle(
      c,
      r * 0.27,
      Paint()
        ..color = _teal.withOpacity(0.06)
        ..style = PaintingStyle.fill,
    );

    const double a1 = 0.0;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.42),
      a1,
      3.14 * 0.42,
      false,
      Paint()
        ..color       = _teal.withOpacity(0.70)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap   = StrokeCap.round,
    );

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.57),
      1.57,
      3.14 * 0.28,
      false,
      Paint()
        ..color       = _teal.withOpacity(0.32)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap   = StrokeCap.round,
    );

    const double dotAngle = a1 + 3.14 * 0.42;
    canvas.drawCircle(
      Offset(c.dx + r * 0.42 * cos(dotAngle), c.dy + r * 0.42 * sin(dotAngle)),
      3.5,
      Paint()
        ..color = _teal
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_EyePainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────
//  TRUST BAR — real, honest, current claims
// ─────────────────────────────────────────────────────────────────
class _TrustBar extends StatelessWidget {
  const _TrustBar();

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 36, horizontal: mobile ? 24 : 80),
      decoration: BoxDecoration(
        color: _bgSection,
        border: Border.symmetric(horizontal: BorderSide(color: _border)),
      ),
      child: mobile
          ? const Column(
              children: [
                _TrustItem(icon: Icons.android, label: 'Live on Google Play'),
                SizedBox(height: 22),
                _TrustItem(icon: Icons.lock_outline, label: 'On-device processing only'),
                SizedBox(height: 22),
                _TrustItem(icon: Icons.phone_iphone, label: 'iOS in final App Store review'),
              ],
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TrustItem(icon: Icons.android, label: 'Live on Google Play'),
                _TrustItem(icon: Icons.lock_outline, label: 'On-device processing only'),
                _TrustItem(icon: Icons.phone_iphone, label: 'iOS in final App Store review'),
              ],
            ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _teal, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: _textMid, fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  VIDEO SECTION — "See Drowzy in Action" (lazy-loaded YouTube embed)
// ═════════════════════════════════════════════════════════════════
class _VideoSection extends StatelessWidget {
  const _VideoSection();

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 760;
    final hpad   = mobile ? 24.0 : 80.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: hpad, vertical: 100),
      color: _bg,
      child: Column(
        children: [
          const _SectionLabel('SEE IT IN ACTION'),
          const SizedBox(height: 16),
          Text(
            'Watch Drowzy catch\na microsleep in real time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textHigh,
              fontSize: mobile ? 30 : 40,
              fontWeight: FontWeight.w700,
              height: 1.18,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 48),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _teal.withOpacity(0.18)),
                    boxShadow: [
                      BoxShadow(color: _teal.withOpacity(0.08), blurRadius: 60, offset: const Offset(0, 20)),
                    ],
                  ),
                  child: const _LazyYoutubePlayer(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a thumbnail with a play button; swaps to a live YouTube iframe
/// only after the user taps, keeping the initial page load lightweight.
class _LazyYoutubePlayer extends StatefulWidget {
  const _LazyYoutubePlayer();

  @override
  State<_LazyYoutubePlayer> createState() => _LazyYoutubePlayerState();
}

class _LazyYoutubePlayerState extends State<_LazyYoutubePlayer> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    if (_playing) {
      return const _YoutubeIframe(viewId: 'drowzy-youtube-embed');
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _playing = true),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _youtubeThumbUrl,
              fit: BoxFit.cover,
              semanticLabel: 'Drowzy campaign video thumbnail',
              errorBuilder: (_, __, ___) => Container(color: _bgCard),
            ),
            Container(color: Colors.black.withOpacity(0.28)),
            Center(
              child: Semantics(
                button: true,
                label: 'Play the Drowzy campaign video',
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: _teal,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: _teal.withOpacity(0.4), blurRadius: 30, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 42),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final Set<String> _registeredPlatformViews = {};

/// Registers (once) and renders an HtmlElementView hosting a YouTube iframe.
class _YoutubeIframe extends StatefulWidget {
  final String viewId;
  const _YoutubeIframe({required this.viewId});

  @override
  State<_YoutubeIframe> createState() => _YoutubeIframeState();
}

class _YoutubeIframeState extends State<_YoutubeIframe> {
  @override
  void initState() {
    super.initState();
    if (!_registeredPlatformViews.contains(widget.viewId)) {
      _registeredPlatformViews.add(widget.viewId);
      ui_web.platformViewRegistry.registerViewFactory(widget.viewId, (int _) {
        final iframe = html.IFrameElement()
          ..src = _youtubeEmbedUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allowFullscreen = true;
        iframe.setAttribute(
          'allow',
          'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture',
        );
        return iframe;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: widget.viewId);
  }
}

// ─────────────────────────────────────────────────────────────────
//  FEATURES
// ─────────────────────────────────────────────────────────────────
class _Features extends StatelessWidget {
  const _Features();

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 820;
    final hpad   = mobile ? 24.0 : 80.0;

    const cards = [
      _FCard(icon: Icons.lock_outline, title: '100% Private', desc: 'All processing stays on your device. Not a single frame of video ever leaves your phone — guaranteed.', tag: 'On-device ML'),
      _FCard(icon: Icons.notifications_active_outlined, title: 'Instant Alerts', desc: 'Loud alarm and vibration even in silent mode. Configurable sounds so you\'ll always wake up when it matters.', tag: 'Bypass silent mode'),
      _FCard(icon: Icons.shield_outlined, title: 'Safety Score', desc: 'Track drowsiness patterns across every drive. Share reports with your insurer or fleet manager.', tag: 'Drive analytics'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: hpad, vertical: 100),
      color: _bgSection,
      child: Column(
        children: [
          const _SectionLabel('FEATURES'),
          const SizedBox(height: 16),
          const Text('Everything you need.\nNothing you don\'t.', textAlign: TextAlign.center,
              style: TextStyle(color: _textHigh, fontSize: 40, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.8)),
          const SizedBox(height: 64),
          mobile
              ? Column(children: [cards[0], const SizedBox(height: 20), cards[1], const SizedBox(height: 20), cards[2]])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: cards[0]), const SizedBox(width: 20),
                  Expanded(child: cards[1]), const SizedBox(width: 20),
                  Expanded(child: cards[2]),
                ]),
        ],
      ),
    );
  }
}

class _FCard extends StatefulWidget {
  final IconData icon;
  final String   title;
  final String   desc;
  final String   tag;
  const _FCard({required this.icon, required this.title, required this.desc, required this.tag});

  @override
  State<_FCard> createState() => _FCardState();
}

class _FCardState extends State<_FCard> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border(
            top:    BorderSide(color: _h ? _teal.withOpacity(0.55) : _teal.withOpacity(0.12), width: 2),
            left:   BorderSide(color: _border),
            right:  BorderSide(color: _border),
            bottom: BorderSide(color: _border),
          ),
          boxShadow: _h ? [BoxShadow(color: _teal.withOpacity(0.07), blurRadius: 40, offset: const Offset(0, 8))] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(13)), child: Icon(widget.icon, color: _teal, size: 24)),
            const SizedBox(height: 22),
            Text(widget.title, style: const TextStyle(color: _textHigh, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(widget.desc, style: const TextStyle(color: _textMid, fontSize: 14, height: 1.6)),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _teal.withOpacity(0.08), borderRadius: BorderRadius.circular(7)),
              child: Text(widget.tag, style: const TextStyle(color: _teal, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  HOW IT WORKS
// ─────────────────────────────────────────────────────────────────
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 820;
    final hpad   = mobile ? 24.0 : 80.0;

    const steps = [
      _Step(n: '01', title: 'Mount your phone', desc: 'Place your phone on a dashboard mount so the front camera has a clear view of your face before you set off.'),
      _Step(n: '02', title: 'Tap Start Driving', desc: 'Open Drowzy and press the big button. No sign-up required — monitoring begins in under a second.'),
      _Step(n: '03', title: 'Drive with confidence', desc: 'Drowzy watches continuously and blasts an alarm through your speakers the moment fatigue is detected.'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: hpad, vertical: 100),
      color: _bg,
      child: Column(
        children: [
          const _SectionLabel('HOW IT WORKS'),
          const SizedBox(height: 16),
          const Text('Up and running\nin 30 seconds.', textAlign: TextAlign.center,
              style: TextStyle(color: _textHigh, fontSize: 40, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.8)),
          const SizedBox(height: 64),
          mobile
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [steps[0], const SizedBox(height: 36), steps[1], const SizedBox(height: 36), steps[2]])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: steps[0]), const SizedBox(width: 40), Expanded(child: steps[1]), const SizedBox(width: 40), Expanded(child: steps[2])]),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String title;
  final String desc;
  const _Step({required this.n, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(n, style: TextStyle(color: _teal.withOpacity(0.36), fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1)),
        const SizedBox(height: 18),
        Text(title, style: const TextStyle(color: _textHigh, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(desc, style: const TextStyle(color: _textMid, fontSize: 15, height: 1.65)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  WHY DROWZY
// ═════════════════════════════════════════════════════════════════
class _WhyDrowzy extends StatelessWidget {
  const _WhyDrowzy();

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 760;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 120, vertical: 100),
      color: _bgSection,
      child: Column(
        children: [
          const _SectionLabel('WHY DROWZY EXISTS'),
          const SizedBox(height: 16),
          Text(
            'Drowsy driving kills\nmore people than we talk about.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textHigh,
              fontSize: mobile ? 30 : 38,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Long commutes, night shifts, and rideshare hours push drivers past '
                  'the point where willpower can keep their eyes open. Coffee helps for '
                  'a while. It doesn\'t help when it matters most — in the seconds before '
                  'a microsleep takes over.',
                  style: TextStyle(color: _textMid, fontSize: mobile ? 15 : 16, height: 1.75),
                ),
                const SizedBox(height: 18),
                Text(
                  'We built Drowzy because the tools that exist either cost thousands '
                  'and ship inside a car, or don\'t exist at all for the rest of us. A phone '
                  'already has a camera, a speaker, and is already on your dashboard. '
                  'That\'s enough to save a life — it just needed the right software.',
                  style: TextStyle(color: _textMid, fontSize: mobile ? 15 : 16, height: 1.75),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: _teal.withOpacity(0.14), shape: BoxShape.circle),
                      child: const Center(
                        child: Icon(Icons.person_outline, color: _teal, size: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('The Drowzy Team', style: TextStyle(color: _textHigh, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('Building in Nigeria, for drivers everywhere', style: TextStyle(color: _textMid, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.forum_outlined, color: _teal, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Real driver stories are on their way — we\'re a brand-new app on Google Play '
                    'and would rather wait for genuine reviews than invent them.',
                    style: TextStyle(color: _textMid, fontSize: mobile ? 13 : 13.5, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  ROADMAP
// ═════════════════════════════════════════════════════════════════
class _RoadmapSection extends StatelessWidget {
  const _RoadmapSection();

  @override
  Widget build(BuildContext context) {
    final w      = MediaQuery.of(context).size.width;
    final mobile = w < 820;
    final hpad   = mobile ? 24.0 : 80.0;

    const milestones = [
      _RoadmapItem(
        status: _RoadmapStatus.done,
        title: 'Core drowsiness detection engine',
        desc: 'On-device eye-closure tracking, tuned and tested across lighting conditions.',
      ),
      _RoadmapItem(
        status: _RoadmapStatus.done,
        title: 'Android launch on Google Play',
        desc: 'Drowzy is live and available to download today, with guest mode and a free trial.',
      ),
      _RoadmapItem(
        status: _RoadmapStatus.inProgress,
        title: 'iOS App Store review',
        desc: 'Final polish and review response — currently in progress with Apple.',
      ),
      _RoadmapItem(
        status: _RoadmapStatus.upcoming,
        title: 'iOS public launch',
        desc: 'Waitlist members get first access and a founding-member discount.',
      ),
      _RoadmapItem(
        status: _RoadmapStatus.upcoming,
        title: 'Fleet & insurer reporting',
        desc: 'Shareable safety-score reports for rideshare fleets and insurance partners.',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: hpad, vertical: 100),
      color: _bg,
      child: Column(
        children: [
          const _SectionLabel('ROADMAP'),
          const SizedBox(height: 16),
          const Text(
            'Here\'s what\'s next.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textHigh, fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.8),
          ),
          const SizedBox(height: 64),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                for (int i = 0; i < milestones.length; i++) milestones[i],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RoadmapStatus { done, inProgress, upcoming }

class _RoadmapItem extends StatelessWidget {
  final _RoadmapStatus status;
  final String title;
  final String desc;
  const _RoadmapItem({required this.status, required this.title, required this.desc});

  Color get _dotColor {
    switch (status) {
      case _RoadmapStatus.done:
        return _teal;
      case _RoadmapStatus.inProgress:
        return _teal;
      case _RoadmapStatus.upcoming:
        return _textLow;
    }
  }

  IconData get _icon {
    switch (status) {
      case _RoadmapStatus.done:
        return Icons.check_circle;
      case _RoadmapStatus.inProgress:
        return Icons.autorenew;
      case _RoadmapStatus.upcoming:
        return Icons.radio_button_unchecked;
    }
  }

  String get _badgeLabel {
    switch (status) {
      case _RoadmapStatus.done:
        return 'DONE';
      case _RoadmapStatus.inProgress:
        return 'IN PROGRESS';
      case _RoadmapStatus.upcoming:
        return 'UPCOMING';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: status == _RoadmapStatus.inProgress ? _teal.withOpacity(0.4) : _border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: _dotColor, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(color: _textHigh, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _dotColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _badgeLabel,
                          style: TextStyle(color: _dotColor, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(desc, style: const TextStyle(color: _textMid, fontSize: 13.5, height: 1.6)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  DOWNLOAD SECTION — Android CTA card + iOS waitlist card
// ═════════════════════════════════════════════════════════════════
class _DownloadSection extends StatelessWidget {
  const _DownloadSection();

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 900;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 24 : 80, vertical: 100),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF091828), _bg]),
      ),
      child: Column(
        children: [
          const _SectionLabel('GET DROWZY'),
          const SizedBox(height: 16),
          Text('Don\'t drive tired.\nGet Drowzy today.', textAlign: TextAlign.center,
              style: TextStyle(color: _textHigh, fontSize: mobile ? 34 : 48, fontWeight: FontWeight.w800, height: 1.12, letterSpacing: -1.2)),
          const SizedBox(height: 14),
          const Text('Available now for Android. iPhone is next.', textAlign: TextAlign.center, style: TextStyle(color: _textMid, fontSize: 16)),
          const SizedBox(height: 56),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: mobile
                ? Column(
                    children: const [
                      _AndroidCard(),
                      SizedBox(height: 24),
                      _IosWaitlistCard(),
                    ],
                  )
                : const IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _AndroidCard()),
                        SizedBox(width: 24),
                        Expanded(child: _IosWaitlistCard()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AndroidCard extends StatelessWidget {
  const _AndroidCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _teal.withOpacity(0.35), width: 1.5),
        boxShadow: [BoxShadow(color: _teal.withOpacity(0.06), blurRadius: 40, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('AVAILABLE NOW', style: TextStyle(color: _teal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.android, color: _teal, size: 28),
          ),
          const SizedBox(height: 20),
          const Text('Android', style: TextStyle(color: _textHigh, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            'Download Drowzy from Google Play and start your first drive in under a minute. '
            'Free to try, with no account required.',
            style: TextStyle(color: _textMid, fontSize: 14.5, height: 1.6),
          ),
          const SizedBox(height: 28),
          Semantics(
            button: true,
            label: 'Download Drowzy on Google Play',
            child: SizedBox(
              width: double.infinity,
              child: _TealButton(
                label: 'Get it on Google Play',
                icon: Icons.android,
                onTap: _openPlayStore,
                paddingH: 24,
                paddingV: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosWaitlistCard extends StatefulWidget {
  const _IosWaitlistCard();

  @override
  State<_IosWaitlistCard> createState() => _IosWaitlistCardState();
}

class _IosWaitlistCardState extends State<_IosWaitlistCard> {
  int _waitlistCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCount();
  }

  Future<void> _fetchCount() async {
    final count = await WaitlistService.instance.getWaitlistCount();
    if (mounted) setState(() => _waitlistCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: _textLow.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Text('COMING SOON', style: TextStyle(color: _textMid, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          ),
          const SizedBox(height: 20),
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: _textLow.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.phone_iphone, color: _textHigh, size: 28),
          ),
          const SizedBox(height: 20),
          const Text('iPhone', style: TextStyle(color: _textHigh, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            _waitlistCount > 0
                ? 'In final App Store review. Join ${_waitlistCount} others on the waitlist for early access and a founding-member discount.'
                : 'In final App Store review. Join the waitlist for early access and a founding-member discount.',
            style: const TextStyle(color: _textMid, fontSize: 14.5, height: 1.6),
          ),
          const SizedBox(height: 28),
          const _WaitlistForm(centered: false),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  STICKY CTA BAR
// ═════════════════════════════════════════════════════════════════
class _StickyCtaBar extends StatelessWidget {
  final VoidCallback onIosWaitlistTap;
  const _StickyCtaBar({required this.onIosWaitlistTap});

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 640;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 56, vertical: 16),
          decoration: BoxDecoration(
            color: _bg.withOpacity(0.94),
            border: const Border(top: BorderSide(color: _border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!mobile) ...[
                  const Icon(Icons.remove_red_eye_outlined, color: _teal, size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Ready to never drive drowsy again?',
                    style: TextStyle(color: _textHigh, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                ],
                Semantics(
                  button: true,
                  label: 'Download Drowzy on Google Play',
                  child: _TealButton(
                    label: mobile ? 'Google Play' : 'Download on Google Play',
                    icon: Icons.android,
                    onTap: _openPlayStore,
                    paddingH: mobile ? 16 : 22,
                    paddingV: 12,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 14),
                TextButton(
                  onPressed: onIosWaitlistTap,
                  style: TextButton.styleFrom(foregroundColor: _textMid),
                  child: Text(mobile ? 'iOS' : 'iOS Waitlist', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  FOOTER
// ─────────────────────────────────────────────────────────────────
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF1E293B)))),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'Download Drowzy on Google Play',
            child: _TealButton(
              label: 'Download on Google Play',
              icon: Icons.android,
              onTap: _openPlayStore,
              paddingH: 22,
              paddingV: 12,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              TextButton(onPressed: () => Navigator.pushNamed(context, '/support'), child: const Text('Support', style: TextStyle(color: Color(0xFF94A3B8)))),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/privacy'), child: const Text('Privacy', style: TextStyle(color: Color(0xFF94A3B8)))),
              TextButton(onPressed: () => Navigator.pushNamed(context, '/terms'), child: const Text('Terms', style: TextStyle(color: Color(0xFF94A3B8)))),
              TextButton(onPressed: () => launchUrl(Uri.parse('mailto:support@drowzy.app')), child: const Text('Contact', style: TextStyle(color: Color(0xFF94A3B8)))),
            ],
          ),
          const SizedBox(height: 20),
          const Text('© 2026 Drowzy. All rights reserved.', style: TextStyle(color: Color(0xFF475569), fontSize: 12)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  SUPPORT PAGE
// ═════════════════════════════════════════════════════════════════
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 700;
    final hpad   = mobile ? 24.0 : 80.0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Support'),
        backgroundColor: _bgSection,
        elevation: 0,
        foregroundColor: _textHigh,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: hpad, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionLabel('HELP CENTER'),
            const SizedBox(height: 16),
            const Text(
              'How can we help?',
              style: TextStyle(
                color: _textHigh,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Drowzy is live on Android and finishing up iOS review. Below are answers to '
              'common questions about downloading, getting started, and the iOS waitlist. '
              'For anything else, reach out and we\'ll get back to you within 24 hours.',
              style: TextStyle(color: _textMid, fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _teal.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.mail_outline_rounded, color: _teal, size: 22),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Email support', style: TextStyle(color: _textHigh, fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('We respond within 24 hours on business days.', style: TextStyle(color: _textMid, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _TealButton(
                    label: 'Email Us',
                    onTap: () => launchUrl(Uri.parse('mailto:support@drowzy.app')),
                    paddingH: 18,
                    paddingV: 10,
                    fontSize: 13,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 56),
            const Text('Frequently Asked Questions', style: TextStyle(color: _textHigh, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 28),
            const _FaqItem(
              question: 'Where can I download Drowzy?',
              answer: 'Drowzy for Android is available today on Google Play — search "Drowzy" or use the '
                  'Download on Google Play button anywhere on this page. iPhone users can join the waitlist '
                  'below and we\'ll email you the moment the iOS version is approved.',
            ),
            const _FaqItem(
              question: 'When does the iPhone version launch?',
              answer: 'Drowzy is currently in final App Store review. Waitlist members are notified first, in '
                  'the order they joined — with priority given to anyone who referred friends. Join the '
                  'waitlist above to lock in your spot.',
            ),
            const _FaqItem(
              question: 'How does Drowzy detect drowsiness?',
              answer: 'Drowzy uses your phone\'s front camera to monitor your eyes in real time. '
                  'It measures how long your eyes are closed using the PERCLOS algorithm — '
                  'a scientifically validated method used in driver monitoring research. '
                  'When your eyes remain closed beyond a safe threshold, the alarm fires immediately. '
                  'All processing happens entirely on your device; no video is ever stored or transmitted.',
            ),
            const _FaqItem(
              question: 'Is my camera feed stored or shared?',
              answer: 'No. Drowzy never stores, records, or transmits your camera feed. '
                  'Video frames are processed on your device in real time and discarded '
                  'immediately after analysis. Nothing leaves your phone.',
            ),
            const _FaqItem(
              question: 'Will Drowzy work in the background?',
              answer: 'Drowzy continues monitoring even if you switch briefly to another app or your '
                  'screen dims once a drive session has started. For best results, keep the app in the '
                  'foreground with your screen on and your phone mounted so the front camera has a '
                  'clear view of your face.',
            ),
            const _FaqItem(
              question: 'Do I need an account to use Drowzy?',
              answer: 'No. Guest mode lets you start a drive and receive alerts without signing in, '
                  'with trip history stored locally on your device for up to 3 free drives. Creating a '
                  'free account unlocks cloud backup, cross-device sync, and a 7-day free trial of '
                  'premium features.',
            ),
            const _FaqItem(
              question: 'What does joining the iOS waitlist get me?',
              answer: 'Priority access when we launch on iOS, a founding-member discount on premium '
                  'features, and updates on our progress. If you refer friends using your '
                  'personal referral link, you\'ll move up the queue.',
            ),
            const _FaqItem(
              question: 'How do I delete my account and data?',
              answer: 'You can delete your account directly inside the app: go to '
                  'Profile → scroll down → Delete Account, then type DELETE to confirm. '
                  'All your data — trip history, safety scores, and account information — '
                  'is permanently erased from our servers immediately.',
            ),
            const SizedBox(height: 56),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _bgSection,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              child: Column(
                children: [
                  const Icon(Icons.headset_mic_outlined, color: _teal, size: 36),
                  const SizedBox(height: 16),
                  const Text('Still need help?', style: TextStyle(color: _textHigh, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Send us a message and we\'ll get back to you within 24 hours.', textAlign: TextAlign.center, style: TextStyle(color: _textMid, fontSize: 15, height: 1.5)),
                  const SizedBox(height: 24),
                  _TealButton(
                    label: 'Email support@drowzy.app',
                    onTap: () => launchUrl(Uri.parse('mailto:support@drowzy.app')),
                    paddingH: 24,
                    paddingV: 13,
                    fontSize: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _ctrl;
  late final Animation<double> _expand;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _expand = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _toggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _open ? _bgCard : _bgSection,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _open ? _teal.withOpacity(0.25) : _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(widget.question, style: TextStyle(color: _textHigh, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                      ),
                      const SizedBox(width: 16),
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _open ? _teal : _textLow),
                      ),
                    ],
                  ),
                ),
                SizeTransition(
                  sizeFactor: _expand,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                    child: Text(widget.answer, style: const TextStyle(color: _textMid, fontSize: 14, height: 1.65)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
//  LEGAL PAGES
// ═════════════════════════════════════════════════════════════════
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Privacy Policy'), backgroundColor: _bgSection, elevation: 0, foregroundColor: _textHigh),
      body: const SingleChildScrollView(padding: EdgeInsets.all(24), child: Text(privacyText, style: TextStyle(color: Colors.white70, height: 1.6))),
    );
  }
}

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(title: const Text('Terms of Service'), backgroundColor: _bgSection, elevation: 0, foregroundColor: _textHigh),
      body: const SingleChildScrollView(padding: EdgeInsets.all(24), child: Text(termsText, style: TextStyle(color: Colors.white70, height: 1.6))),
    );
  }
}


const String privacyText = '''
Privacy Policy

Last updated: June 16, 2026

Drowzy ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use the Drowzy website and the Drowzy mobile application (the "App"), available now on Android with iOS coming soon. Please read this policy carefully. If you do not agree with the terms of this Privacy Policy, please do not use our website or App.

1. Information We Collect

We collect minimal information to provide and improve our services:

- Waitlist Information: When you join our iOS waitlist, we collect your email address and generate a referral code associated with your signup. If you were referred by someone, we also store which referral code brought you to the waitlist.
- Account Information: When you create an account, we collect your email address and an encrypted password. We do not collect your name, phone number, or other personal identifiers unless you voluntarily provide them (e.g., in a feedback form).
- Trip Data: The App records your driving sessions, including duration, detected drowsiness events, and a calculated safety score. This data is stored locally on your device in guest mode and synced to our secure cloud database when you sign in.
- Camera Data: The App accesses your device's front camera solely for real‑time face analysis. No video, images, or facial recognition data are ever stored, transmitted, or shared. All processing happens on‑device and is immediately discarded.
- Usage and Analytics: We use Firebase Analytics to collect anonymous usage statistics (e.g., screen views, feature engagement) to improve the App. This information does not identify you personally.
- Purchase Information: When you subscribe, the transaction is processed by Apple (App Store) or Google (Play Store). We receive a receipt token to verify your subscription status; we never see your full credit card details.

2. How We Use Your Information

We use the information we collect to:
- Notify you when Drowzy launches on iOS and manage your position on the waitlist.
- Track referrals so we can honor founding-member perks and queue priority.
- Provide, maintain, and improve the App's drowsiness detection and alert functionality.
- Sync your trip history across devices when you sign in.
- Manage your subscription and free trial.
- Send you essential notifications (e.g., trial expiration reminders, billing issues). You can disable notifications in your device settings.
- Respond to your feedback and support requests.
- Analyze aggregated, anonymized data to enhance safety features.

3. Sharing Your Information

We do not sell, trade, or rent your personal information. We may share data only in the following circumstances:
- With service providers who help us operate our website and App (e.g., Supabase for database hosting, Firebase for analytics). These providers are contractually obligated to protect your data.
- If required by law, to comply with a legal obligation, protect our rights, or investigate fraud.

4. Data Retention and Security

- Waitlist entries are retained until iOS launch and for a reasonable period afterward to honor referral perks, or until you request deletion.
- Account information and trip data are retained as long as your account exists. You may delete your account at any time from the App's Profile screen, which will permanently erase your data from our servers.
- Guest trip data stored locally on your device is deleted when you sign out or uninstall the App.
- We implement industry‑standard security measures (encryption, secure authentication) to protect your information. However, no method of electronic storage is 100% secure.

5. Your Rights

Depending on your location, you may have rights to access, correct, delete, or port your personal data. To exercise these rights, contact us at support@drowzy.app.

6. Children's Privacy

Our website and App are not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13.

7. Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date. Continued use of our website or App after changes constitutes acceptance.

8. Contact Us

If you have questions about this Privacy Policy, contact us at:
support@drowzy.app
''';

const String termsText = '''
Terms of Service

Last updated: June 16, 2026

Welcome to Drowzy! These Terms of Service ("Terms") govern your use of the Drowzy website and the Drowzy mobile application (together, the "Service"), operated by Drowzy ("we," "us," or "our"). By using our website or App, you agree to be bound by these Terms. If you do not agree, do not use the Service.

1. Eligibility

You must be at least 13 years old to use the App or join our iOS waitlist. By using the Service, you represent that you meet this age requirement.

2. Description of Service

Drowzy is available now on Android via Google Play, with an iOS version in final App Store review. This website allows you to download the Android app directly, or join a waitlist for early access to the iOS version. The App provides real‑time drowsiness detection using your device's front camera, analyzing eye closure patterns and alerting you with sound and vibration when signs of fatigue are detected. The App also stores trip history and provides safety scores. Drowzy's drowsiness detection is a driver assistance tool only and does not guarantee accident prevention. You remain fully responsible for your driving decisions and safety.

3. Waitlist

Joining the iOS waitlist does not guarantee access to the App upon launch, a specific launch date, or any specific pricing, though we intend to honor stated founding-member perks and referral priority in good faith. We may modify or discontinue the waitlist program at any time.

4. Account and Guest Use

You may use a limited version of the App as a guest (without an account). Creating a free account unlocks cloud backup, cross‑device sync, and a 7‑day free trial of premium features. You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account.

5. Free Trial and Subscription

- Free Trial: New users may be offered a 7‑day free trial of premium features. The trial begins when you start your first authenticated drive.
- Subscription: After the trial, you may purchase a monthly or annual auto‑renewing subscription to continue unlimited drowsiness detection and premium features.
- Billing: Payment will be charged to your Apple ID or Google Play account upon confirmation of purchase. Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period.
- Cancellation: You can manage or cancel your subscription in your device's account settings. Cancellation takes effect after the current billing period ends. No refunds are provided for unused portions of the subscription period, except as required by law.

6. Acceptable Use

You agree not to:
- Use the App while driving if it causes distraction or violates local traffic laws.
- Modify, reverse‑engineer, or attempt to extract the source code of the App or website.
- Use the Service for any unlawful purpose or in a way that could harm others.
- Attempt to game the referral system through fraudulent signups.

7. Intellectual Property

The Service and all related content, features, and functionality (including but not limited to the Drowzy name, logo, design, and algorithms) are owned by Drowzy and are protected by copyright, trademark, and other intellectual property laws. You may not copy, distribute, or create derivative works without our prior written consent.

8. Disclaimer of Warranties

The Service is provided "as is" and "as available" without warranties of any kind, either express or implied. We do not guarantee that the App will be error‑free, uninterrupted, or that drowsiness detection will be 100% accurate. The App is a driver assistance tool and should not be relied upon as a sole safety measure. Always remain attentive while driving.

9. Limitation of Liability

To the fullest extent permitted by law, Drowzy shall not be liable for any indirect, incidental, special, consequential, or punitive damages, including but not limited to personal injury, property damage, or loss of data, arising from your use of the Service. Our total liability for any claim shall not exceed the amount you paid us for the 12 months preceding the claim.

10. Termination

We may suspend or terminate your access to the Service at any time, without prior notice, if you violate these Terms. Upon termination, your right to use the Service will cease immediately. You may also stop using the Service at any time.

11. Governing Law

These Terms shall be governed by the laws of Nigeria, without regard to conflict of law principles.

12. Changes to Terms

We reserve the right to modify these Terms at any time. We will notify you of significant changes by posting the new Terms on this page and updating the "Last updated" date. Your continued use of the Service after changes constitutes acceptance of the new Terms.

13. Contact

For questions or concerns about these Terms, contact us at:
support@drowzy.app
''';