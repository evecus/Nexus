/// Shared value objects for local media files.

class VideoFile {
  final String path;
  final String name;
  final int size;
  const VideoFile(this.path, this.name, this.size);
}

class MusicFile {
  final String path;
  final String name;
  final int size;
  const MusicFile(this.path, this.name, this.size);
}

const videoExtensions = {
  '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv',
  '.ts', '.m2ts', '.mpg', '.mpeg', '.webm', '.rmvb',
  '.rm', '.3gp', '.m4v',
};

const musicExtensions = {
  '.mp3', '.flac', '.aac', '.ogg', '.opus',
  '.wav', '.m4a', '.wma', '.ape',
};
