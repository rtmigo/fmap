// SPDX-FileCopyrightText: (c) 2020 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:disk_cache/disk_cache.dart';
import 'package:disk_cache/src/81_bytes_fmap.dart';
import "package:test/test.dart";
import 'package:xrandom/xrandom.dart';
import 'package:disk_cache/src/10_readwrite_v3.dart';

import 'helper.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    deleteTempDir(tempDir);
  });

  Future performRandomWritesAndDeletions(BytesFmap cache) async {
    cache.keyToHash = badHashFunc;
    await populate(cache);

    // we will perform 3000 actions in 3 seconds in async manner
    const ACTIONS = 3000;
    const MAX_DELAY = 3000;

    final random = Drandom();
    const UNIQUE_KEYS_COUNT = 50;

    List<Future> futures = [];
    final keys = <String>[];

    final typesOfActionsPerformed = Set<int>();
    int maxKeysCountEver = 0;

    // TODO purge
    // TODO compare to Map

    for (int i = 0; i < ACTIONS; ++i) {
      futures.add(Future.delayed(Duration(milliseconds: random.nextInt(MAX_DELAY))).then((_) {
        // after the random delay perform a random action

        if (keys.length > maxKeysCountEver) maxKeysCountEver = keys.length;

        int act = random.nextInt(3);
        typesOfActionsPerformed.add(act);
        switch (act) {
          case 0: // add a key
            final newKey = random.nextInt(UNIQUE_KEYS_COUNT).toRadixString(16);
            keys.add(newKey);
            cache.writeBytesSync(newKey, TypedBlob(0, List.filled(random.nextInt(2048), 42)));
            break;
          case 1: // remove previously added key
            if (keys.length > 0) {
              final randomOldKey = keys.removeAt(random.nextInt(keys.length));
              cache.deleteSync(randomOldKey);
            }
            break;
          case 2: // read a value
            if (keys.length > 0) {
              final randomKey = keys[random.nextInt(keys.length)];
              cache[randomKey];
            }
            break;
          default:
            throw FallThroughError();
        }
      }));
    }

    await Future.wait(futures);
    //print(typesOfActionsPerformed);
    assert(typesOfActionsPerformed.length == 3);
    assert(maxKeysCountEver > 5);
  }

  test("Random stress", () async {
    await performRandomWritesAndDeletions(BytesFmap(tempDir));
  });
}
