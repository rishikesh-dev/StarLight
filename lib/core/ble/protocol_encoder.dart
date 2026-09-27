import 'dart:typed_data';
import '../utils/color_conversion.dart';

/// Protocol encoder for the MR Star BLE LED controller.
///
/// All packets begin with 0xBC and end with 0x55.
/// This class encapsulates every known command from the decompiled APK.
///
/// Source files inspected:
/// - `sources/e2/e.java` (method B for HSV conversion)
/// - `sources/e1/d.java` (brightness)
/// - `sources/com/findn/ui/fragment/AdjustFragment.java` (power, color)
/// - `sources/f1/d.java` (visualizer color)
/// - `sources/MicroPhoneFragment.java` (mic mode, sensitivity)
/// - `sources/ModeFragment.java` (speed)
/// - `sources/TimerFragment.java` (timer)
/// - `sources/MainActivity.java` (LED count, line order)
/// - `sources/e1/c.java` (color picker up)
/// - `sources/com/addisonelliott/segmentedbutton/SegmentedButtonGroup.java` (mic toggle)
class ProtocolEncoder {
  /// Start byte for every packet.
  static const int startByte = 0xBC;

  /// End byte for every packet.
  static const int endByte = 0x55;

  /// Command: Power control.
  static const int cmdPower = 0x01;

  /// Command: Color / HSV.
  static const int cmdColor = 0x04;

  /// Command: Brightness.
  static const int cmdBrightness = 0x05;

  /// Command: Visualizer color.
  static const int cmdVisualizerColor = 0x09;

  /// Command: LED strip order.
  static const int cmdLineOrder = 0x02;

  /// Command: LED point count.
  static const int cmdLedPoint = 0x03;

  /// Command: Speed.
  static const int cmdSpeed = 0x08;

  /// Command: Microphone sensitivity.
  static const int cmdMicSensitivity = 0x12;

  /// Command: Microphone mode.
  static const int cmdMicMode = 0x11;

  /// Command: Microphone toggle.
  static const int cmdMicToggle = 0x0F;

  /// Command: Color picker state.
  static const int cmdPicker = 0x07;

  /// Subcommand for power.
  static const int subPower = 0x01;

  /// Subcommand for color.
  static const int subColor = 0x06;

  /// Subcommand for brightness.
  static const int subBrightness = 0x06;

  /// Subcommand for LED point.
  static const int subLedPoint = 0x02;

  /// Subcommands.
  static const int subLineOrder = 0x01;
  static const int subSpeed = 0x01;
  static const int subMicSensitivity = 0x01;
  static const int subMicMode = 0x01;
  static const int subMicToggle = 0x01;
  static const int subPicker = 0x01;

  /// Encodes a 16-bit integer as big-endian (most-significant byte first),
  /// matching `(byte)(value / 256), (byte)(value % 256)` in Java.
  static List<int> _encode16BE(int value) {
    return [(value >> 8) & 0xFF, value & 0xFF];
  }

  /// Encodes an 8-bit value to unsigned.
  static int _toUnsignedByte(int value) => value & 0xFF;

  /// --- Core Commands ---

  /// Power ON: `BC 01 01 00 55`
  static Uint8List powerOn() {
    return Uint8List.fromList([startByte, cmdPower, subPower, 0x00, endByte]);
  }

  /// Power OFF: `BC 01 01 01 55`
  static Uint8List powerOff() {
    return Uint8List.fromList([startByte, cmdPower, subPower, 0x01, endByte]);
  }

  /// Set color using HSV values derived from RGB via the APK's e.B() function.
  ///
  /// Packet: `BC 04 06 VH VL SH SL 00 00 55`
  ///
  /// Where:
  /// - VH VL = value1 (hue, 0-360) as 16-bit big-endian
  /// - SH SL = value2 (saturation * 1000, 0-1000) as 16-bit big-endian
  ///
  /// The RGB-to-HSV conversion matches Android's `Color.RGBToHSV` with the
  /// additional saturation fix from `e2.e.B()`.
  static Uint8List colorFromRGB(int red, int green, int blue) {
    final (value1, value2) =
        ColorConversion.computeColorValues(red, green, blue);
    return colorFromHSV(value1, value2);
  }

  /// Set color using already-computed HSV values.
  ///
  /// value1 is hue (0-360), value2 is saturation*1000 (0-1000).
  static Uint8List colorFromHSV(int value1, int value2) {
    final parts = _encode16BE(value1);
    final parts2 = _encode16BE(value2);
    return Uint8List.fromList([
      startByte,
      cmdColor,
      subColor,
      parts[0],
      parts[1],
      parts2[0],
      parts2[1],
      0x00,
      0x00,
      endByte,
    ]);
  }

  /// Set brightness.
  ///
  /// Packet: `BC 05 06 PH PL 00 00 00 00 55`
  ///
  /// Where:
  /// - PH PL = progress (0-1000) as 16-bit big-endian
  /// - Minimum value is clamped to 3 (matching e1/d.java and e1/h.java)
  static Uint8List brightness(int progress) {
    int p = progress;
    if (p < 3) {
      p = 3;
    }
    final parts = _encode16BE(p);
    return Uint8List.fromList([
      startByte,
      cmdBrightness,
      subBrightness,
      parts[0],
      parts[1],
      0x00,
      0x00,
      0x00,
      0x00,
      endByte,
    ]);
  }

  /// --- Additional Commands ---

  /// Command: Mode / Effect selection.
  /// This command exists in the APK but the value-to-name mapping is NOT verified.
  /// The APK has 117 modes (cmode1..cmode117) resolved at runtime.
  /// Use with caution - only for testing/development.
  static const int cmdMode = 0x06;
  static const int subMode = 0x02;

  /// Set LED strip pixel/point count.
  ///
  /// Packet: `BC 03 02 PH PL 55` (6 bytes)
  static Uint8List setLedCount(int count) {
    final parts = _encode16BE(count);
    return Uint8List.fromList([
      startByte,
      cmdLedPoint,
      subLedPoint,
      parts[0],
      parts[1],
      endByte,
    ]);
  }

  /// Set line order (segment order).
  ///
  /// Packet: `BC 02 01 [order] 55`
  static Uint8List setLineOrder(int order) {
    return Uint8List.fromList([
      startByte,
      cmdLineOrder,
      subLineOrder,
      _toUnsignedByte(order),
      endByte,
    ]);
  }

  /// Set mode speed.
  ///
  /// Packet: `BC 08 01 [speed] 55`
  static Uint8List setSpeed(int speed) {
    return Uint8List.fromList([
      startByte,
      cmdSpeed,
      subSpeed,
      _toUnsignedByte(speed),
      endByte,
    ]);
  }

  /// Set mode/effect.
  ///
  /// Packet: `BC 06 02 [id/255] [id%255] 55`
  ///
  /// WARNING: The mode value-to-name mapping is NOT verified.
  /// The APK has 117 modes (cmode1..cmode117) resolved at runtime.
  /// This method is provided for testing/development only.
  static Uint8List setMode(int modeId) {
    if (modeId < 0) modeId = 0;
    return Uint8List.fromList([
      startByte,
      cmdMode,
      subMode,
      _toUnsignedByte(modeId ~/ 255),
      _toUnsignedByte(modeId % 255),
      endByte,
    ]);
  }

  /// Set microphone sensitivity.
  ///
  /// Packet: `BC 12 01 [sensitivity] 55`
  static Uint8List setMicSensitivity(int sensitivity) {
    return Uint8List.fromList([
      startByte,
      cmdMicSensitivity,
      subMicSensitivity,
      _toUnsignedByte(sensitivity),
      endByte,
    ]);
  }

  /// Set microphone mode.
  ///
  /// Packet: `BC 11 01 [mode] 55`
  static Uint8List setMicMode(int mode) {
    return Uint8List.fromList([
      startByte,
      cmdMicMode,
      subMicMode,
      _toUnsignedByte(mode),
      endByte,
    ]);
  }

  /// Toggle microphone on/off.
  ///
  /// Packet: `BC 0F 01 [0|1] 55`
  static Uint8List micToggle(bool on) {
    return Uint8List.fromList([
      startByte,
      cmdMicToggle,
      subMicToggle,
      on ? 0x01 : 0x00,
      endByte,
    ]);
  }

  /// Set color picker state.
  ///
  /// Packet: `BC 07 01 [0|1] 55`
  static Uint8List setColorPicker(bool up) {
    return Uint8List.fromList([
      startByte,
      cmdPicker,
      subPicker,
      up ? 0x01 : 0x00,
      endByte,
    ]);
  }
}
