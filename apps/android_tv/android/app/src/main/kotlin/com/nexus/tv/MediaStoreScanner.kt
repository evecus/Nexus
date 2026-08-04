package com.nexus.tv

import android.content.Context
import android.database.Cursor
import android.os.Build
import android.os.storage.StorageManager
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel

/**
 * 通过 MediaStore 查询本地视频 / 音频文件。
 *
 * 与直接遍历文件路径不同，MediaStore 由系统媒体扫描服务统一维护，
 * 会自动索引所有已挂载的存储卷（内置存储、SD 卡、OTG U 盘等），
 * 因此这里只需查询一次 EXTERNAL_CONTENT_URI，即可覆盖全部外置存储设备
 * 上已被系统扫描到的媒体文件，无需再手动枚举各个存储卷的挂载路径。
 */
object MediaStoreScanner {

    private const val CHANNEL_NAME = "com.nexus.tv/media_store"

    fun register(context: Context, messenger: io.flutter.plugin.common.BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanVideos" -> {
                    try {
                        result.success(queryVideos(context))
                    } catch (e: Exception) {
                        result.error("SCAN_VIDEOS_FAILED", e.message, null)
                    }
                }
                "scanAudios" -> {
                    try {
                        result.success(queryAudios(context))
                    } catch (e: Exception) {
                        result.error("SCAN_AUDIOS_FAILED", e.message, null)
                    }
                }
                "listVolumes" -> {
                    try {
                        result.success(listStorageVolumePaths(context))
                    } catch (e: Exception) {
                        result.error("LIST_VOLUMES_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 查询所有视频文件，返回 List<Map<String, Any?>>，字段与 Dart 端
     * ScannedVideo 对应：path / name / size / modified / folder。
     */
    private fun queryVideos(context: Context): List<Map<String, Any?>> {
        val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATE_MODIFIED,
            MediaStore.Video.Media.VOLUME_NAME,
        )
        val sortOrder = "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
        val out = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(uri, projection, null, null, sortOrder)?.use { cursor ->
            val iId = cursor.getColumnIndex(MediaStore.Video.Media._ID)
            val iData = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
            val iName = cursor.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
            val iSize = cursor.getColumnIndex(MediaStore.Video.Media.SIZE)
            val iMod = cursor.getColumnIndex(MediaStore.Video.Media.DATE_MODIFIED)

            while (cursor.moveToNext()) {
                val path = safeGetString(cursor, iData)
                if (path.isNullOrEmpty()) continue
                val name = safeGetString(cursor, iName) ?: fileNameFromPath(path)
                val size = safeGetLong(cursor, iSize)
                val modifiedSec = safeGetLong(cursor, iMod)
                val folder = path.substringBeforeLast('/', "")

                // 部分厂商 ROM 对已拔出/离线存储卷的记录不会及时从 MediaStore 移除，
                // 这里做一次文件存在性校验，避免把失效路径展示给用户。
                if (!java.io.File(path).exists()) continue

                out.add(
                    mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "modified" to modifiedSec * 1000L,
                        "folder" to folder,
                    )
                )
            }
        }
        return out
    }

    /**
     * 查询所有音频文件，返回字段与 Dart 端 ScannedAudio 对应：
     * path / name / size / modified / folder。
     */
    private fun queryAudios(context: Context): List<Map<String, Any?>> {
        val uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.IS_MUSIC,
        )
        // 只取"音乐"类音频，过滤掉铃声/通知音/录音等系统音频文件。
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
        val out = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(uri, projection, selection, null, sortOrder)?.use { cursor ->
            val iData = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            val iName = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
            val iSize = cursor.getColumnIndex(MediaStore.Audio.Media.SIZE)
            val iMod = cursor.getColumnIndex(MediaStore.Audio.Media.DATE_MODIFIED)

            while (cursor.moveToNext()) {
                val path = safeGetString(cursor, iData)
                if (path.isNullOrEmpty()) continue
                val name = safeGetString(cursor, iName) ?: fileNameFromPath(path)
                val size = safeGetLong(cursor, iSize)
                val modifiedSec = safeGetLong(cursor, iMod)
                val folder = path.substringBeforeLast('/', "")

                if (!java.io.File(path).exists()) continue

                out.add(
                    mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "modified" to modifiedSec * 1000L,
                        "folder" to folder,
                    )
                )
            }
        }
        return out
    }

    /**
     * 列出系统当前挂载的所有存储卷根路径（内置存储 + SD 卡 + OTG 等），
     * 仅作调试/诊断用途，暴露给 Dart 端可用于展示"已识别的存储设备"列表。
     */
    private fun listStorageVolumePaths(context: Context): List<String> {
        val result = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val sm = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            for (volume in sm.storageVolumes) {
                try {
                    val dir = volume.directory
                    if (dir != null) {
                        result.add(dir.absolutePath)
                    }
                } catch (_: Exception) {
                    // 部分系统版本 directory 字段可能为 null 或访问受限，忽略即可。
                }
            }
        }
        return result
    }

    private fun safeGetString(cursor: Cursor, index: Int): String? =
        if (index >= 0) cursor.getString(index) else null

    private fun safeGetLong(cursor: Cursor, index: Int): Long =
        if (index >= 0) cursor.getLong(index) else 0L

    private fun fileNameFromPath(path: String): String =
        path.substringAfterLast('/', path)
}
