import 'package:flutter_test/flutter_test.dart';
import 'package:pandapainterapp/models/svg_asset.dart';

void main() {
  Map<String, dynamic> row({Object? isActive = true}) => {
        'id': '1',
        'name': 'Bird',
        'public_url': 'https://example.com/bird.svg',
        'is_active': isActive,
      };

  group('SvgAsset.fromMap is_active', () {
    test('active row is unlocked', () {
      final asset = SvgAsset.fromMap(row(isActive: true))!;
      expect(asset.isActive, isTrue);
      expect(asset.isLocked, isFalse);
    });

    test('inactive row is locked', () {
      final asset = SvgAsset.fromMap(row(isActive: false))!;
      expect(asset.isActive, isFalse);
      expect(asset.isLocked, isTrue);
    });

    test('missing is_active defaults to active (never silently locks)', () {
      final map = row()..remove('is_active');
      final asset = SvgAsset.fromMap(map)!;
      expect(asset.isActive, isTrue);
      expect(asset.isLocked, isFalse);
    });
  });
}
