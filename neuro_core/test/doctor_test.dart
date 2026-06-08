import 'package:test/test.dart';

class Doctor {
  final String name;
  Doctor(this.name);

}

void main() {
  test('doctor name stored correctly', () 
  {
    final doctor=Doctor('Pikija');
    expect(doctor.name, 'Pikija');
  }
  );
}