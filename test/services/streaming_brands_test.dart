import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/streaming_brands.dart';

void main() {
  group('matching', () {
    test('case and punctuation do not matter', () {
      expect(StreamingBrand.matching('NETFLIX'), StreamingBrand.netflix);
      expect(StreamingBrand.matching('Disney Plus'), StreamingBrand.disney);
      expect(StreamingBrand.matching('Disney+'), StreamingBrand.disney);
      expect(StreamingBrand.matching('Amazon MGM Studios'), StreamingBrand.prime);
      expect(StreamingBrand.matching('Max'), StreamingBrand.hbo);
    });

    test('a name must match whole', () {
      expect(StreamingBrand.matching('Disney Channel'), isNull);
      expect(StreamingBrand.matching('Paramount Pictures'), isNull);
      expect(StreamingBrand.matching('Netflixx'), isNull);
      expect(StreamingBrand.matching(''), isNull);
    });

    test('"Apple TV+" and "Apple TV" are both Apple', () {
      expect(StreamingBrand.matching('Apple TV+'), StreamingBrand.apple);
      expect(StreamingBrand.matching('Apple TV'), StreamingBrand.apple);
    });

    test('no name stands for two brands', () {
      final seen = <String, StreamingBrand>{};
      for (final brand in StreamingBrand.values) {
        for (final name in brand.names) {
          final key = normalizeBrandName(name);
          expect(seen[key] ?? brand, brand, reason: name);
          seen[key] = brand;
        }
      }
    });
  });

  group('layout', () {
    test('the standard shows the big five, the rest are listed but off', () {
      final layout = BrandRowsLayout.standard;
      expect(layout.visible, [
        StreamingBrand.netflix,
        StreamingBrand.prime,
        StreamingBrand.disney,
        StreamingBrand.hbo,
        StreamingBrand.apple,
      ]);
      expect(layout.order, hasLength(StreamingBrand.values.length));
      expect(layout.isHidden(StreamingBrand.sky), isTrue);
    });

    test('round-trips order and hidden ones', () {
      final layout = BrandRowsLayout.standard
          .withOrder([StreamingBrand.hbo, ...BrandRowsLayout.standard.order.where((b) => b != StreamingBrand.hbo)])
          .withHidden(StreamingBrand.netflix, true)
          .withHidden(StreamingBrand.sky, false);
      final back = BrandRowsLayout.decode(layout.encode());
      expect(back.order, layout.order);
      expect(back.visible.first, StreamingBrand.hbo);
      expect(back.isHidden(StreamingBrand.netflix), isTrue);
      expect(back.isHidden(StreamingBrand.sky), isFalse);
    });

    test('the last one on show cannot be hidden', () {
      var layout = BrandRowsLayout.decode('netflix');
      for (final brand in StreamingBrand.values) {
        layout = layout.withHidden(brand, true);
      }
      expect(layout.visible, hasLength(1));
    });

    test('unknown and repeated entries are dropped, missing brands appended', () {
      final layout = BrandRowsLayout.decode('sky,-netflix,unknown,sky');
      expect(layout.order.first, StreamingBrand.sky);
      expect(layout.isHidden(StreamingBrand.sky), isFalse);
      expect(layout.isHidden(StreamingBrand.netflix), isTrue);
      expect(layout.order.toSet(), StreamingBrand.values.toSet());
      expect(layout.isHidden(StreamingBrand.prime), isFalse, reason: 'appended with its default');
    });
  });
}
