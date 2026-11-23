import 'package:chemnote/features/chemistry/widgets/equation_balancer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChemicalEquationBalancer', () {
    test('balances simple synthesis and combustion reactions', () {
      final feOx = ChemicalEquationBalancer.balance('Fe + O2 -> Fe3O4');
      expect(feOx.coefficients, [3, 2, 1]);
      expect(feOx.arrow, '→');
      expect(feOx.plain, '3Fe + 2O2 -> Fe3O4');
      expect(feOx.balanced, '3Fe + 2O₂ → Fe₃O₄');

      final propane = ChemicalEquationBalancer.balance('C3H8 + O2 -> CO2 + H2O');
      expect(propane.coefficients, [1, 5, 3, 4]);
    });

    test('balances complex redox and bracketed equations accurately', () {
      final kmno4 = ChemicalEquationBalancer.balance(
        'KMnO4 + HCl -> KCl + MnCl2 + Cl2 + H2O',
      );
      expect(kmno4.coefficients, [2, 16, 2, 2, 5, 8]);

      final caoh = ChemicalEquationBalancer.balance(
        'Ca(OH)2 + H3PO4 -> Ca3(PO4)2 + H2O',
      );
      expect(caoh.coefficients, [3, 2, 1, 6]);
    });

    test('preserves equilibrium arrows and supports Unicode subscripts', () {
      final haber = ChemicalEquationBalancer.balance('N₂ + H₂ ⇌ NH₃');
      expect(haber.coefficients, [1, 3, 2]);
      expect(haber.arrow, '⇌');
      expect(haber.balanced, 'N₂ + 3H₂ ⇌ 2NH₃');

      final eqAscii = ChemicalEquationBalancer.balance('SO2 + O2 <=> SO3');
      expect(eqAscii.coefficients, [2, 1, 2]);
      expect(eqAscii.arrow, '⇌');
    });

    test('formats subscripts while keeping hydrate coefficients intact', () {
      expect(
        ChemicalEquationBalancer.formatFormulaSubscripts('CuSO4.5H2O'),
        'CuSO₄·5H₂O',
      );
      expect(
        ChemicalEquationBalancer.formatFormulaSubscripts('Fe3O4'),
        'Fe₃O₄',
      );
    });

    test('throws EquationBalanceException on invalid inputs', () {
      expect(
        () => ChemicalEquationBalancer.balance(''),
        throwsA(isA<EquationBalanceException>()),
      );
      expect(
        () => ChemicalEquationBalancer.balance('H2 + O2'),
        throwsA(isA<EquationBalanceException>()),
      );
      expect(
        () => ChemicalEquationBalancer.balance('Fe + O2 -> CuO'),
        throwsA(isA<EquationBalanceException>()),
      );
    });
  });
}
