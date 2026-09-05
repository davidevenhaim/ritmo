import 'package:flutter/material.dart';

/// Nocturne design-system tokens (design handoff, `reference/nocturne-styles.css`).
///
/// The handoff ships every value inline because it was a streaming HTML
/// preview; this file is the theme layer it asks for. Screens reference these
/// names, never raw hex. Ramps are OKLCH-generated: 700-900 for tinted fills,
/// 500 as base, 100-300 for text on tints. Never pure black or white.
class Noc {
  Noc._();

  // ---------------------------------------------------------------- colour
  static const bg = Color(0xFF161826);
  static const surface = Color(0xFF232532);

  /// Inner rows and tiles that sit *inside* a surface.
  static const sunken = Color(0xFF292B31);
  static const sheet = Color(0xFF1D1F2C);

  static const text = Color(0xFFE9E9ED);
  static const muted = Color(0xFF9397AB);

  /// Labels, meta, inactive tabs.
  static const dim = Color(0xFF75798C);

  /// Hairline that stands in for elevation.
  static const line = Color(0xFF3F424D);

  /// Divider inside a card. Same value as [sunken] by design.
  static const divider = Color(0xFF292B31);

  static const accent = Color(0xFF9184D9);
  static const accent100 = Color(0xFFF5F4FF);
  static const accent200 = Color(0xFFE7E5FE);
  static const accent300 = Color(0xFFD2CEFD);
  static const accent400 = Color(0xFFB5ABFC);
  static const accent600 = Color(0xFF796CBF);
  static const accent700 = Color(0xFF5D5294);
  static const accent800 = Color(0xFF423A6A);
  static const accent900 = Color(0xFF2B2741);

  static const neutral300 = Color(0xFFCFD3E5);
  static const neutral400 = Color(0xFFB2B6CA);
  static const neutral700 = Color(0xFF595D6C);

  static const scrim = Color(0xBC0F111C);

  // --------------------------------------------------------------- spacing
  /// Dense 0.7x scale.
  static const s1 = 2.8;
  static const s2 = 5.6;
  static const s3 = 8.4;
  static const s4 = 11.2;
  static const s6 = 16.8;
  static const s8 = 22.4;

  /// Screen gutter.
  static const gutter = 18.0;

  // ---------------------------------------------------------------- radius
  static const rSheet = 24.0;
  static const rCard = 16.0;
  static const rCardLg = 18.0;
  static const rRow = 14.0;
  static const rRowSm = 13.0;
  static const rControl = 12.0;
  static const rIcon = 11.0;
  static const rPill = 999.0;

  // ------------------------------------------------------------- elevation
  /// Card: a hairline plus ambient darkness, never stacked shadows.
  static Border get hairline => Border.all(color: line, width: 1);
  static Border get hairlineAccent => Border.all(color: accent800, width: 1);
  static Border get hairlineAccentLift => Border.all(color: accent700, width: 1);

  static BoxDecoration card({Color? color, double radius = rCard, Border? border}) => BoxDecoration(color: color ?? surface, borderRadius: BorderRadius.circular(radius), border: border ?? hairline);

  /// The streak card's ground: a diagonal tint that fades into the sheet.
  static const streakGradient = LinearGradient(begin: Alignment(-0.7, -1), end: Alignment(0.5, 1), colors: [accent900, sheet], stops: [0.0, 0.7]);

  /// Progress fills run 700 -> 500 left to right.
  static const barGradient = LinearGradient(colors: [accent700, accent]);

  // ------------------------------------------------------------------ type
  /// Inter, weights 400/500/600. Headings are 500 only, never bolder;
  /// hierarchy comes from size and space.
  static const _f = 'Inter';

  /// Inter ships as one variable file, so a weight only takes effect when the
  /// `wght` axis is set alongside [FontWeight].
  static const w400 = [FontVariation('wght', 400)];
  static const w500 = [FontVariation('wght', 500)];
  static const w600 = [FontVariation('wght', 600)];

  static const screenTitle = TextStyle(fontFamily: _f, fontSize: 26, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -0.65, color: text, height: 1.1);
  static const pageTitle = TextStyle(fontFamily: _f, fontSize: 23, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -0.5, color: text);
  static const name = TextStyle(fontFamily: _f, fontSize: 19, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -0.38, color: text);
  static const sectionTitle = TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w500, fontVariations: w500, color: text);
  static const planTitle = TextStyle(fontFamily: _f, fontSize: 17, fontWeight: FontWeight.w500, fontVariations: w500, color: text);
  static const cardTitle = TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, fontVariations: w500, color: text);
  static const rowTitle = TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w400, color: text);
  static const body = TextStyle(fontFamily: _f, fontSize: 13, color: text, height: 1.45);
  static const bodyMuted = TextStyle(fontFamily: _f, fontSize: 13, color: muted);
  static const meta = TextStyle(fontFamily: _f, fontSize: 11, color: dim);
  static const metaMuted = TextStyle(fontFamily: _f, fontSize: 11.5, color: muted);
  static const metaDim = TextStyle(fontFamily: _f, fontSize: 11.5, color: dim);
  static const small = TextStyle(fontFamily: _f, fontSize: 10.5, color: dim);
  static const tiny = TextStyle(fontFamily: _f, fontSize: 10, color: dim);

  /// 40px hero numeral (streak).
  static const hero = TextStyle(fontFamily: _f, fontSize: 40, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -1.2, height: 1, color: text);
  static const stat = TextStyle(fontFamily: _f, fontSize: 22, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -0.44, height: 1.1, color: text);
  static const statSm = TextStyle(fontFamily: _f, fontSize: 19, fontWeight: FontWeight.w500, fontVariations: w500, letterSpacing: -0.38, color: text);

  /// Uppercase kicker: 10.5-11px with .10-.12em tracking.
  static const kicker = TextStyle(fontFamily: _f, fontSize: 11, letterSpacing: 1.32, color: dim, fontWeight: FontWeight.w400);
  static const kickerAccent = TextStyle(fontFamily: _f, fontSize: 10.5, letterSpacing: 1.26, color: accent400, fontWeight: FontWeight.w400);

  /// Column labels in a stat strip.
  static const columnLabel = TextStyle(fontFamily: _f, fontSize: 9.5, letterSpacing: 0.76, color: dim);
}

/// A tappable card that lifts its hairline to the accent while pressed —
/// the handoff's hover state, translated to touch.
class NocCard extends StatefulWidget {
  const NocCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.radius = Noc.rCard, this.color, this.border, this.gradient});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final Border? border;
  final Gradient? gradient;

  @override
  State<NocCard> createState() => _NocCardState();
}

class _NocCardState extends State<NocCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.gradient != null ? null : (widget.color ?? Noc.surface),
        gradient: widget.gradient,
        borderRadius: BorderRadius.circular(widget.radius),
        border: _down && widget.onTap != null ? Border.all(color: Noc.accent) : (widget.border ?? Noc.hairline),
      ),
      child: widget.child,
    );
    if (widget.onTap == null) return body;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

/// Primary action: an accent **outline**, never a solid fill. The one
/// intentional accent fill in the system is the Start circle.
class NocButton extends StatelessWidget {
  const NocButton({super.key, required this.label, this.onTap, this.primary = true, this.icon, this.dense = false, this.block = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final IconData? icon;
  final bool dense;

  /// `btn-block`: fills its parent's width with the label centred.
  final bool block;

  @override
  Widget build(BuildContext context) {
    final c = primary ? Noc.accent : Noc.text;
    // `.btn:disabled { opacity: .45 }` in the handoff.
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Noc.rControl),
        hoverColor: c.withValues(alpha: 0.12),
        splashColor: c.withValues(alpha: 0.22),
        child: Container(
          width: block ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: dense ? 11 : 14, vertical: dense ? 7 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Noc.rControl),
            border: Border.all(color: primary ? Noc.accent : Noc.line),
          ),
          child: Row(
            mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: primary ? Noc.accent : Noc.text), const SizedBox(width: 6)],
              // A block button owns its width, so a long label ellipsises
              // rather than overflowing the row it sits in. A min-width button
              // is sized by its label and must not be constrained.
              _label(block),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(bool block) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(fontFamily: 'Inter', fontSize: dense ? 12.5 : 14, color: primary ? Noc.accent : Noc.text),
    );
    return block ? Flexible(child: text) : text;
  }
}

/// 32-36px square icon button on the surface ground.
class NocIconButton extends StatelessWidget {
  const NocIconButton({super.key, required this.icon, this.onTap, this.size = 36, this.outlined = false, this.color, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool outlined;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Noc.rIcon),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: outlined ? null : Noc.surface,
          borderRadius: BorderRadius.circular(Noc.rIcon),
          border: Border.all(color: outlined ? Noc.accent : Noc.line),
        ),
        child: Icon(icon, size: size * 0.47, color: color ?? (outlined ? Noc.accent : Noc.neutral400)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// `tag-accent` / `tag-neutral` / `tag-outline`.
class NocTag extends StatelessWidget {
  const NocTag(this.label, {super.key, this.style = NocTagStyle.accent, this.fontSize = 10});
  final String label;
  final NocTagStyle style;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: switch (style) {
        NocTagStyle.accent => Noc.accent800,
        NocTagStyle.neutral => Noc.line,
        NocTagStyle.outline => null,
      },
      borderRadius: BorderRadius.circular(7),
      border: style == NocTagStyle.outline ? Border.all(color: Noc.accent) : null,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: fontSize,
        color: switch (style) {
          NocTagStyle.accent => Noc.accent100,
          NocTagStyle.neutral => Noc.text,
          NocTagStyle.outline => Noc.accent,
        },
      ),
    ),
  );
}

enum NocTagStyle { accent, neutral, outline }

/// 40 x 24 track, 18px knob. Used for Health and the builder's share rows.
class NocToggle extends StatelessWidget {
  const NocToggle({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 24,
      decoration: BoxDecoration(color: value ? Noc.accent : Noc.line, borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: 3,
            left: value ? 19 : 3,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(color: Noc.text, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Progress bar. Track [Noc.sunken] (or a given colour), fill 700 -> 500.
class NocBar extends StatelessWidget {
  const NocBar({super.key, required this.pct, this.height = 6, this.track});
  final double pct;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height * 0.67),
    child: Container(
      height: height,
      color: track ?? Noc.sunken,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: pct.clamp(0.0, 1.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(gradient: Noc.barGradient, borderRadius: BorderRadius.circular(height * 0.67)),
        ),
      ),
    ),
  );
}

/// The stat ring: 6px track, accent arc, starts at 12 o'clock.
class NocRing extends StatelessWidget {
  const NocRing({super.key, required this.pct, this.size = 56, this.stroke = 6});
  final double pct;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RingPainter(pct.clamp(0.0, 1.0), stroke)),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pct, this.stroke);
  final double pct;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.width - stroke) / 2;
    final track = Paint()
      ..color = Noc.sunken
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = Paint()
      ..color = Noc.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);
    if (pct > 0) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -1.5707963, 6.2831853 * pct, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct || old.stroke != stroke;
}

/// `nfPulse` — opacity .3 <-> .9, used for today's streak dot and the
/// "looping media" marker.
class NocPulse extends StatefulWidget {
  const NocPulse({super.key, required this.child, this.period = const Duration(seconds: 2)});
  final Widget child;
  final Duration period;

  @override
  State<NocPulse> createState() => _NocPulseState();
}

class _NocPulseState extends State<NocPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period)..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.3, end: 0.9).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// `nfIn` — a 12px rise plus fade. Screen enter, sheet body, toast.
class NocIn extends StatelessWidget {
  const NocIn({super.key, required this.child, this.delay = Duration.zero, this.duration = const Duration(milliseconds: 300)});
  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: duration,
    curve: Curves.easeOut,
    builder: (context, t, child) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
    ),
    child: child,
  );
}

/// Section head: a 15px title with an optional right-hand action.
class NocSectionHead extends StatelessWidget {
  const NocSectionHead(this.title, {super.key, this.trailing, this.note, this.onNote});
  final String title;
  final Widget? trailing;
  final String? note;
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Expanded(child: Text(title, style: Noc.sectionTitle)),
      if (note != null)
        GestureDetector(
          onTap: onNote,
          child: Text(note!, style: Noc.metaDim.copyWith(color: onNote == null ? Noc.dim : Noc.accent)),
        ),
      ?trailing,
    ],
  );
}

/// A person, drawn as their emoji on a sunken disc. The app has no photos
/// for other people, so the emoji is the face everywhere friends appear.
class NocFace extends StatelessWidget {
  const NocFace(this.emoji, {super.key, this.size = 34, this.selected = false, this.border});
  final String emoji;
  final double size;
  final bool selected;
  final Color? border;

  /// CanvasKit resolves emoji fallbacks one codepoint at a time, so a ZWJ
  /// sequence like 🧘‍♀️ comes out as two tofu boxes on web. Drawing the base
  /// glyph keeps the same person on every platform.
  static String base(String emoji) {
    final zwj = emoji.indexOf('\u200d');
    return (zwj == -1 ? emoji : emoji.substring(0, zwj)).replaceAll('\ufe0f', '');
  }

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? Noc.accent900 : Noc.surface,
      border: Border.all(color: border ?? (selected ? Noc.accent : Noc.line), width: selected ? 1.4 : 1),
    ),
    child: Text(base(emoji), style: TextStyle(fontSize: size * 0.46)),
  );
}

/// The system toast: accent-900 ground, accent-700 ring, 2.6s.
void nocToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: Noc.accent200),
      ),
      backgroundColor: Noc.accent900,
      duration: const Duration(milliseconds: 2600),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Noc.rRow),
        side: const BorderSide(color: Noc.accent700),
      ),
      elevation: 0,
    ),
  );
}

/// Phosphor regular, the icon set the handoff specifies.
///
/// The `phosphor_flutter` package does not compile against Flutter 3.47 —
/// its `PhosphorIconData extends IconData`, and `IconData` is now a final
/// class — so the font itself is vendored (MIT, `assets/fonts/`) and the
/// glyphs the design uses are declared here. Add a codepoint when a screen
/// needs a new glyph; they are stable across Phosphor releases.
class Nx {
  Nx._();
  static const _f = 'Phosphor';
  static const IconData arrowLeft = IconData(0xe058, fontFamily: _f);
  static const IconData arrowsOutSimple = IconData(0xe0a6, fontFamily: _f);
  static const IconData arrowCounterClockwise = IconData(0xe038, fontFamily: _f);
  static const IconData barbell = IconData(0xe0b6, fontFamily: _f);
  static const IconData camera = IconData(0xe10e, fontFamily: _f);
  static const IconData caretDown = IconData(0xe136, fontFamily: _f);
  static const IconData caretRight = IconData(0xe13a, fontFamily: _f);
  static const IconData check = IconData(0xe182, fontFamily: _f);
  static const IconData clipboardText = IconData(0xe198, fontFamily: _f);
  static const IconData dotsSixVertical = IconData(0xeae2, fontFamily: _f);
  static const IconData fire = IconData(0xe242, fontFamily: _f);
  static const IconData footprints = IconData(0xea88, fontFamily: _f);
  static const IconData gear = IconData(0xe270, fontFamily: _f);
  static const IconData heart = IconData(0xe2a8, fontFamily: _f);
  static const IconData heartbeat = IconData(0xe2ac, fontFamily: _f);
  static const IconData image = IconData(0xe2ca, fontFamily: _f);
  static const IconData listBullets = IconData(0xe2f2, fontFamily: _f);
  static const IconData magnifyingGlass = IconData(0xe30c, fontFamily: _f);
  static const IconData paperPlaneTilt = IconData(0xe398, fontFamily: _f);
  static const IconData play = IconData(0xe3d0, fontFamily: _f);
  static const IconData calendarBlank = IconData(0xe10a, fontFamily: _f);
  static const IconData calendarPlus = IconData(0xe714, fontFamily: _f);
  static const IconData calendarCheck = IconData(0xe712, fontFamily: _f);
  static const IconData clock = IconData(0xe19a, fontFamily: _f);
  static const IconData bell = IconData(0xe0ce, fontFamily: _f);
  static const IconData copySimple = IconData(0xe1cc, fontFamily: _f);
  static const IconData chatCircle = IconData(0xe168, fontFamily: _f);
  static const IconData minus = IconData(0xe32a, fontFamily: _f);
  static const IconData plus = IconData(0xe3d4, fontFamily: _f);
  static const IconData target = IconData(0xe47c, fontFamily: _f);
  static const IconData shieldCheck = IconData(0xe40c, fontFamily: _f);
  static const IconData sparkle = IconData(0xe6a2, fontFamily: _f);
  static const IconData user = IconData(0xe4c2, fontFamily: _f);
  static const IconData userPlus = IconData(0xe4d0, fontFamily: _f);
  static const IconData usersThree = IconData(0xe68e, fontFamily: _f);
  static const IconData x = IconData(0xe4f6, fontFamily: _f);
}

/// The handoff's media placeholder: diagonal stripes with an optional accent
/// bloom. Every striped tile in the design is where looping exercise media
/// goes — this app has real images for most of the catalogue, so [NocMedia]
/// falls back to stripes only when an exercise has none.
class NocStripes extends StatelessWidget {
  const NocStripes({super.key, this.bloom = false, this.dark = false});
  final bool bloom;
  final bool dark;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _StripePainter(bloom: bloom, dark: dark),
    child: const SizedBox.expand(),
  );
}

class _StripePainter extends CustomPainter {
  _StripePainter({required this.bloom, required this.dark});
  final bool bloom;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final a = dark ? const Color(0xFF3F424D) : const Color(0xFF292B31);
    final b = dark ? const Color(0xFF33363F) : const Color(0xFF1F2130);
    final step = dark ? 4.0 : 6.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    final p = Paint()
      ..color = a
      ..strokeWidth = step
      ..style = PaintingStyle.stroke;
    for (var x = -size.height; x < size.width + size.height; x += step * 2) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    if (bloom) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(center: const Alignment(0.6, -0.6), radius: 0.9, colors: [Noc.accent.withValues(alpha: 0.22), Noc.accent.withValues(alpha: 0)]).createShader(Offset.zero & size),
      );
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.bloom != bloom || old.dark != dark;
}

/// `nfSweep` — a gradient bar sliding left to right while the AI drafts.
class NocSweep extends StatefulWidget {
  const NocSweep({super.key, this.height = 4});
  final double height;

  @override
  State<NocSweep> createState() => _NocSweepState();
}

class _NocSweepState extends State<NocSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.height),
    child: SizedBox(
      height: widget.height,
      child: ColoredBox(
        color: Noc.sunken,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => FractionallySizedBox(
            widthFactor: 0.4,
            alignment: Alignment(-1 + 2 * (_c.value * 1.4), 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height),
                gradient: const LinearGradient(colors: [Noc.accent900, Noc.accent, Noc.accent900]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
