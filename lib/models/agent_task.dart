/// Model for a background sub-agent task.
library;

import 'package:flutter/foundation.dart';

enum AgentTaskStatus { pending, running, completed, error }

class AgentTask extends ChangeNotifier {
  final String id;
  final String instruction;
  final List<String> inputFiles;
  AgentTaskStatus _status = AgentTaskStatus.pending;
  String _result = '';
  String? _error;
  final List<String> _steps = [];
  final List<String> _generatedFiles = [];
  int _currentStep = 0;
  int maxSteps;

  AgentTask({
    required this.id,
    required this.instruction,
    this.inputFiles = const [],
    this.maxSteps = 25,
  });

  AgentTaskStatus get status => _status;
  String get result => _result;
  String? get error => _error;
  List<String> get steps => List.unmodifiable(_steps);
  List<String> get generatedFiles => List.unmodifiable(_generatedFiles);
  int get currentStep => _currentStep;

  void setRunning() {
    _status = AgentTaskStatus.running;
    notifyListeners();
  }

  void addStep(String description) {
    _currentStep++;
    _steps.add(description);
    notifyListeners();
  }

  void addGeneratedFile(String path) {
    _generatedFiles.add(path);
    notifyListeners();
  }

  void complete(String resultText) {
    _result = resultText;
    _status = AgentTaskStatus.completed;
    notifyListeners();
  }

  void fail(String errorText) {
    _error = errorText;
    _status = AgentTaskStatus.error;
    notifyListeners();
  }
}
