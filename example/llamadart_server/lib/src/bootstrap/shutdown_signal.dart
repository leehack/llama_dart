import 'dart:async';
import 'dart:io';

/// Waits until SIGINT or SIGTERM is received.
Future<void> waitForShutdownSignal() {
  final completer = Completer<void>();

  late final StreamSubscription<ProcessSignal> sigIntSub;
  late final StreamSubscription<ProcessSignal> sigTermSub;

  void completeIfNeeded() {
    if (completer.isCompleted) {
      return;
    }

    completer.complete();
    sigIntSub.cancel();
    sigTermSub.cancel();
  }

  sigIntSub = ProcessSignal.sigint.watch().listen((_) => completeIfNeeded());
  sigTermSub = ProcessSignal.sigterm.watch().listen((_) => completeIfNeeded());

  return completer.future;
}
