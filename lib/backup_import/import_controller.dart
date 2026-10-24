import 'package:flutter/foundation.dart';
import 'package:kartka/backup_import/backup_importer.dart';
import 'package:kartka/backup_import/backup_planner.dart';
import 'package:kartka/backup_import/import_plan.dart';
import 'package:kartka/backup_import/source_mapper.dart';
import 'package:kartka/backup_import/tachibk_decoder.dart';
import 'package:kartka/platform/file_picker.dart';

/// Decodes and plans a backup synchronously (runs inside an isolate).
ImportPlan planBackupSync(Uint8List bytes) =>
    const BackupPlanner(SourceMapper()).plan(decodeTachibk(bytes));

/// [planBackupSync] off the UI thread (inline on web, which has no isolates).
Future<ImportPlan> planBackup(Uint8List bytes) =>
    compute(planBackupSync, bytes);

/// Where the import screen is.
enum ImportPhase {
  /// Nothing chosen yet.
  idle,

  /// Reading and decoding the file.
  loading,

  /// Dry-run summary is showing.
  preview,

  /// Writing to the repositories.
  importing,

  /// Finished.
  done,

  /// Something went wrong; see [ImportController.error].
  failed,
}

/// State machine behind the "Import SY backup" screen.
class ImportController extends ChangeNotifier {
  /// Creates a controller.
  new({
    required this.picker,
    required this.importer,
    this.planner = planBackup,
  });

  /// File chooser (platform seam).
  final FilePicker picker;

  /// Writes the plan.
  final BackupImporter importer;

  /// Turns file bytes into a plan.
  final Future<ImportPlan> Function(Uint8List bytes) planner;

  ImportPhase _phase = ImportPhase.idle;
  String? _fileName;
  ImportPlan? _plan;
  ImportResult? _result;
  String? _error;
  (int, int) _progress = (0, 0);

  /// Whether AniList/MAL links will be stored.
  bool get bindsTrackers => importer.bindings != null;

  /// Current phase.
  ImportPhase get phase => _phase;

  /// Name of the chosen file.
  String? get fileName => _fileName;

  /// Dry-run plan, once a file was read.
  ImportPlan? get plan => _plan;

  /// What the import wrote.
  ImportResult? get result => _result;

  /// Failure message in [ImportPhase.failed].
  String? get error => _error;

  /// (entries done, entries total) while importing.
  (int, int) get progress => _progress;

  void _go(ImportPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// Back to the start.
  void reset() {
    _plan = null;
    _result = null;
    _error = null;
    _go(ImportPhase.idle);
  }

  /// Lets the user choose a `.tachibk`, then builds the dry-run plan.
  Future<void> pick() async {
    final files = await picker.pickFiles(extensions: const ['tachibk']);
    if (files.isEmpty) return;
    _go(ImportPhase.loading);
    try {
      _fileName = files.first.name;
      _plan = await planner(await files.first.readBytes());
      _result = null;
      _go(ImportPhase.preview);
    } on Object catch (e) {
      _fail(e);
    }
  }

  /// Writes the planned import.
  Future<void> runImport() async {
    final plan = _plan;
    if (plan == null) return;
    _progress = (0, plan.manga.length);
    _go(ImportPhase.importing);
    try {
      _result = await importer.apply(
        plan,
        onProgress: (done, total) {
          _progress = (done, total);
          notifyListeners();
        },
      );
      _go(ImportPhase.done);
    } on Object catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    _error = e is BackupFormatException ? e.message : '$e';
    _go(ImportPhase.failed);
  }
}
