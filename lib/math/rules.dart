import 'package:geb/math/symbols.dart';

import 'ast.dart';
import 'proof.dart';
import 'state.dart';

abstract class DerivationRegionInfo {
  StepRegionInfo? operator [](int index);
}

class DoubleTildeRule extends Rule {
  const DoubleTildeRule()
      : super._(
            'double tilde',
            "The string '~~' can be deleted from any theorem. "
                "It can also be inserted into any theorem, provided that the "
                "resulting string is itself well formed.");

  @override
  SelectRegion activate(FullState state, DerivationState derivation) {
    // TODO(paul): get rid of the old Proof object once it's not needed
    // anymore.
    return SelectRegion(this, [
      for (var line in derivation.lines)
        DoubleTildePrinter.run(state, derivation, line)
    ]);
  }
}

abstract class FullLineStepRule extends Rule {
  const FullLineStepRule._(String name, String description)
      : super._(name, description);

  @override
  SelectTwoLines activate(FullState state, DerivationState derivation) =>
      SelectTwoLines(computeIsSelectable(derivation.lines), this);

  void apply(DerivationState derivation, Formula x, Formula y);

  String preview(List<Formula> regions);

  List<bool> computeIsSelectable(List<DerivationLine> derivation) =>
      [for (var line in derivation) _isLineSelectable(line)];

  bool _isLineSelectable(DerivationLine line);
}

class JoiningRule extends FullLineStepRule {
  const JoiningRule()
      : super._('joining', 'If x and y are theorems, then <x∧y> is a theorem');

  @override
  void apply(DerivationState derivation, Formula x, Formula y) {
    derivation.join(x, y);
  }

  @override
  String preview(List<Formula> formulas) => [
        '<',
        formulas.length > 0 ? formulas[0] : 'x',
        and,
        formulas.length > 1 ? formulas[1] : 'y',
        '>'
      ].join();

  @override
  bool _isLineSelectable(DerivationLine line) => line is Formula;
}

class PartialLineStepRegionInfo {
  final Formula formula;

  PartialLineStepRegionInfo(this.formula);
}

abstract class Rule {
  final String name;

  final String description;

  const Rule._(this.name, this.description);

  InteractiveState activate(FullState state, DerivationState derivation) {
    throw UnimplementedError(
        '''activateRule doesn't know how to handle the rule "$this"''');
  }

  @override
  String toString() => name;
}

class SeparationRule extends Rule {
  const SeparationRule()
      : super._('separation',
            'If <x∧y> is a theorem, then both x and y are theorems. ');

  List<Formula> apply(PartialLineStepRegionInfo x) => [x.formula];

  List<SubexpressionsStepRegionInfo?> getRegions(
          List<DerivationLine> derivation) =>
      [
        for (int i = 0; i < derivation.length; i++)
          _getRegionsForLine(derivation, i)
      ];

  SubexpressionsStepRegionInfo? _getRegionsForLine(
      List<DerivationLine> derivation, int index) {
    var line = derivation[index];
    if (line is And) {
      return SubexpressionsStepRegionInfo([
        PartialLineStepRegionInfo(line.leftOperand),
        PartialLineStepRegionInfo(line.rightOperand)
      ]);
    }
    return null;
  }
}

abstract class StepRegionInfo {}

class SubexpressionsStepRegionInfo extends StepRegionInfo {
  final List<PartialLineStepRegionInfo> _subexpressions;

  SubexpressionsStepRegionInfo(this._subexpressions);

  Iterable<PartialLineStepRegionInfo> get subexpressions => _subexpressions;
}

class UnimplementedRule extends Rule {
  const UnimplementedRule(String name, String description)
      : super._(name, description);
}
