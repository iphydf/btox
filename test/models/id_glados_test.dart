import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:glados/glados.dart';

void main() {
  group('Id', () {
    Glados(any.int).test('Id equality and hashCode', (value) {
      final id1 = Id<Contacts>(value);
      final id2 = Id<Contacts>(value);
      final id3 = Id<Profiles>(value);

      expect(id1, id2);
      expect(id1.hashCode, id2.hashCode);

      expect(id1, isNot(id3));
    });

    Glados(any.int).test('Id.toString', (value) {
      expect(Id<Contacts>(value).toString(), 'Id<Contacts>($value)');
    });
  });

  group('IdConverter', () {
    const converter = IdConverter<Contacts>();

    Glados(any.int).test('IdConverter round-trip', (value) {
      final id = Id<Contacts>(value);
      expect(converter.fromSql(converter.toSql(id)), id);
      expect(converter.fromJson(converter.toJson(id)), id);
    });
  });
}
