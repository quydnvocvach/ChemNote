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

    test('balances ionic redox equations with charge conservation', () {
      final permanganate = ChemicalEquationBalancer.balance(
        'MnO4- + Fe2+ + H+ -> Mn2+ + Fe3+ + H2O',
      );
      expect(permanganate.coefficients, [1, 5, 8, 1, 5, 4]);
      expect(permanganate.balanced, 'MnO₄⁻ + 5Fe²⁺ + 8H⁺ → Mn²⁺ + 5Fe³⁺ + 4H₂O');

      final dichromate = ChemicalEquationBalancer.balance(
        'Cr2O7^2- + H+ + Fe2+ -> Cr3+ + Fe3+ + H2O',
      );
      expect(dichromate.coefficients, [1, 14, 6, 2, 6, 7]);
      expect(dichromate.balanced, 'Cr₂O₇²⁻ + 14H⁺ + 6Fe²⁺ → 2Cr³⁺ + 6Fe³⁺ + 7H₂O');

      final oxalate = ChemicalEquationBalancer.balance(
        'MnO4- + C2O4^2- + H+ -> Mn2+ + CO2 + H2O',
      );
      expect(oxalate.coefficients, [2, 5, 16, 2, 10, 8]);
      expect(oxalate.balanced, '2MnO₄⁻ + 5C₂O₄²⁻ + 16H⁺ → 2Mn²⁺ + 10CO₂ + 8H₂O');
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
