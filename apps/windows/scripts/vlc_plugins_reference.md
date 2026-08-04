# VLC 插件完整清单（未精简基准）

生成时间：2026-07-12，来源：完整未裁剪的 Release 构建产物核对（media_kit + libvlc 打包），共 365 个 `_plugin.dll`，总体积约 131.6 MB。

## 使用方法

- **✅ 标记 = 当前 `strip_vlc_plugins.ps1` 白名单里保留的插件**，其余为已被裁剪脚本删除的插件。

**全部保留（不精简）总大小：131.6 MB**　|　**当前白名单保留：33.3 MB**

- 遇到播放问题（黑屏/无声/某格式播不了/某协议连不上），先看下面对应目录的"排查提示"，找到疑似缺失的插件，从未裁剪的完整构建里复制对应文件回精简版测试。

- **⚠️ 注意**：文件名必须与实际构建产物完全一致再写入白名单脚本，不要凭记忆猜测（历史上多次因为拼写错误导致白名单失效，例如 `libaccess_http_plugin` 实际应为 `libhttp_plugin`）。VLC/media_kit 升级后应重新核对本清单。

---

## access/ — 网络/本地文件访问协议
*36 个插件，共 17.78 MB（当前白名单保留 1.26 MB）*

> 💡 IPTV播放"连不上/加载失败"多半是这里缺了对应协议插件（http/https/tcp/udp/live555=RTSP等）

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libaccess_concat_plugin.dll` | 45 KB |
| ✅ | `libaccess_imem_plugin.dll` | 75 KB |
| — | `libaccess_mms_plugin.dll` | 109 KB |
| ✅ | `libaccess_realrtsp_plugin.dll` | 150 KB |
| — | `libaccess_srt_plugin.dll` | 3.52 MB |
| — | `libaccess_wasapi_plugin.dll` | 61 KB |
| — | `libattachment_plugin.dll` | 43 KB |
| — | `libcdda_plugin.dll` | 810 KB |
| — | `libdcp_plugin.dll` | 2.39 MB |
| — | `libdshow_plugin.dll` | 905 KB |
| — | `libdtv_plugin.dll` | 887 KB |
| — | `libdvdnav_plugin.dll` | 230 KB |
| — | `libdvdread_plugin.dll` | 165 KB |
| ✅ | `libfilesystem_plugin.dll` | 72 KB |
| — | `libftp_plugin.dll` | 127 KB |
| ✅ | `libhttp_plugin.dll` | 77 KB |
| ✅ | `libhttps_plugin.dll` | 155 KB |
| — | `libidummy_plugin.dll` | 44 KB |
| ✅ | `libimem_plugin.dll` | 44 KB |
| — | `liblibbluray_plugin.dll` | 2.03 MB |
| ✅ | `liblive555_plugin.dll` | 586 KB |
| — | `libnfs_plugin.dll` | 288 KB |
| — | `librist_plugin.dll` | 118 KB |
| — | `librtp_plugin.dll` | 662 KB |
| — | `libsatip_plugin.dll` | 77 KB |
| — | `libscreen_plugin.dll` | 51 KB |
| — | `libsdp_plugin.dll` | 43 KB |
| — | `libsftp_plugin.dll` | 869 KB |
| — | `libshm_plugin.dll` | 46 KB |
| — | `libsmb_plugin.dll` | 70 KB |
| ✅ | `libtcp_plugin.dll` | 43 KB |
| — | `libtimecode_plugin.dll` | 67 KB |
| ✅ | `libudp_plugin.dll` | 45 KB |
| — | `libvcd_plugin.dll` | 111 KB |
| — | `libvdr_plugin.dll` | 109 KB |
| — | `libvnc_plugin.dll` | 2.83 MB |

## access_output/ — 推流/转码输出（sout）
*8 个插件，共 4.91 MB（当前白名单保留 0.00 MB）*

> 💡 纯播放场景不需要，只有做转发/录制/推流功能才用得到

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libaccess_output_dummy_plugin.dll` | 42 KB |
| — | `libaccess_output_file_plugin.dll` | 47 KB |
| — | `libaccess_output_http_plugin.dll` | 48 KB |
| — | `libaccess_output_livehttp_plugin.dll` | 670 KB |
| — | `libaccess_output_rist_plugin.dll` | 114 KB |
| — | `libaccess_output_shout_plugin.dll` | 459 KB |
| — | `libaccess_output_srt_plugin.dll` | 3.52 MB |
| — | `libaccess_output_udp_plugin.dll` | 48 KB |

## audio_filter/ — 音频滤镜（混音/重采样/均衡器等）
*25 个插件，共 3.87 MB（当前白名单保留 0.32 MB）*

> 💡 倍速播放变调、音量异常，检查 scaletempo/simple_channel_mixer/ugly_resampler 等是否都在

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libaudio_format_plugin.dll` | 67 KB |
| — | `libaudiobargraph_a_plugin.dll` | 72 KB |
| — | `libchorus_flanger_plugin.dll` | 53 KB |
| — | `libcompressor_plugin.dll` | 57 KB |
| — | `libdolby_surround_decoder_plugin.dll` | 43 KB |
| — | `libequalizer_plugin.dll` | 84 KB |
| — | `libgain_plugin.dll` | 43 KB |
| — | `libheadphone_channel_mixer_plugin.dll` | 49 KB |
| — | `libkaraoke_plugin.dll` | 42 KB |
| — | `libmad_plugin.dll` | 170 KB |
| — | `libmono_plugin.dll` | 50 KB |
| — | `libnormvol_plugin.dll` | 46 KB |
| — | `libparam_eq_plugin.dll` | 53 KB |
| — | `libremap_plugin.dll` | 50 KB |
| — | `libsamplerate_plugin.dll` | 1.45 MB |
| — | `libscaletempo_pitch_plugin.dll` | 57 KB |
| ✅ | `libscaletempo_plugin.dll` | 51 KB |
| ✅ | `libsimple_channel_mixer_plugin.dll` | 51 KB |
| — | `libspatialaudio_plugin.dll` | 1.04 MB |
| ✅ | `libspatializer_plugin.dll` | 116 KB |
| — | `libspeex_resampler_plugin.dll` | 55 KB |
| — | `libstereo_widen_plugin.dll` | 47 KB |
| — | `libtospdif_plugin.dll` | 59 KB |
| — | `libtrivial_channel_mixer_plugin.dll` | 46 KB |
| ✅ | `libugly_resampler_plugin.dll` | 43 KB |

## audio_mixer/ — 音频混音核心
*2 个插件，共 0.09 MB（当前白名单保留 0.04 MB）*

> 💡 float_mixer 几乎必须保留，否则可能完全无声

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libfloat_mixer_plugin.dll` | 43 KB |
| — | `libinteger_mixer_plugin.dll` | 47 KB |

## audio_output/ — Windows 音频输出
*7 个插件，共 0.38 MB（当前白名单保留 0.19 MB）*

> 💡 完全无声先查这里：directsound/wasapi/mmdevice

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libadummy_plugin.dll` | 42 KB |
| — | `libafile_plugin.dll` | 46 KB |
| — | `libamem_plugin.dll` | 45 KB |
| ✅ | `libdirectsound_plugin.dll` | 64 KB |
| ✅ | `libmmdevice_plugin.dll` | 70 KB |
| ✅ | `libwasapi_plugin.dll` | 61 KB |
| — | `libwaveout_plugin.dll` | 61 KB |

## codec/ — 解码器（体积最大的目录，46MB+）
*61 个插件，共 46.38 MB（当前白名单保留 18.31 MB）*

> 💡 "能加载但黑屏/无声"先查 avcodec 是否在；某个格式播不了，可能是对应 codec 被裁掉

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `liba52_plugin.dll` | 110 KB |
| ✅ | `libadpcm_plugin.dll` | 53 KB |
| — | `libaes3_plugin.dll` | 46 KB |
| — | `libaom_plugin.dll` | 1.97 MB |
| ✅ | `libaraw_plugin.dll` | 66 KB |
| — | `libaribsub_plugin.dll` | 347 KB |
| ✅ | `libavcodec_plugin.dll` | 16.47 MB |
| — | `libcc_plugin.dll` | 78 KB |
| — | `libcdg_plugin.dll` | 48 KB |
| — | `libcrystalhd_plugin.dll` | 119 KB |
| — | `libcvdsub_plugin.dll` | 49 KB |
| — | `libd3d11va_plugin.dll` | 292 KB |
| — | `libdav1d_plugin.dll` | 1.80 MB |
| ✅ | `libdca_plugin.dll` | 211 KB |
| — | `libddummy_plugin.dll` | 67 KB |
| — | `libdmo_plugin.dll` | 68 KB |
| — | `libdvbsub_plugin.dll` | 121 KB |
| — | `libdxva2_plugin.dll` | 326 KB |
| — | `libedummy_plugin.dll` | 42 KB |
| — | `libfaad_plugin.dll` | 302 KB |
| ✅ | `libflac_plugin.dll` | 242 KB |
| — | `libfluidsynth_plugin.dll` | 148 KB |
| — | `libg711_plugin.dll` | 56 KB |
| — | `libjpeg_plugin.dll` | 241 KB |
| — | `libkate_plugin.dll` | 98 KB |
| — | `liblibass_plugin.dll` | 2.98 MB |
| — | `liblibmpeg2_plugin.dll` | 147 KB |
| — | `liblpcm_plugin.dll` | 53 KB |
| — | `libmft_plugin.dll` | 137 KB |
| — | `libmpg123_plugin.dll` | 414 KB |
| — | `liboggspots_plugin.dll` | 46 KB |
| ✅ | `libopus_plugin.dll` | 376 KB |
| — | `libpng_plugin.dll` | 284 KB |
| — | `libqsv_plugin.dll` | 171 KB |
| — | `librawvideo_plugin.dll` | 45 KB |
| — | `librtpvideo_plugin.dll` | 42 KB |
| — | `libschroedinger_plugin.dll` | 1.39 MB |
| — | `libscte18_plugin.dll` | 49 KB |
| — | `libscte27_plugin.dll` | 61 KB |
| — | `libsdl_image_plugin.dll` | 737 KB |
| — | `libspdif_plugin.dll` | 42 KB |
| — | `libspeex_plugin.dll` | 168 KB |
| — | `libspudec_plugin.dll` | 52 KB |
| — | `libstl_plugin.dll` | 49 KB |
| — | `libsubsdec_plugin.dll` | 80 KB |
| — | `libsubstx3g_plugin.dll` | 48 KB |
| ✅ | `libsubsusf_plugin.dll` | 55 KB |
| — | `libsvcdsub_plugin.dll` | 47 KB |
| — | `libt140_plugin.dll` | 43 KB |
| — | `libtextst_plugin.dll` | 47 KB |
| — | `libtheora_plugin.dll` | 331 KB |
| — | `libttml_plugin.dll` | 124 KB |
| — | `libtwolame_plugin.dll` | 162 KB |
| — | `libuleaddvaudio_plugin.dll` | 44 KB |
| ✅ | `libvorbis_plugin.dll` | 769 KB |
| — | `libvpx_plugin.dll` | 4.30 MB |
| — | `libwebvtt_plugin.dll` | 188 KB |
| — | `libx26410b_plugin.dll` | 1.80 MB |
| — | `libx264_plugin.dll` | 1.80 MB |
| — | `libx265_plugin.dll` | 4.69 MB |
| — | `libzvbi_plugin.dll` | 1.42 MB |

## control/ — VLC 交互控制（热键/手势/系统服务等）
*8 个插件，共 0.47 MB（当前白名单保留 0.00 MB）*

> 💡 桌面GUI控制相关，Flutter嵌入式场景基本不需要

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libdummy_plugin.dll` | 42 KB |
| — | `libgestures_plugin.dll` | 48 KB |
| — | `libhotkeys_plugin.dll` | 88 KB |
| — | `libnetsync_plugin.dll` | 48 KB |
| — | `libntservice_plugin.dll` | 70 KB |
| — | `liboldrc_plugin.dll` | 96 KB |
| — | `libwin_hotkeys_plugin.dll` | 46 KB |
| — | `libwin_msg_plugin.dll` | 45 KB |

## d3d11/ — Direct3D11 滤镜辅助
*1 个插件，共 0.20 MB（当前白名单保留 0.20 MB）*

> 💡 和 video_output/libdirect3d11_plugin 配套使用

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libdirect3d11_filters_plugin.dll` | 202 KB |

## d3d9/ — Direct3D9 滤镜辅助
*1 个插件，共 0.15 MB（当前白名单保留 0.15 MB）*

> 💡 和 video_output/libdirect3d9_plugin 配套使用

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libdirect3d9_filters_plugin.dll` | 151 KB |

## demux/ — 容器解封装（拆包）
*46 个插件，共 10.48 MB（当前白名单保留 5.75 MB）*

> 💡 HLS(.m3u8)黑屏先查 libadaptive_plugin；MP4/MKV/TS等格式播不了查对应demux插件是否还在

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libadaptive_plugin.dll` | 2.30 MB |
| — | `libaiff_plugin.dll` | 45 KB |
| ✅ | `libasf_plugin.dll` | 123 KB |
| — | `libau_plugin.dll` | 44 KB |
| ✅ | `libavi_plugin.dll` | 136 KB |
| — | `libcaf_plugin.dll` | 51 KB |
| — | `libdemux_cdg_plugin.dll` | 44 KB |
| — | `libdemux_chromecast_plugin.dll` | 111 KB |
| — | `libdemux_stl_plugin.dll` | 47 KB |
| — | `libdemuxdump_plugin.dll` | 44 KB |
| — | `libdiracsys_plugin.dll` | 44 KB |
| — | `libdirectory_demux_plugin.dll` | 43 KB |
| ✅ | `libes_plugin.dll` | 72 KB |
| — | `libflacsys_plugin.dll` | 118 KB |
| — | `libgme_plugin.dll` | 1.06 MB |
| — | `libh26x_plugin.dll` | 144 KB |
| — | `libimage_plugin.dll` | 56 KB |
| — | `libmjpeg_plugin.dll` | 50 KB |
| ✅ | `libmkv_plugin.dll` | 1.67 MB |
| — | `libmod_plugin.dll` | 440 KB |
| ✅ | `libmp4_plugin.dll` | 323 KB |
| — | `libmpc_plugin.dll` | 109 KB |
| — | `libmpgv_plugin.dll` | 44 KB |
| — | `libnoseek_plugin.dll` | 42 KB |
| — | `libnsc_plugin.dll` | 80 KB |
| — | `libnsv_plugin.dll` | 48 KB |
| — | `libnuv_plugin.dll` | 50 KB |
| ✅ | `libogg_plugin.dll` | 342 KB |
| — | `libplaylist_plugin.dll` | 172 KB |
| ✅ | `libps_plugin.dll` | 74 KB |
| — | `libpva_plugin.dll` | 50 KB |
| — | `librawaud_plugin.dll` | 45 KB |
| ✅ | `librawdv_plugin.dll` | 46 KB |
| ✅ | `librawvid_plugin.dll` | 49 KB |
| — | `libreal_plugin.dll` | 68 KB |
| — | `libsid_plugin.dll` | 1.21 MB |
| — | `libsmf_plugin.dll` | 52 KB |
| — | `libsubtitle_plugin.dll` | 123 KB |
| ✅ | `libts_plugin.dll` | 612 KB |
| — | `libtta_plugin.dll` | 45 KB |
| — | `libty_plugin.dll` | 63 KB |
| — | `libvc1_plugin.dll` | 44 KB |
| — | `libvobsub_plugin.dll` | 110 KB |
| — | `libvoc_plugin.dll` | 47 KB |
| ✅ | `libwav_plugin.dll` | 52 KB |
| — | `libxa_plugin.dll` | 44 KB |

## gui/ — VLC 自带 GUI（Qt/皮肤界面）
*2 个插件，共 18.86 MB（当前白名单保留 0.00 MB）*

> 💡 Flutter 嵌入式场景完全不需要，可以整个目录删除

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libqt_plugin.dll` | 16.61 MB |
| — | `libskins2_plugin.dll` | 2.25 MB |

## keystore/ — 凭据/密钥存储
*2 个插件，共 0.11 MB（当前白名单保留 0.04 MB）*

> 💡 需要密码保护的流媒体源（少见）才用得到

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libfile_keystore_plugin.dll` | 73 KB |
| ✅ | `libmemory_keystore_plugin.dll` | 44 KB |

## logger/ — 日志输出
*2 个插件，共 0.13 MB（当前白名单保留 0.00 MB）*

> 💡 排查问题时如果要打详细日志，需要保留 console_logger 或 file_logger

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libconsole_logger_plugin.dll` | 66 KB |
| — | `libfile_logger_plugin.dll` | 69 KB |

## lua/ — VLC Lua 脚本引擎（HTTP接口/播放列表脚本）
*1 个插件，共 0.38 MB（当前白名单保留 0.00 MB）*

> 💡 和顶层 lua/ 目录不同，这里是引擎本体，顶层是脚本资源

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `liblua_plugin.dll` | 390 KB |

## meta_engine/ — 媒体元数据解析（标签/封面等）
*2 个插件，共 1.54 MB（当前白名单保留 0.00 MB）*

> 💡 音乐/视频列表显示标题、专辑封面缺失可以查这里

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libfolder_plugin.dll` | 66 KB |
| — | `libtaglib_plugin.dll` | 1.48 MB |

## misc/ — 核心杂项（日志/统计/加密等）
*10 个插件，共 3.77 MB（当前白名单保留 0.16 MB）*

> 💡 logger、stats 建议保留，其余多是插件市场/指纹识别等边缘功能

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libaddonsfsstorage_plugin.dll` | 110 KB |
| — | `libaddonsvorepository_plugin.dll` | 103 KB |
| ✅ | `libaudioscrobbler_plugin.dll` | 79 KB |
| — | `libexport_plugin.dll` | 74 KB |
| — | `libfingerprinter_plugin.dll` | 87 KB |
| — | `libgnutls_plugin.dll` | 2.08 MB |
| ✅ | `liblogger_plugin.dll` | 42 KB |
| ✅ | `libstats_plugin.dll` | 46 KB |
| — | `libvod_rtsp_plugin.dll` | 124 KB |
| — | `libxml_plugin.dll` | 1.04 MB |

## mux/ — 容器封装（打包）
*9 个插件，共 0.90 MB（当前白名单保留 0.00 MB）*

> 💡 只有做录制/转码/推流才需要，纯播放不需要

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libmux_asf_plugin.dll` | 75 KB |
| — | `libmux_avi_plugin.dll` | 61 KB |
| — | `libmux_dummy_plugin.dll` | 44 KB |
| — | `libmux_mp4_plugin.dll` | 260 KB |
| — | `libmux_mpjpeg_plugin.dll` | 66 KB |
| — | `libmux_ogg_plugin.dll` | 98 KB |
| — | `libmux_ps_plugin.dll` | 94 KB |
| — | `libmux_ts_plugin.dll` | 173 KB |
| — | `libmux_wav_plugin.dll` | 47 KB |

## packetizer/ — 裸流打包（TS直播流必需）
*14 个插件，共 1.02 MB（当前白名单保留 0.67 MB）*

> 💡 IPTV能连接、demux能拆包但依然黑屏，十有八九是这里缺了对应编码的packetizer（h264/hevc/mpeg4audio等）

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libpacketizer_a52_plugin.dll` | 54 KB |
| — | `libpacketizer_av1_plugin.dll` | 68 KB |
| ✅ | `libpacketizer_copy_plugin.dll` | 44 KB |
| — | `libpacketizer_dirac_plugin.dll` | 59 KB |
| ✅ | `libpacketizer_dts_plugin.dll` | 54 KB |
| — | `libpacketizer_flac_plugin.dll` | 53 KB |
| ✅ | `libpacketizer_h264_plugin.dll` | 172 KB |
| ✅ | `libpacketizer_hevc_plugin.dll` | 155 KB |
| — | `libpacketizer_mlp_plugin.dll` | 60 KB |
| ✅ | `libpacketizer_mpeg4audio_plugin.dll` | 94 KB |
| — | `libpacketizer_mpeg4video_plugin.dll` | 58 KB |
| ✅ | `libpacketizer_mpegaudio_plugin.dll` | 49 KB |
| ✅ | `libpacketizer_mpegvideo_plugin.dll` | 58 KB |
| — | `libpacketizer_vc1_plugin.dll` | 66 KB |

## services_discovery/ — 局域网服务发现（UPnP/SAP/mDNS等）
*6 个插件，共 1.35 MB（当前白名单保留 0.00 MB）*

> 💡 扫描局域网媒体服务器/共享才需要，纯播放不需要

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libmediadirs_plugin.dll` | 47 KB |
| — | `libmicrodns_plugin.dll` | 120 KB |
| — | `libpodcast_plugin.dll` | 50 KB |
| — | `libsap_plugin.dll` | 154 KB |
| — | `libupnp_plugin.dll` | 970 KB |
| — | `libwindrive_plugin.dll` | 44 KB |

## spu/ — 字幕/OSD叠加特效
*7 个插件，共 1.00 MB（当前白名单保留 0.00 MB）*

> 💡 除基础字幕渲染外，这里多是花字/水印/马赛克等特效，基本用不到

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libaudiobargraph_v_plugin.dll` | 52 KB |
| — | `liblogo_plugin.dll` | 51 KB |
| — | `libmarq_plugin.dll` | 51 KB |
| — | `libmosaic_plugin.dll` | 59 KB |
| — | `libremoteosd_plugin.dll` | 676 KB |
| — | `librss_plugin.dll` | 77 KB |
| — | `libsubsdelay_plugin.dll` | 54 KB |

## stream_extractor/ — 压缩包内容提取（zip等）
*1 个插件，共 0.46 MB（当前白名单保留 0.00 MB）*

> 💡 播放压缩包内媒体文件才需要，基本用不到

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libarchive_plugin.dll` | 474 KB |

## stream_filter/ — 流预处理（缓存/解压/预读等）
*9 个插件，共 0.49 MB（当前白名单保留 0.00 MB）*

> 💡 libcache_read/libcache_block 与播放流畅度有关，网络卡顿可以关注

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libadf_plugin.dll` | 44 KB |
| — | `libaribcam_plugin.dll` | 70 KB |
| — | `libcache_block_plugin.dll` | 46 KB |
| — | `libcache_read_plugin.dll` | 46 KB |
| — | `libhds_plugin.dll` | 84 KB |
| — | `libinflate_plugin.dll` | 73 KB |
| — | `libprefetch_plugin.dll` | 47 KB |
| — | `librecord_plugin.dll` | 44 KB |
| — | `libskiptags_plugin.dll` | 44 KB |

## stream_out/ — 推流/转码/录制输出
*20 个插件，共 3.94 MB（当前白名单保留 0.00 MB）*

> 💡 和 access_output 类似，纯播放完全不需要

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libstream_out_autodel_plugin.dll` | 44 KB |
| — | `libstream_out_bridge_plugin.dll` | 73 KB |
| — | `libstream_out_chromaprint_plugin.dll` | 1.16 MB |
| — | `libstream_out_chromecast_plugin.dll` | 1.07 MB |
| — | `libstream_out_cycle_plugin.dll` | 45 KB |
| — | `libstream_out_delay_plugin.dll` | 44 KB |
| — | `libstream_out_description_plugin.dll` | 43 KB |
| — | `libstream_out_display_plugin.dll` | 44 KB |
| — | `libstream_out_dummy_plugin.dll` | 42 KB |
| — | `libstream_out_duplicate_plugin.dll` | 99 KB |
| — | `libstream_out_es_plugin.dll` | 48 KB |
| — | `libstream_out_gather_plugin.dll` | 45 KB |
| — | `libstream_out_mosaic_bridge_plugin.dll` | 52 KB |
| — | `libstream_out_record_plugin.dll` | 77 KB |
| — | `libstream_out_rtp_plugin.dll` | 780 KB |
| — | `libstream_out_setid_plugin.dll` | 45 KB |
| — | `libstream_out_smem_plugin.dll` | 47 KB |
| — | `libstream_out_standard_plugin.dll` | 75 KB |
| — | `libstream_out_stats_plugin.dll` | 68 KB |
| — | `libstream_out_transcode_plugin.dll` | 74 KB |

## text_renderer/ — 字幕文字渲染
*3 个插件，共 2.76 MB（当前白名单保留 2.67 MB）*

> 💡 freetype 必须保留才能正常显示字幕文字

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libfreetype_plugin.dll` | 2.67 MB |
| — | `libsapi_plugin.dll` | 50 KB |
| — | `libtdummy_plugin.dll` | 42 KB |

## video_chroma/ — 像素格式转换（解码输出→渲染输入）
*19 个插件，共 2.17 MB（当前白名单保留 1.30 MB）*

> 💡 "能解码但画面花屏/纯色/黑屏"经常是这里缺了对应的chroma转换插件

| 状态 | 文件名 | 大小 |
|---|---|---|
| ✅ | `libchain_plugin.dll` | 71 KB |
| — | `libgrey_yuv_plugin.dll` | 48 KB |
| — | `libi420_10_p010_plugin.dll` | 116 KB |
| — | `libi420_nv12_plugin.dll` | 118 KB |
| — | `libi420_rgb_mmx_plugin.dll` | 84 KB |
| ✅ | `libi420_rgb_plugin.dll` | 61 KB |
| — | `libi420_rgb_sse2_plugin.dll` | 147 KB |
| — | `libi420_yuy2_mmx_plugin.dll` | 52 KB |
| ✅ | `libi420_yuy2_plugin.dll` | 63 KB |
| — | `libi420_yuy2_sse2_plugin.dll` | 61 KB |
| ✅ | `libi422_i420_plugin.dll` | 45 KB |
| — | `libi422_yuy2_mmx_plugin.dll` | 48 KB |
| ✅ | `libi422_yuy2_plugin.dll` | 58 KB |
| — | `libi422_yuy2_sse2_plugin.dll` | 54 KB |
| — | `librv32_plugin.dll` | 43 KB |
| ✅ | `libswscale_plugin.dll` | 993 KB |
| ✅ | `libyuvp_plugin.dll` | 44 KB |
| — | `libyuy2_i420_plugin.dll` | 60 KB |
| — | `libyuy2_i422_plugin.dll` | 54 KB |

## video_filter/ — 视频画面滤镜特效
*41 个插件，共 2.52 MB（当前白名单保留 0.16 MB）*

> 💡 基础播放只需要 deinterlace（去交错），其余都是画面特效可选功能

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libadjust_plugin.dll` | 93 KB |
| — | `libalphamask_plugin.dll` | 45 KB |
| — | `libanaglyph_plugin.dll` | 47 KB |
| — | `libantiflicker_plugin.dll` | 52 KB |
| — | `libball_plugin.dll` | 65 KB |
| — | `libblend_plugin.dll` | 187 KB |
| — | `libblendbench_plugin.dll` | 46 KB |
| — | `libbluescreen_plugin.dll` | 53 KB |
| — | `libcanvas_plugin.dll` | 69 KB |
| — | `libcolorthres_plugin.dll` | 47 KB |
| — | `libcroppadd_plugin.dll` | 49 KB |
| ✅ | `libdeinterlace_plugin.dll` | 162 KB |
| — | `libedgedetection_plugin.dll` | 44 KB |
| — | `liberase_plugin.dll` | 50 KB |
| — | `libextract_plugin.dll` | 48 KB |
| — | `libfps_plugin.dll` | 44 KB |
| — | `libfreeze_plugin.dll` | 48 KB |
| — | `libgaussianblur_plugin.dll` | 49 KB |
| — | `libgradfun_plugin.dll` | 54 KB |
| — | `libgradient_plugin.dll` | 63 KB |
| — | `libgrain_plugin.dll` | 58 KB |
| — | `libhqdn3d_plugin.dll` | 58 KB |
| — | `libinvert_plugin.dll` | 46 KB |
| — | `libmagnify_plugin.dll` | 47 KB |
| — | `libmirror_plugin.dll` | 50 KB |
| — | `libmotionblur_plugin.dll` | 47 KB |
| — | `libmotiondetect_plugin.dll` | 53 KB |
| — | `liboldmovie_plugin.dll` | 54 KB |
| — | `libposterize_plugin.dll` | 48 KB |
| — | `libpostproc_plugin.dll` | 149 KB |
| — | `libpsychedelic_plugin.dll` | 45 KB |
| — | `libpuzzle_plugin.dll` | 113 KB |
| — | `libripple_plugin.dll` | 46 KB |
| — | `librotate_plugin.dll` | 87 KB |
| — | `libscale_plugin.dll` | 44 KB |
| — | `libscene_plugin.dll` | 69 KB |
| — | `libsepia_plugin.dll` | 47 KB |
| — | `libsharpen_plugin.dll` | 45 KB |
| — | `libtransform_plugin.dll` | 59 KB |
| — | `libvhs_plugin.dll` | 47 KB |
| — | `libwave_plugin.dll` | 46 KB |

## video_output/ — 视频输出渲染 + 窗口/表面创建（本清单最关键目录）
*15 个插件，共 3.25 MB（当前白名单保留 2.10 MB）*

> 💡 黑屏问题优先查这里：direct3d11/d3d9/wgl等渲染器 + glwin32/wingdi等窗口句柄创建 + vmem内存纹理输出

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libcaca_plugin.dll` | 828 KB |
| ✅ | `libdirect3d11_plugin.dll` | 376 KB |
| ✅ | `libdirect3d9_plugin.dll` | 268 KB |
| ✅ | `libdirectdraw_plugin.dll` | 251 KB |
| — | `libdrawable_plugin.dll` | 43 KB |
| — | `libflaschen_plugin.dll` | 68 KB |
| ✅ | `libgl_plugin.dll` | 246 KB |
| — | `libglinterop_dxva2_plugin.dll` | 130 KB |
| ✅ | `libglwin32_plugin.dll` | 437 KB |
| — | `libvdummy_plugin.dll` | 45 KB |
| ✅ | `libvmem_plugin.dll` | 46 KB |
| ✅ | `libwgl_plugin.dll` | 244 KB |
| ✅ | `libwingdi_plugin.dll` | 234 KB |
| ✅ | `libwinhibit_plugin.dll` | 44 KB |
| — | `libyuv_plugin.dll` | 68 KB |

## video_splitter/ — 多屏/画面分割
*3 个插件，共 0.19 MB（当前白名单保留 0.00 MB）*

> 💡 多路画面分屏显示才需要，基本用不到

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libclone_plugin.dll` | 45 KB |
| — | `libpanoramix_plugin.dll` | 69 KB |
| — | `libwall_plugin.dll` | 83 KB |

## visualization/ — 音乐可视化特效（频谱/goom等）
*4 个插件，共 2.01 MB（当前白名单保留 0.00 MB）*

> 💡 播放器场景完全不需要

| 状态 | 文件名 | 大小 |
|---|---|---|
| — | `libglspectrum_plugin.dll` | 63 KB |
| — | `libgoom_plugin.dll` | 225 KB |
| — | `libprojectm_plugin.dll` | 1.65 MB |
| — | `libvisual_plugin.dll` | 79 KB |
