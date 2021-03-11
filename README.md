![Generic badge](https://img.shields.io/badge/status-draft-red.svg)
[![Actions Status](https://github.com/rtmigo/dart_disk_cache/workflows/unittest/badge.svg?branch=master)](https://github.com/rtmigo/dart_disk_cache/actions)
![Generic badge](https://img.shields.io/badge/tested_on-Windows_|_MacOS_|_Ubuntu-blue.svg)

# disk_cache

`DiskBytesMap` and `DiskBytesCache` are objects for storing binary data in files. They are good for
small chunks of data that easily fit into a `Uint8List`. For example, to cache data from the web or
store user images.

``` dart
final diskBytes = DiskBytesMap(directory);
diskBytes.saveBytesSync('myKey', [0x21, 0x23]); // saved into a file!
Uint8List fromDisk = diskBytes.loadBytesSync('myKey'); 
```

Each item actually stored in a separate file. So there is no central index, that can be broken.
It's just named files.

Even if the OS decides to clear the temporary directories, and deletes half of the files, 
it's not a big deal.

Although each item is contained in a file, this does not impose any restrictions on the keys. 
They can be of any length and can contain any characters.
``` dart
diskBytes.saveBytesSync('C:\\con', ...);  // no problem
diskBytes.saveBytesSync('* :) *', ...);   // no problem
```

## As a Map

Both objects implement `Map<String, List<int>>`. So they can be used like an ordinary `Map`.

``` dart
diskBytes["mykey"] = [1,2,3];
for (var byte in diskBytes["mykey"])
  print("$byte");
print(diskBytes.length);   
```

It is worth remembering that `BytesMap`
and `BytesCache` do not store lists or ints. They just accept `List<int>` as an argument. Each item
of the list will be truncated to a byte.

``` dart
var bytesMap = BytesMap(dir);

diskBytes["a"] = [1, 2, 3];
print(diskBytes["a"]);  // prints [1, 2, 3]

diskBytes["b"] = [0, -1, -2];
print(diskBytes["b"]);  // prints [0, 255, 254]
```





File names are created based on hashes from string keys. This could hypothetically lead to hash
collisions. If, by a rare miracle, the program encounters a collision, it will not affect the cache.

Although both classes inherit from `Map<String, List<int>>`, it is worth remembering that `BytesMap`
and `BytesCache` do not store lists or ints. They just accept `List<int>` as an argument. Each item
of the list will be truncated to a byte.

``` dart
var bytesMap = BytesMap(dir);

bytesMap["a"] = [1, 2, 3];
print(bytesMap["a"]);  // prints [1, 2, 3]

bytesMap["b"] = [0, -1, -2];
print(bytesMap["b"]);  // prints [0, 255, 254]
```

# Example

``` dart
import 'dart:typed_data';
import 'package:disk_cache/disk_cache.dart';
import 'package:path/path.dart' as pathlib;
import 'dart:io';

void main() {
  
  // let's place the cache in the temp directory
  String dirPath = pathlib.join(Directory.systemTemp.path, "myCache");

  // creating the cache
  final diskCache = BytesCache(Directory(dirPath));

  // reading bytes from cache
  Uint8List? myData = diskCache["myKey"];

  print(myData); // on first start it's null

  // saving two bytes
  diskCache["myKey"] = [0x23, 0x21];

  // after restart diskCache["myKey"] will load the data
}
```