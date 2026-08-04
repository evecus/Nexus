# strip_vlc_plugins.ps1
#
# Run after `flutter build windows` to remove VLC runtime plugins that
# IPTV / local-video playback does not need. Shrinks plugins/ from ~80MB
# to ~15MB.
#
# Usage (from windows):
#   powershell -ExecutionPolicy Bypass -File scripts\strip_vlc_plugins.ps1
#
# Looks for the VLC plugins folder under the Release directory. If vlc_player
# changes its packaging location in the future, the script recursively
# searches Release for any plugins folder that contains *_plugin.dll.

$ErrorActionPreference = 'Stop'

# 1. Locate the Release directory
$releaseDir = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
  $releaseDir = Join-Path $PSScriptRoot '..\..\..\build\windows\x64\runner\Release'
}
if (-not (Test-Path $releaseDir)) {
  Write-Error ("Release directory not found: {0}. Run 'flutter build windows' first." -f $releaseDir)
  exit 1
}
$releaseDir = (Resolve-Path $releaseDir).Path
Write-Host ("Release directory: {0}" -f $releaseDir)

# 2. Recursively find plugins folders (vlc_player may use vlc\plugins or plugins)
$pluginDirs = Get-ChildItem -Path $releaseDir -Recurse -Directory -Filter 'plugins' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match 'vlc' -or (Test-Path (Join-Path $_.FullName '..\libvlc.dll')) }

if ($pluginDirs.Count -eq 0) {
  # Fallback: any plugins folder that contains *_plugin.dll
  $pluginDirs = Get-ChildItem -Path $releaseDir -Recurse -Directory -Filter 'plugins' -ErrorAction SilentlyContinue |
    Where-Object { (Get-ChildItem $_.FullName -Filter '*_plugin.dll' -ErrorAction SilentlyContinue).Count -gt 0 }
}

if ($pluginDirs.Count -eq 0) {
  Write-Host "No VLC plugins directory found. VLC runtime may not be bundled in this build. Skipping."
  exit 0
}

# 3. Plugin whitelist for IPTV / local-video playback (file name, no path).
#    IMPORTANT: names below were verified against an actual `flutter build
#    windows` output (media_kit / libvlc packaging), not guessed. Several
#    entries in the previous version of this list did not match real file
#    names (e.g. 'libaccess_http_plugin' vs the real 'libhttp_plugin') and
#    were silently dropped by the -notcontains check below, which is why
#    playback broke after stripping. If you upgrade media_kit / the VLC
#    runtime version, re-verify this list against the new build output
#    rather than editing by memory: run a full (unstripped) build and diff
#    plugin file names before touching this array.
#
#    access:      network and file access (HTTP/HTTPS/RTSP/RTMP/UDP/TCP/local file)
#    access_output: needed only for outbound streaming (sout); not needed for
#                 pure playback, kept minimal/empty here.
#    demux:       container demuxing (TS/HLS/FLV/MP4/MKV/AVI + FFmpeg fallback)
#    codec:       decoding (avcodec via FFmpeg covers H.264/H.265/AAC/MP3/AC3 etc.)
#    video_chroma:pixel format conversion between decoder output and the vout
#                 (required — without a matching chroma converter the vout
#                 cannot consume the decoded frame, which can also present as
#                 a black screen even when direct3d/vmem plugins are present)
#    video_output:Windows video output AND the window/surface providers the
#                 vout modules depend on to get something to draw into.
#                 libvmem_plugin is what texture/memory-callback based
#                 integrations (e.g. media_kit's texture rendering) use to
#                 pull decoded frames — dropping it removes the entire video
#                 path for that rendering mode while audio keeps working,
#                 which matches "vlc plays, screen is black".
#    audio_output:Windows audio output (DirectSound/WASAPI/MMDevice)
#    video_filter:deinterlacing etc.
#    misc/logger: core plumbing referenced by the above chain
$keep = @(
  # access / filesystem / network
  'libfilesystem_plugin',
  'libhttp_plugin',
  'libhttps_plugin',
  'libtcp_plugin',
  'libudp_plugin',
  'liblive555_plugin',        # RTSP
  'libaccess_concat_plugin',
  'libaccess_realrtsp_plugin',
  'libaccess_imem_plugin',
  'libimem_plugin',
  # demux
  'libts_plugin',
  'libadaptive_plugin',        # HLS(.m3u8)/DASH/Smooth Streaming — this VLC
                                # build has no standalone libhls_plugin, HLS
                                # support lives entirely in libadaptive_plugin.
                                # Missing this = IPTV .m3u8 sources black screen
                                # even though local files play fine.
  'libasf_plugin',            # WMV/ASF
  'libavi_plugin',
  'libes_plugin',              # elementary streams (raw H.264 etc.)
  'libmkv_plugin',
  'libmp4_plugin',
  'libogg_plugin',
  'libps_plugin',               # MPEG-PS
  'librawdv_plugin',
  'librawvid_plugin',
  'libwav_plugin',
  # codec
  'libavcodec_plugin',        # FFmpeg, covers most video/audio codecs (H.264/H.265/AAC/MP3 etc via avcodec)
  'liba52_plugin',             # AC3
  'libdca_plugin',             # DTS
  'libflac_plugin',
  'libvorbis_plugin',
  'libopus_plugin',
  'libadpcm_plugin',
  'libaraw_plugin',
  'libsubsusf_plugin',
  # packetizer: repackages raw elementary streams pulled out of a TS/PS
  # container (e.g. IPTV live streams) into a format the codec plugins can
  # decode. Not needed by most local MP4/MKV files (already packaged), but
  # required for live TS streams — missing this produces exactly "connects,
  # demuxes, but no picture" while local video plays fine.
  'libpacketizer_h264_plugin',
  'libpacketizer_hevc_plugin',
  'libpacketizer_mpeg4audio_plugin',
  'libpacketizer_mpegaudio_plugin',
  'libpacketizer_mpegvideo_plugin',
  'libpacketizer_copy_plugin',
  'libpacketizer_a52_plugin',
  'libpacketizer_dts_plugin',
  # video_chroma (decoder output -> vout pixel format conversion; required)
  'libswscale_plugin',
  'libi420_rgb_plugin',
  'libi420_yuy2_plugin',
  'libi422_yuy2_plugin',
  'libi422_i420_plugin',
  'libyuvp_plugin',
  'libchain_plugin',
  # video_output: renderers + the window/surface providers they depend on
  'libdirect3d11_plugin',
  'libdirect3d9_plugin',
  'libdirectdraw_plugin',
  'libwgl_plugin',
  'libgl_plugin',
  'libglwin32_plugin',        # win32 window/surface creation for gl/wgl vouts
  'libwingdi_plugin',
  'libvmem_plugin',           # memory/texture-callback video output — required
                               # by texture-backed embedding (e.g. media_kit)
  'libwinhibit_plugin',       # prevent screen sleep during playback
  # d3d filter helpers that ride alongside the d3d11/d3d9 vouts
  'libdirect3d11_filters_plugin',
  'libdirect3d9_filters_plugin',
  # audio_output (Windows)
  'libdirectsound_plugin',
  'libwasapi_plugin',
  'libmmdevice_plugin',
  # audio_mixer / audio_filter (format conversion / resampling / mixing, required)
  'libaudio_format_plugin',
  'libfloat_mixer_plugin',
  'libsimple_channel_mixer_plugin',
  'libspatializer_plugin',
  'libugly_resampler_plugin',
  'libscaletempo_plugin',     # tempo change preserving pitch
  # video_filter
  'libdeinterlace_plugin',
  # subtitles / OSD (local video may have subtitles)
  'libfreetype_plugin',
  # misc / logger / keystore (core plumbing)
  'liblogger_plugin',
  'libstats_plugin',
  'libaudioscrobbler_plugin',
  'libmemory_keystore_plugin'
)

# 4. Walk each plugins directory and delete any _plugin.dll not in the whitelist
$totalRemoved = 0
$totalBytesSaved = 0
foreach ($dir in $pluginDirs) {
  $dirPath = $dir.FullName
  Write-Host ""
  Write-Host ("Processing: {0}" -f $dirPath)
  $allPlugins = Get-ChildItem -Path $dirPath -Recurse -Filter '*_plugin.dll' -ErrorAction SilentlyContinue
  $beforeSize = ($allPlugins | Measure-Object -Property Length -Sum).Sum
  Write-Host ("  Total plugins: {0}  Total size: {1:N1} MB" -f $allPlugins.Count, ($beforeSize / 1MB))

  foreach ($p in $allPlugins) {
    if ($keep -notcontains $p.BaseName) {
      $sz = $p.Length
      Remove-Item $p.FullName -Force
      $totalRemoved++
      $totalBytesSaved += $sz
    }
  }
  $afterPlugins = Get-ChildItem -Path $dirPath -Recurse -Filter '*_plugin.dll' -ErrorAction SilentlyContinue
  $afterSize = ($afterPlugins | Measure-Object -Property Length -Sum).Sum
  Write-Host ("  Kept plugins:  {0}  Kept size:    {1:N1} MB" -f $afterPlugins.Count, ($afterSize / 1MB))
}

# 5. Remove non-plugin VLC files that a headless embedded playback use case
#    does not need. These are bundled by vlc_player for completeness but are
#    either VLC's own GUI/extension surface or localization we do not use.
#
#    - locale/      VLC UI translations (104 languages, ~41MB). Our UI is
#                   Flutter; VLC runs headless, so these are never loaded.
#    - lua/         VLC HTTP interface + playlist/extension scripts (~1.1MB).
#    - skins/       VLC skinnable GUI resources (~0.5MB).
#    - hrtfs/       Spatial audio HRTF data (~0.1MB); we do not enable it.
#    - axvlc.dll    VLC ActiveX / COM control (~1.3MB).
#    - npvlc.dll    VLC Netscape/Mozilla plugin (~1.2MB).
#    - debug_log.txt  Stale diagnostic file from an older build (source removed).
$extraDirs = @('locale', 'lua', 'skins', 'hrtfs')
$extraFiles = @('axvlc.dll', 'npvlc.dll', 'debug_log.txt')
foreach ($name in $extraDirs) {
  $p = Join-Path $releaseDir $name
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    $totalBytesSaved += $sz
    Write-Host ("Removed directory: {0}  ({1:N1} MB)" -f $name, ($sz / 1MB))
  }
}
foreach ($name in $extraFiles) {
  $p = Join-Path $releaseDir $name
  if (Test-Path $p) {
    $sz = (Get-Item $p).Length
    Remove-Item $p -Force -ErrorAction SilentlyContinue
    $totalBytesSaved += $sz
    Write-Host ("Removed file:      {0}  ({1:N1} MB)" -f $name, ($sz / 1MB))
  }
}

Write-Host ""
Write-Host ("Done. Removed {0} plugins, saved {1:N1} MB total." -f $totalRemoved, ($totalBytesSaved / 1MB))
