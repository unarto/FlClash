import 'package:fl_clash/core/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OhosDisconnectGate', () {
    test('active generation notifies only once', () {
      final gate = OhosDisconnectGate();

      final generation = gate.beginConnection();

      expect(gate.consumeDisconnect(generation), isTrue);
      expect(gate.consumeDisconnect(generation), isFalse);
    });

    test('stale generation disconnect is ignored after reconnect', () {
      final gate = OhosDisconnectGate();

      final firstGeneration = gate.beginConnection();
      final secondGeneration = gate.beginConnection();

      expect(gate.isActiveConnection(firstGeneration), isFalse);
      expect(gate.isActiveConnection(secondGeneration), isTrue);
      expect(gate.consumeDisconnect(firstGeneration), isFalse);
      expect(gate.consumeDisconnect(secondGeneration), isTrue);
    });

    test('reset clears active generation', () {
      final gate = OhosDisconnectGate();

      final generation = gate.beginConnection();
      gate.reset();

      expect(gate.consumeDisconnect(generation), isFalse);
    });

    test('beginConnection after reset isolates a new connection generation', () {
      final gate = OhosDisconnectGate();

      final firstGeneration = gate.beginConnection();
      gate.reset();
      final secondGeneration = gate.beginConnection();

      expect(secondGeneration, isNot(firstGeneration));
      expect(gate.isActiveConnection(firstGeneration), isFalse);
      expect(gate.isActiveConnection(secondGeneration), isTrue);
      expect(gate.consumeDisconnect(firstGeneration), isFalse);
      expect(gate.consumeDisconnect(secondGeneration), isTrue);
    });
  });
}
