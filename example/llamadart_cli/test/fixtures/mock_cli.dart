import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('style', defaultsTo: 'llama')
    ..addFlag('mismatch', defaultsTo: false);
  final result = parser.parse(arguments);

  final style = result['style'] as String;
  final mismatch = result['mismatch'] as bool;

  if (style == 'dart') {
    stdout.writeln('== llamadart-cli ==');
    stdout.writeln('mode    : interactive');
    stdout.writeln('Loaded model: fixture.gguf');
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final prompt = line.trim();
    if (prompt.isEmpty) {
      continue;
    }
    if (prompt == 'exit' || prompt == '/exit') {
      break;
    }

    final response = mismatch && prompt == 'beta'
        ? 'answer:DIFF:$prompt'
        : 'answer:$prompt';

    if (style == 'dart') {
      stdout.writeln('assistant> $response');
    } else {
      stdout.writeln(response);
    }
  }
}
