import 'package:flutter_test/flutter_test.dart';
import 'package:starlight/domain/entities/wled_config.dart';

void main() {
  group('WledConfig.validateHost', () {
    test('accepts valid IPv4 addresses', () {
      expect(WledConfig.validateHost('192.168.1.42'), isNull);
      expect(WledConfig.validateHost('10.0.0.1'), isNull);
      expect(WledConfig.validateHost('0.0.0.0'), isNull);
      expect(WledConfig.validateHost('255.255.255.255'), isNull);
    });

    test('rejects IPv4 with octet above 255', () {
      expect(WledConfig.validateHost('192.168.1.999'), isNotNull);
      expect(WledConfig.validateHost('256.0.0.1'), isNotNull);
    });

    test('accepts RFC 1123 hostnames', () {
      expect(WledConfig.validateHost('wled'), isNull);
      expect(WledConfig.validateHost('wled.lan'), isNull);
      expect(WledConfig.validateHost('strip-01.local'), isNull);
      expect(WledConfig.validateHost('My-Host.Example.COM'), isNull);
    });

    test('rejects empty, whitespace and URL-shaped input', () {
      expect(WledConfig.validateHost(''), isNotNull);
      expect(WledConfig.validateHost('   '), isNotNull);
      expect(WledConfig.validateHost('http://wled.local'), isNotNull);
      expect(WledConfig.validateHost('wled.local/json'), isNotNull);
      expect(WledConfig.validateHost('192.168.1.42?ON=1'), isNotNull);
      expect(WledConfig.validateHost('has space'), isNotNull);
    });

    test('rejects malformed hostnames', () {
      expect(WledConfig.validateHost('-leading-hyphen'), isNotNull);
      expect(WledConfig.validateHost('trailing-hyphen-'), isNotNull);
      expect(WledConfig.validateHost('bad_label'), isNotNull);
      expect(WledConfig.validateHost('a..b'), isNotNull);
    });

    test('accepts IPv6 literals, bracketed or bare', () {
      expect(WledConfig.validateHost('fe80::1'), isNull);
      expect(WledConfig.validateHost('[fe80::1]'), isNull);
      expect(WledConfig.validateHost('::1'), isNull);
    });
  });

  group('WledConfig.validate', () {
    test('accepts valid port and timeout', () {
      expect(
        WledConfig.validate(host: 'wled', port: 80, timeoutSeconds: 5),
        isNull,
      );
      expect(
        WledConfig.validate(host: 'wled', port: 65535, timeoutSeconds: 60),
        isNull,
      );
    });

    test('rejects out-of-range port', () {
      expect(
        WledConfig.validate(host: 'wled', port: 0, timeoutSeconds: 5),
        isNotNull,
      );
      expect(
        WledConfig.validate(host: 'wled', port: 65536, timeoutSeconds: 5),
        isNotNull,
      );
    });

    test('rejects out-of-range timeout', () {
      expect(
        WledConfig.validate(host: 'wled', port: 80, timeoutSeconds: 0),
        isNotNull,
      );
      expect(
        WledConfig.validate(host: 'wled', port: 80, timeoutSeconds: 61),
        isNotNull,
      );
    });

    test('rejects invalid host', () {
      expect(
        WledConfig.validate(host: 'no spaces', port: 80, timeoutSeconds: 5),
        isNotNull,
      );
    });
  });

  group('WledConfig serialization', () {
    test('round-trips through toMap/fromMap', () {
      const config = WledConfig(
        host: '192.168.1.42',
        port: 8080,
        useHttps: true,
        timeoutSeconds: 10,
      );
      final restored = WledConfig.fromMap(config.toMap());
      expect(restored, config);
    });

    test('fromMap falls back to defaults for missing keys', () {
      final config = WledConfig.fromMap({'host': 'wled'});
      expect(config.host, 'wled');
      expect(config.port, 80);
      expect(config.useHttps, false);
      expect(config.timeoutSeconds, 5);
    });
  });
}
