// SPDX-FileCopyrightText: (c) 2020 Art Galkin <ortemeo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as paths;

const _DEBUG_LOGGING = false;

extension DateTimeCmp on DateTime {
  bool isBeforeOrSame(DateTime b) => this.isBefore(b) || this.isAtSameMomentAs(b);
  bool isAfterOrSame(DateTime b) => this.isAfter(b) || this.isAtSameMomentAs(b);
}

typedef DeleteFile(File file);

const JS_MAX_SAFE_INTEGER = 9007199254740991;

class FileAndStat {
  FileAndStat(this.file) {
    if (!this.file.isAbsolute) throw ArgumentError.value(this.file);
  }

  final File file;

  FileStat get stat {
    if (_stat == null) _stat = file.statSync();
    return _stat!;
  }

  set stat(FileStat x) {
    this._stat = x;
  }

  FileStat? _stat;

  static void sortByLastModifiedDesc(List<FileAndStat> files) {
    if (files.length >= 2) {
      files.sort((FileAndStat a, FileAndStat b) => -a.stat.modified.compareTo(b.stat.modified));
      assert(files[0].stat.modified.isAfterOrSame(files[1].stat.modified));
    }
  }

  static int sumSize(Iterable<FileAndStat> files) {
    return files.fold(0, (prev, curr) => prev + curr.stat.size);
  }

  static void _deleteOldest(List<FileAndStat> files,
      {int maxSumSize = JS_MAX_SAFE_INTEGER,
      int maxCount = JS_MAX_SAFE_INTEGER,
      DeleteFile? deleteFile}) {
    //

    files = files.toList();

    FileAndStat.sortByLastModifiedDesc(files); // now they are sorted by time
    int sumSize = FileAndStat.sumSize(files);

    if (_DEBUG_LOGGING)
      {
        print("ALL THE FILE LMTS");
        for (var f in files)
          print("- "+f.file.lastModifiedSync().toString());
      }

    DateTime? prevLastModified;

    //iterating files from old to new
    for (int i = files.length - 1;
        i >= 0 && (sumSize > maxSumSize || files.length > maxCount);
        --i) {

      var item = files[i];
      // assert that the files are sorted from old to new
      assert(prevLastModified == null || item.stat.modified.isAfterOrSame(prevLastModified));
      if (_DEBUG_LOGGING)
        print("Deleting file ${item.file.path} LMT ${item.file.lastModifiedSync()}");

      if (deleteFile != null)
        deleteFile(item.file);
      else
        item.file.deleteSync();

      files.removeAt(i);
      assert(files.length == i);
      sumSize -= item.stat.size;
    }
  }
}

void writeKeyAndDataSync(File targetFile, String key, List<int> data) {
  RandomAccessFile raf = targetFile.openSync(mode: FileMode.write);

  try {
    final keyAsBytes = utf8.encode(key);

    // сохраняю номер версии
    raf.writeFromSync([1]);

    // сохраняю длину ключа
    final keyLenByteData = ByteData(2);
    keyLenByteData.setInt16(0, keyAsBytes.length);
    raf.writeFromSync(keyLenByteData.buffer.asInt8List());

    // сохраняю ключ
    raf.writeFromSync(keyAsBytes);

    // сохраняю данные
    raf.writeFromSync(data);
  } finally {
    raf.closeSync();
  }
}

Uint8List? readIfKeyMatchSync(File file, String key) {
  RandomAccessFile raf = file.openSync(mode: FileMode.read);

  try {
    final versionNum = raf.readSync(1)[0];
    if (versionNum > 1) throw Exception("Unsupported version"); // todo custom exceptions

    final keyBytesLen = ByteData.sublistView(raf.readSync(2)).getInt16(0);

    final keyAsBytes = raf.readSync(keyBytesLen); // utf8.encode(key);
    final keyFromFile = utf8.decode(keyAsBytes);

    if (keyFromFile != key)
      return null;

    final bytes = <int>[];
    const CHUNK_SIZE = 128 * 1024;

    while (true) {
      final chunk = raf.readSync(CHUNK_SIZE);
      bytes.addAll(chunk);
      if (chunk.length < CHUNK_SIZE) break;
    }

    return Uint8List.fromList(bytes);
  } finally {
    raf.closeSync();
  }
}

String readKeySync(File file) {
  RandomAccessFile raf = file.openSync(mode: FileMode.read);
  try {
    final versionNum = raf.readSync(1)[0];
    if (versionNum > 1)
      throw Exception("Unsupported version");
    final keyBytesLen = ByteData.sublistView(raf.readSync(2)).getInt16(0);
    final keyAsBytes = raf.readSync(keyBytesLen); // utf8.encode(key);
    return utf8.decode(keyAsBytes);
  } finally {
    raf.closeSync();
  }
}

String stringToMd5(String data) {
  var content = new Utf8Encoder().convert(data);
  var md5 = crypto.md5;
  var digest = md5.convert(content);
  return hex.encode(digest.bytes);
}

typedef String KeyToHash(String s);

bool isDirectoryNotEmptyException(FileSystemException e)
{
  // https://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html
  if (Platform.isLinux && e.osError?.errorCode == 39)
    return true;

  // there is no evident source of macOS errors in 2021 O_O
  if (Platform.isMacOS && e.osError?.errorCode == 66)
    return true;

  return false;
}

void deleteDirIfEmptySync(Directory d) {
  try {
    d.deleteSync(recursive: false);
  } on FileSystemException catch (e) {

    if (!isDirectoryNotEmptyException(e))
      print("WARNING: Got unexpected osError.errorCode=${e.osError?.errorCode} "
            "trying to remove directory.");
  }
}

bool deleteSyncCalm(File file) {
  try {
    file.deleteSync();
    return true;
  } on FileSystemException catch (e) {
    print("WARNING: Failed to delete $file: $e");
    return false;
  }
}

/// A cache that provides to access [Uint8List] binary items by [String] keys.
class DiskCache {

  DiskCache(this.directory, {this.keyToHash = stringToMd5, this.asyncTimestamps = true}) {
    this._initialized = this._init();
  }

  final bool asyncTimestamps;

  /// The data will be stored in directories, whose names are generated by [keyToHash(key)].
  /// By default [keyToHash] is MD5 function, which is great.
  final KeyToHash keyToHash;
    // to be honest, user does not need this. It's here for testing.
    // By setting this callback to a something much worse than MD5, we can prepare ourselves
    // for hash collisions than happen once in a decade

  static const _DIRTY_SUFFIX = ".dirt";
  static const _DATA_SUFFIX = ".dat";

  Future<DiskCache> _init() async {
    directory.createSync(recursive: true);
    this.compactSync();

    return this;
  }

  void compactSync(
      {final int maxSizeBytes = JS_MAX_SAFE_INTEGER, final maxCount = JS_MAX_SAFE_INTEGER}) {
    List<FileAndStat> files = <FileAndStat>[];

    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(recursive: true);
    } on FileSystemException catch (e) {
      throw FileSystemException(
          "DiskCache failed to listSync directory $directory right after creation. "
          "osError: ${e.osError}.");
    }

    for (final entry in entries) {
      if (entry.path.endsWith(_DIRTY_SUFFIX)) {
        deleteSyncCalm(File(entry.path));
        continue;
      }
      if (entry.path.endsWith(_DATA_SUFFIX)) {
        final f = File(entry.path);
        files.add(FileAndStat(f));
      }
    }

    FileAndStat._deleteOldest(files, maxSumSize: maxSizeBytes, maxCount: maxCount,
        deleteFile: (file) {
      deleteSyncCalm(file);
      deleteDirIfEmptySync(file.parent);
    });
  }

  Future<DiskCache> get initialized => this._initialized!;

  Future<DiskCache>? _initialized;
  final Directory directory;

  Future<bool> delete(String key) async {
    await this._initialized;
    final file = this._findExistingFile(key);
    if (file==null)
      return false;

    assert(file.path.endsWith(_DATA_SUFFIX));
    file.deleteSync();
    deleteDirIfEmptySync(file.parent);
    return true;
  }

  Future<File> writeBytes(String key, List<int> data) async {
    //final cacheFile = _fnToCacheFile(filename);

    await this._initialized;
    final cacheFile = this._findExistingFile(key) ?? this._proposeUniqueFile(key);

    File? dirtyFile = _uniqueDirtyFn();
    try {
      writeKeyAndDataSync(dirtyFile, key, data); //# dirtyFile.writeAsBytes(data);

      try {
        Directory(paths.dirname(cacheFile.path)).createSync();
      } on FileSystemException {}
      //print("Writing to $cacheFile");

      if (cacheFile.existsSync()) cacheFile.deleteSync();
      dirtyFile.renameSync(cacheFile.path);
      dirtyFile = null;
    } finally {
      if (dirtyFile != null && dirtyFile.existsSync()) dirtyFile.delete();
    }

    return cacheFile;
  }

  /// Returns the target directory path for a file that holds the data for [key].
  /// The directory may exist or not.
  ///
  /// Each directory corresponds to a hash value. Due to hash collision different keys
  /// may produce the same hash. Files with the same hash will be placed in the same
  /// directory.
  Directory _keyToHypotheticalDir(String key) {
    String hash = this.keyToHash(key);
    assert(!hash.contains(paths.style.context.separator));
    return Directory(paths.join(this.directory.path, hash));
  }

  /// Returns all existing files whose key-hashes are the same as the hash of [key].
  /// Any of them may be the file that is currently storing the data for [key].
  /// It's also possible, that neither of them stores the data for [key].
  Iterable<File> _keyToExistingFiles(String key) sync* {
    // возвращает существующие файлы, в которых _возможно_ хранится значение key
    final kd = this._keyToHypotheticalDir(key);

    List<FileSystemEntity> files;

    if (kd.existsSync()) {
      files = kd.listSync();
      for (final entity in files) {
        if (entity.path.endsWith(_DATA_SUFFIX)) yield File(entity.path);
      }
    }
  }

  /// Generates a unique filename in a directory that should contain file [key].
  File _proposeUniqueFile(String key) {
    final dirPath = _keyToHypotheticalDir(key).path;
    for (int i = 0;; ++i) {
      final candidateFile = File(paths.join(dirPath, "$i$_DATA_SUFFIX"));
      if (!candidateFile.existsSync()) return candidateFile;
    }
  }

  /// Tries to find a file for the [key]. If file does not exist, returns `null`.
  File? _findExistingFile(String key) {
    for (final existingFile in this._keyToExistingFiles(key)) {
      if (readKeySync(existingFile) == key) return existingFile;
    }
    return null;
  }

  Future<Uint8List?> readBytes(String key) async {
    await this._initialized;

    for (final fileCandidate in _keyToExistingFiles(key)) {
      //print("Reading $fileCandidate");
      final data = readIfKeyMatchSync(fileCandidate, key);
      if (data != null) {
        if (this.asyncTimestamps) // todo юниттест таймстампов
          _setTimestampToNow(fileCandidate);
        else
          await _setTimestampToNow(fileCandidate);

        return data;
      }
    }

    return null;
  }

  Future<void> _setTimestampToNow(File file) async {
    // since the cache is located in a temporary directory,
    // any file there can be deleted at any time
    try {
      file.setLastModifiedSync(DateTime.now());
    } on FileSystemException catch (e, _) {
      print("WARNING: Cannot set timestamp to file $file: $e");
    }
  }

  File _uniqueDirtyFn() {
    for (int i = 0;; ++i) {
      final f = File(directory.path + "/$i$_DIRTY_SUFFIX");
      if (!f.existsSync()) return f;
    }
  }
}
