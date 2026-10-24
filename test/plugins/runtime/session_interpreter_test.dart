import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_interpreter.dart';

import 'engine_contract.dart';

void main() => engineContractTests(InterpreterEngine.new);
