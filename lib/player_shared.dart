/// Public API of the player_shared package.
/// All three apps import this single file.
library player_shared;

// Storage
export 'src/storage/storage_service.dart';

// Models
export 'src/parser/m3u_parser.dart';
export 'src/player/media_file.dart';

// Controllers / settings
export 'src/controller/settings_controller.dart';
export 'src/controller/playback_bar_controller.dart';

// Player core mixins & backend abstraction
export 'src/player/player_core.dart';
export 'src/player/player_backend.dart';
export 'src/player/mpv_backend.dart';

// Music metadata & models
export 'src/music/audio_metadata.dart';
export 'src/music/rich_music_file.dart';
export 'src/music/song_entry.dart';
export 'src/music/artist_splitter.dart';

// Local media scanning (phone & TV shared)
export 'src/scanner/local_scanner.dart';

// Permission handling (phone & TV shared)
export 'src/permission/permission_util.dart';

// Media cache: video thumbnails on disk (phone & TV shared)
export 'src/media_cache/app_data_dir.dart';
export 'src/media_cache/video_thumbnail_generator.dart';

// Music cover art: in-memory, incremental-batch loading (all three apps
// share this strategy now — audio covers are never written to disk).
export 'src/media_cache/audio_cover_memory_cache.dart';
