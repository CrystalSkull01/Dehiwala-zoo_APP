import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/gamification_profile.dart';

abstract interface class GamificationStorageService {
  Future<GamificationProfile> loadProfile();

  Future<void> saveProfile(GamificationProfile profile);
}

class FileGamificationStorageService implements GamificationStorageService {
  final Directory? rootDirectory;

  const FileGamificationStorageService({this.rootDirectory});

  Future<File> _profileFile() async {
    final directory = rootDirectory ?? await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(
      '${directory.path}${Platform.pathSeparator}wildlife_progress.json',
    );
  }

  @override
  Future<GamificationProfile> loadProfile() async {
    final file = await _profileFile();
    if (!await file.exists()) return GamificationProfile.empty();
    final decoded = jsonDecode(await file.readAsString());
    return GamificationProfile.fromJson(
      Map<String, dynamic>.from(decoded as Map),
    );
  }

  @override
  Future<void> saveProfile(GamificationProfile profile) async {
    final file = await _profileFile();
    final temporaryFile = File('${file.path}.tmp');
    await temporaryFile.writeAsString(
      jsonEncode(profile.toJson()),
      flush: true,
    );
    await temporaryFile.rename(file.path);
  }
}
