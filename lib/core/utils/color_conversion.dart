
import 'app_logger.dart';

/// Color conversion matching the exact algorithm from the decompiled MR Star APK.
///
/// Source: `sources/e2/e.java` method `B(int r, int g, int b)`:
///
/// ```java
/// public static float[] B(int i4, int i5, int i6) {
///     float[] fArr = new float[3];
///     Color.RGBToHSV(i4, i5, i6, fArr);
///     if (fArr[1] > 1.0f || (fArr[0] == 0.0f && fArr[1] == 0.0f)) {
///         fArr[1] = 1.0f;
///     }
///     return fArr;
/// }
/// ```
///
/// This converts RGB to HSV using Android's `Color.RGBToHSV`, then forces
/// saturation to 1.0f if it exceeds 1.0 (floating-point rounding) or if
/// both hue and saturation are 0 (grayscale/black colors).
class ColorConversion {
  /// Converts RGB (0-255 per channel) to HSV matching Android's Color.RGBToHSV.
  ///
  /// Returns a 3-element list: [hue (0-360), saturation (0-1), value (0-1)].
  static List<double> rgbToHsv(int red, int green, int blue) {
    final r = _clamp(red) / 255.0;
    final g = _clamp(green) / 255.0;
    final b = _clamp(blue) / 255.0;

    final max = _max3(r, g, b);
    final min = _min3(r, g, b);
    final delta = max - min;

    double hue;
    if (delta < 1e-7) {
      hue = 0.0;
    } else {
      if (max == r) {
        hue = ((g - b) / delta) % 6.0;
      } else if (max == g) {
        hue = (b - r) / delta + 2.0;
      } else {
        hue = (r - g) / delta + 4.0;
      }
      hue *= 60.0;
      if (hue < 0) {
        hue += 360.0;
      }
    }

    double saturation;
    if (max < 1e-7) {
      saturation = 0.0;
    } else {
      saturation = delta / max;
    }

    final value = max;

    final hsv = [hue, saturation, value];

    if (hsv[1] > 1.0 || (hsv[0] == 0.0 && hsv[1] == 0.0)) {
      hsv[1] = 1.0;
    }

    return hsv;
  }

  /// Computes value1 (hue) and value2 (saturation*1000) exactly as the APK does.
  ///
  /// ```java
  /// float[] B = e.B(r, g, b);
  /// int value1 = (int) B[0];         // hue, truncated to int
  /// int value2 = (int)(B[1] * 1000); // saturation*1000, truncated to int
  /// ```
  static (int value1, int value2) computeColorValues(int red, int green, int blue) {
    final hsv = rgbToHsv(red, green, blue);
    final value1 = hsv[0].toInt();
    final value2 = (hsv[1] * 1000.0).toInt();
    AppLog.debug(
      'colorConversion: rgb($red,$green,$blue) → hsv('
      '${hsv[0].toStringAsFixed(1)}, '
      '${hsv[1].toStringAsFixed(3)}, '
      '${hsv[2].toStringAsFixed(3)}) → '
      'values($value1,$value2)',
    );
    return (value1, value2);
  }

  static int _clamp(int v) => v.clamp(0, 255);
  static double _max3(double a, double b, double c) =>
      a >= b ? (a >= c ? a : c) : (b >= c ? b : c);
  static double _min3(double a, double b, double c) =>
      a <= b ? (a <= c ? a : c) : (b <= c ? b : c);
}
