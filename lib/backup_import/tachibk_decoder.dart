import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'backup_models.dart';
import 'proto_reader.dart';

/// Thrown when the file is not a readable `.tachibk`.
class BackupFormatException implements Exception {
  /// Creates the exception.
  const BackupFormatException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Decodes a `.tachibk` (gzip + protobuf) or its already-inflated protobuf.
BackupData decodeTachibk(Uint8List bytes) {
  try {
    final gzipped = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    final raw = gzipped
        ? Uint8List.fromList(GZipDecoder().decodeBytes(bytes))
        : bytes;
    return _readBackup(ProtoReader(raw));
  } on BackupFormatException {
    rethrow;
  } on Object catch (e) {
    throw BackupFormatException('Not a valid TachiyomiSY backup: $e');
  }
}

BackupData _readBackup(ProtoReader r) {
  final manga = <BackupManga>[];
  final categories = <BackupCategory>[];
  final sources = <BackupSource>[];
  while (r.next()) {
    switch (r.field) {
      case 1:
        manga.add(_readManga(r.message()));
      case 2:
        categories.add(_readCategory(r.message()));
      case 101:
        sources.add(_readSource(r.message()));
      default:
        r.skip();
    }
  }
  return BackupData(manga: manga, categories: categories, sources: sources);
}

BackupSource _readSource(ProtoReader r) {
  var name = '';
  var id = '0';
  while (r.next()) {
    switch (r.field) {
      case 1:
        name = r.string();
      case 2:
        id = r.varintBig().toString();
      default:
        r.skip();
    }
  }
  return BackupSource(name, id);
}

BackupCategory _readCategory(ProtoReader r) {
  final c = BackupCategory();
  while (r.next()) {
    switch (r.field) {
      case 1:
        c.name = r.string();
      case 2:
        c.order = r.varint();
      case 3:
        c.id = r.varint();
      default:
        r.skip();
    }
  }
  return c;
}

BackupManga _readManga(ProtoReader r) {
  final m = BackupManga();
  while (r.next()) {
    switch (r.field) {
      case 1:
        m.sourceId = r.varintBig().toString();
      case 2:
        m.url = r.string();
      case 3:
        m.title = r.string();
      case 5:
        m.author = r.string();
      case 7:
        m.genres.add(r.string());
      case 8:
        m.status = r.varint();
      case 9:
        m.thumbnailUrl = r.string();
      case 13:
        m.dateAdded = r.varint();
      case 16:
        m.chapters.add(_readChapter(r.message()));
      case 17:
        r.readInts(m.categories);
      case 18:
        m.tracking.add(_readTracking(r.message()));
      case 100:
        m.favorite = r.boolean();
      case 104:
        m.history.add(_readHistory(r.message()));
      case 106:
        m.lastModifiedAt = r.varint();
      // SY extras.
      case 600:
        m.mergedReferences.add(_readMerged(r.message()));
      case 601:
        m.hasFlatMetadata = true;
        r.skip();
      case 602:
        m.customStatus = r.varint();
      case 603:
        m.customThumbnailUrl = r.string();
      case 800:
        m.customTitle = r.string();
      default:
        r.skip();
    }
  }
  return m;
}

BackupChapter _readChapter(ProtoReader r) {
  final c = BackupChapter();
  while (r.next()) {
    switch (r.field) {
      case 1:
        c.url = r.string();
      case 2:
        c.name = r.string();
      case 4:
        c.read = r.boolean();
      case 6:
        c.lastPageRead = r.varint();
      case 9:
        c.number = r.float32();
      case 10:
        c.sourceOrder = r.varint();
      default:
        r.skip();
    }
  }
  return c;
}

BackupTracking _readTracking(ProtoReader r) {
  final t = BackupTracking();
  var legacyId = '0';
  var modernId = '0';
  while (r.next()) {
    switch (r.field) {
      case 1:
        t.syncId = r.varint();
      case 3:
        legacyId = r.varintBig().toString();
      case 4:
        t.trackingUrl = r.string();
      case 5:
        t.title = r.string();
      case 6:
        t.lastChapterRead = r.float32();
      case 100:
        modernId = r.varintBig().toString();
      default:
        r.skip();
    }
  }
  // Field 100 supersedes the deprecated 32-bit field 3.
  t.mediaId = modernId != '0' ? modernId : legacyId;
  return t;
}

BackupHistory _readHistory(ProtoReader r) {
  final h = BackupHistory();
  while (r.next()) {
    switch (r.field) {
      case 1:
        h.url = r.string();
      case 2:
        h.lastRead = r.varint();
      default:
        r.skip();
    }
  }
  return h;
}

BackupMergedReference _readMerged(ProtoReader r) {
  final m = BackupMergedReference();
  while (r.next()) {
    switch (r.field) {
      case 1:
        m.isInfoManga = r.boolean();
      case 7:
        m.mangaUrl = r.string();
      case 8:
        m.mangaSourceId = r.varintBig().toString();
      default:
        r.skip();
    }
  }
  return m;
}
