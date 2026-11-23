import 'package:chemnote/features/chemistry/data/elements_data.dart';
import 'package:chemnote/features/chemistry/widgets/molar_mass_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Elements Data', () {
    test('contains all 118 IUPAC elements from H (1) to Og (118)', () {
      expect(kChemicalElements.length, 118);
      expect(findElementByNumber(1)?.symbol, 'H');
      expect(findElementByNumber(6)?.symbol, 'C');
      expect(findElementByNumber(79)?.symbol, 'Au');
      expect(findElementByNumber(118)?.symbol, 'Og');
      expect(findElementBySymbol('Fe')?.atomicNumber, 26);
    });
  });

  group('MolarMassCalculator', () {
    test('calculates simple formulas accurately', () {
      final water = MolarMassCalculator.calculate('H2O');
      expect(water.totalMass, closeTo(18.015, 0.02));
      expect(MolarMassCalculator.parseFormula('H2O'), {'H': 2, 'O': 1});

      final h2so4 = MolarMassCalculator.calculate('H2SO4');
      expect(h2so4.totalMass, closeTo(98.08, 0.05));
      expect(MolarMassCalculator.parseFormula('H2SO4'), {'H': 2, 'S': 1, 'O': 4});

      final glucose = MolarMassCalculator.calculate('C6H12O6');
      expect(glucose.totalMass, closeTo(180.16, 0.05));
    });

    test('handles parentheses and nested brackets', () {
      final caoh2 = MolarMassCalculator.parseFormula('Ca(OH)2');
      expect(caoh2, {'Ca': 1, 'O': 2, 'H': 2});
      expect(MolarMassCalculator.calculate('Ca(OH)2').totalMass, closeTo(74.09, 0.05));

      final ferrocyanide = MolarMassCalculator.parseFormula('K4[Fe(CN)6]');
      expect(ferrocyanide, {'K': 4, 'Fe': 1, 'C': 6, 'N': 6});
      expect(
        MolarMassCalculator.calculate('K4[Fe(CN)6]').totalMass,
        closeTo(368.34, 0.1),
      );

      final curly = MolarMassCalculator.parseFormula('Al2{SO4}3');
      expect(curly, {'Al': 2, 'S': 3, 'O': 12});
    });

    test('handles hydrates with ., ·, •, and * separators', () {
      final cuso4Dot = MolarMassCalculator.parseFormula('CuSO4.5H2O');
      expect(cuso4Dot, {'Cu': 1, 'S': 1, 'O': 9, 'H': 10});
      expect(
        MolarMassCalculator.calculate('CuSO4.5H2O').totalMass,
        closeTo(249.68, 0.1),
      );

      final cuso4MidDot = MolarMassCalculator.parseFormula('CuSO4·5H2O');
      expect(cuso4MidDot, cuso4Dot);

      final na2co3Bullet = MolarMassCalculator.parseFormula('Na2CO3•10H2O');
      expect(na2co3Bullet, {'Na': 2, 'C': 1, 'O': 13, 'H': 20});

      final mgso4Star = MolarMassCalculator.parseFormula('MgSO4 * 7 H2O');
      expect(mgso4Star, {'Mg': 1, 'S': 1, 'O': 11, 'H': 14});
    });

    test('computes element percentage breakdown summing to 100%', () {
      final result = MolarMassCalculator.calculate('NaCl');
      final totalPct = result.breakdown.fold<double>(
        0,
        (sum, item) => sum + item.percentage,
      );
      expect(totalPct, closeTo(100.0, 0.01));
      expect(result.formattedSummary, contains('M(NaCl)'));
    });

    test('throws MolarMassException on invalid formulas', () {
      expect(
        () => MolarMassCalculator.calculate(''),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('   '),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('Xx2O3'),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('Ca(OH2'),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('Ca(OH)]2'),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('CuSO4..5H2O'),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('h2o'),
        throwsA(isA<MolarMassException>()),
      );
      expect(
        () => MolarMassCalculator.calculate('Ca()2'),
        throwsA(isA<MolarMassException>()),
      );
    });
  });
}
