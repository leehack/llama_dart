// Stub for dart:io on web
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isWindows => false;
}

enum FileMode { read, write, append, writeOnly, writeOnlyAppend }

class File {
  File(String path);
  String get path => '';
  bool existsSync() => false;
  int lengthSync() => 0;
  Future<void> delete() async {}
  void deleteSync() {}
  Future<List<String>> readAsLines() async => [];
  Future<File> create({bool recursive = false}) async => this;
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      RandomAccessFile();
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async => this;
}

class RandomAccessFile {
  Future<void> truncate(int length) async {}
  Future<void> setPosition(int position) async {}
  Future<void> writeFrom(List<int> buffer, [int start = 0, int? end]) async {}
  Future<void> close() async {}
}

class Directory {
  Directory(String path);
  String get path => '';
  bool existsSync() => false;
  void createSync({bool recursive = false}) {}
  Future<void> create({bool recursive = false}) async {}
}
