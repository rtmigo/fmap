![Generic badge](https://img.shields.io/badge/status-draft-red.svg)
![Generic badge](https://img.shields.io/badge/testing_on-Windows_|_MacOS_|_Ubuntu-blue.svg)


# fmap

А `Map` stored in the file system. Equally suitable for caching and persistent 
storage.

``` dart
Map fmap = Fmap(directory);

fmap['keyA'] = 'my string'; // saved string into a file
fmap['keyB'] = 5;           // saved int into a file
fmap['keyC'] = [23,42,77];  // saved three-bytes blob into a file

print(fmap['keyA']); // read from file
```

The storage is most efficient for storing large objects: blobs and strings. Although it can store small ones like bool and int without any problems.

This object implements `Map`, so it can be used in the same way.

``` dart
Map fmap = Fmap(directory);

print('Count of items: ${fmap.length}');

for (var entry in fmap.entries) {
    print('Item ${entry.name} ${entry.value}'); 
}
```

## Basic types

The storage can store such basic types as `String`, `int`, `double` and `bool`.


They can be read as dynamic types ...

``` dart
var objects = Fmap(directory);
var myJsonString = fmap['json']; // a dynamic type
var myIntValue = fmap['number']; // a dynamic type
```

Or more strictly, limiting to generic arguments:

``` dart
var strings = Fmap<String>(directory);
var myJsonString = strings['json'];  // definitely a string 
var myIntValue = strings['number'];  // OOPS, TypeError
```

## Blobs (binary data)

All values with type derived from `List<int>` are treated as lists of bytes.
This allows you to efficiently save and load **blobs** both in the `Uint8List` 
format and in the more basic `List`. When saving, each `int` will be truncated to 
the range 0..255.

``` dart
var blobs = Fmap<Uint8List>(directory);
blobs['x'] = myBinaryData;
```




## Purge

If the storage has become too large, you can delete the oldest data.

``` dart
// leave only the freshest 16 Mb
fmap.purgeSync(16*1024*1024);
```

The constructor has the `updateTimestampsOnRead` argument. This argument 
determines which elements will be considered fresh at the time of purging.

``` dart
final fmap = Fmap(updateTimestampsOnRead=true);
fmap.purge(...);  // LRU
```

In this case, the elements will be deleted according to the **LRU** policy. 
Items that were accessed recently or added recently will remain in the storage.

However, accounting for usage will require an extra write operation on each read.

``` dart
final fmap = Fmap(updateTimestampsOnRead=false);
fmap.purge(...);  // FIFO
```

In this case, it's a **FIFO**. Items that were added recently will remain in 
the cache.

This is the default mode. This prevents wear to the SSD drives.

