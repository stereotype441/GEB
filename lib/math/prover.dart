import 'ast.dart';
import 'kernel.dart';

const ContinuationStrategy detach = const Detach();

const Strategy join = const Join();

const ContinuationStrategy rewrite = const ApplyEverywhere(trivialRewrite);

const ContinuationStrategy separate = const Separate();

const ContinuationStrategy trivialRewrite = const TrivialRewrite();

class ApplyEverywhere extends ContinuationStrategy {
  final ContinuationStrategy strategy;

  const ApplyEverywhere(this.strategy);

  @override
  Theorem? _continueFrom(ProverState state, Theorem theorem, Formula goal) {
    if (theorem.formula == goal) return theorem;
    var result = strategy._continueFrom(state, theorem, goal);
    if (result != null) {
      assert(result.formula == goal);
      return result;
    }
    Theorem Function(Theorem) continuation;
    if (theorem.formula is Or && goal is Or) {
      theorem = switcheroo(theorem)!;
      goal = switcheroo(assume(null, goal))!.formula;
      continuation = (theorem) => reverseSwitcheroo(theorem)!;
    } else {
      continuation = (theorem) => theorem;
    }
    var formula = theorem.formula;
    if (formula is Implies && goal is Implies) {
      // Given <P1->Q1>, form <P2->Q2> as follows:
      //   [         push fantasy
      //     P2      premise
      //     P1      recursion
      //     Q1      detachment
      //     Q2      recursion
      //   ]         pop fantasy
      //   <P2->Q2>  conclusion
      var p1Formula = formula.leftOperand;
      var q1Formula = formula.rightOperand;
      var p2Formula = goal.leftOperand;
      var q2Formula = goal.rightOperand;
      var p2 = assume(theorem.assumptions, p2Formula);
      var nestedState = ProverState.nest(state, p2);
      var p1 = _continueFrom(nestedState, p2, p1Formula);
      if (p1 == null) return null;
      assert(p1.formula == p1Formula);
      var q1 = detachment(p1, carryOver(p2.assumptions!, theorem)!)!;
      assert(q1.formula == q1Formula);
      var q2 = _continueFrom(nestedState, q1, q2Formula);
      if (q2 == null) return null;
      assert(q2.formula == q2Formula);
      var result = popFantasy(q2)!;
      return continuation(result);
    } else if (formula is And && goal is And) {
      // Given <P1&Q1>, form <P2&Q2> as follows:
      //   P1       separation
      //   P2       recursion
      //   Q1       separation
      //   Q2       recursion
      //   <P2&Q2>  joining
      var p1Formula = formula.leftOperand;
      var q1Formula = formula.rightOperand;
      var p2Formula = goal.leftOperand;
      var q2Formula = goal.rightOperand;
      var p1 = separation(theorem, Side.left)!;
      assert(p1.formula == p1Formula);
      var p2 = _continueFrom(state, p1, p2Formula);
      if (p2 == null) return null;
      assert(p2.formula == p2Formula);
      var q1 = separation(theorem, Side.right)!;
      assert(q1.formula == q1Formula);
      var q2 = _continueFrom(state, q1, q2Formula);
      if (q2 == null) return null;
      assert(q2.formula == q2Formula);
      var result = joining(p2, q2)!;
      return continuation(result);
    }
    return fail('rewrite', 'no rule to rewrite $formula to $goal');
  }
}

class BoundContinuationStrategy extends BoundStrategy {
  final ContinuationStrategy strategy;
  final Formula goal;

  BoundContinuationStrategy._(this.strategy, this.goal);

  @override
  void run(ProverState state) {
    for (int i = 0; i < state._theorems.length; i++) {
      var result = strategy._continueFrom(state, state._theorems[i], goal);
      if (result != null) {
        state.addTheorem(result);
        if (result.formula == goal) return;
      }
    }
  }
}

abstract class BoundStrategy {
  const BoundStrategy();

  void run(ProverState state);

  Strategy then(Strategy strategy) => _SequenceStrategy(this, strategy);
}

abstract class ContinuationStrategy extends Strategy {
  const ContinuationStrategy();

  BoundContinuationStrategy to(Formula goal) =>
      BoundContinuationStrategy._(this, goal);

  Theorem? _continueFrom(ProverState state, Theorem theorem, Formula goal);
}

class Detach extends ContinuationStrategy {
  const Detach();

  @override
  Theorem? _continueFrom(ProverState state, Theorem theorem, Formula goal) {
    for (var implication in state._theorems) {
      var result = detachment(theorem, implication);
      if (result != null && result.formula == goal) return result;
    }
    return null;
  }
}

class Fantasy extends Strategy {
  final Strategy strategy;

  const Fantasy({this.strategy = const NullStrategy()});

  @override
  BoundStrategy to(Formula goal) => _BoundFantasy(strategy, goal);
}

class Join extends Strategy {
  const Join();

  @override
  BoundStrategy to(Formula goal) => _BoundJoin(goal);
}

class NullStrategy extends Strategy {
  const NullStrategy();

  @override
  BoundStrategy to(Formula goal) => const _BoundNullStrategy();
}

class ProverState {
  final Map<Formula, Theorem> _formulaToTheorem = {};

  final List<Theorem> _theorems = [];

  final Assumption? assumptions;

  final Set<String> requiredInsight;

  ProverState()
      : assumptions = null,
        requiredInsight = {};

  ProverState.nest(ProverState outerState, Theorem premise)
      : assumptions = premise.assumptions,
        requiredInsight = outerState.requiredInsight {
    addTheorem(premise);
    for (var theorem in outerState._theorems) {
      addTheorem(carryOver(premise.assumptions!, theorem)!);
    }
  }

  void addTheorem(Theorem theorem) {
    if (!identical(theorem.assumptions, assumptions)) {
      throw 'assumptions mismatch';
    }
    var previousTheorem = _formulaToTheorem[theorem.formula];
    if (previousTheorem == null) {
      _formulaToTheorem[theorem.formula] ??= theorem;
      _theorems.add(theorem);
    }
  }

  Theorem? getTheorem(Formula formula) => _formulaToTheorem[formula];
}

class Separate extends ContinuationStrategy {
  const Separate();

  @override
  Theorem? _continueFrom(ProverState state, Theorem theorem, Formula goal) {
    var result = separation(theorem, Side.left);
    if (result != null && result.formula == goal) return result;
    result = separation(theorem, Side.right);
    if (result != null && result.formula == goal) return result;
    return null;
  }
}

abstract class Strategy {
  const Strategy();

  BoundStrategy to(Formula goal);
}

class TrivialRewrite extends ContinuationStrategy {
  const TrivialRewrite();

  @override
  Theorem? _continueFrom(ProverState state, Theorem theorem, Formula goal) {
    const rules = [
      switcheroo,
      reverseSwitcheroo,
      contrapositive,
      reverseContrapositive,
      deMorgan,
      reverseDeMorgan,
    ];
    for (var rule in rules) {
      var result = rule(theorem);
      if (result != null && result.formula == goal) return result;
    }
    return null;
  }
}

class _BoundFantasy extends BoundStrategy {
  final Strategy strategy;

  final Formula goal;

  _BoundFantasy(this.strategy, this.goal);

  @override
  void run(ProverState state) {
    var goal = this.goal;
    if (goal is! Implies) return;
    var premise = assume(state.assumptions, goal.leftOperand);
    var nestedState = ProverState.nest(state, premise);
    strategy.to(goal.rightOperand).run(nestedState);
    var conclusion = nestedState.getTheorem(goal.rightOperand);
    if (conclusion != null) {
      state.addTheorem(popFantasy(conclusion)!);
    }
  }
}

class _BoundJoin extends BoundStrategy {
  final Formula goal;

  _BoundJoin(this.goal);

  @override
  void run(ProverState state) {
    var goal = this.goal;
    if (goal is! And) return null;
    var x = state.getTheorem(goal.leftOperand);
    if (x == null) return null;
    var y = state.getTheorem(goal.rightOperand);
    if (y == null) return null;
    var theorem = joining(x, y);
    if (theorem == null) return null;
    state.addTheorem(theorem);
  }
}

class _BoundNullStrategy extends BoundStrategy {
  const _BoundNullStrategy();

  @override
  void run(ProverState state) {}
}

class _BoundSequenceStrategy extends BoundStrategy {
  final BoundStrategy first;
  final BoundStrategy second;

  _BoundSequenceStrategy(this.first, this.second);

  @override
  void run(ProverState state) {
    first.run(state);
    second.run(state);
  }
}

class _SequenceStrategy extends Strategy {
  final BoundStrategy first;
  final Strategy second;

  _SequenceStrategy(this.first, this.second);

  @override
  BoundStrategy to(Formula goal) =>
      _BoundSequenceStrategy(first, second.to(goal));
}
