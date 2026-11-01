package com.cmuxremote.mobile.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import com.cmuxremote.mobile.protocol.ProtocolException
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Prepares attachments and reads previews within the Bridge's fixed image bounds. */
class ChatImageStore(private val context: Context) {
    /** Decodes, downsizes and re-encodes one picked image; throws ProtocolException("invalid_image") when unusable. */
    fun prepare(source: File): PreparedImage {
        val length = source.length()
        if (!source.isFile || length <= 0L || length > MAX_SOURCE_BYTES) invalid()
        val fileName = imageFileName(source.name)
        var working = decodeBounded(source) ?: invalid()
        try {
            for (attempt in 0 until MAX_ATTEMPTS) {
                if (attempt > 0) {
                    val nextWidth = maxOf(1, (working.width * 3 + 3) / 4)
                    val nextHeight = maxOf(1, (working.height * 3 + 3) / 4)
                    if (nextWidth == working.width && nextHeight == working.height) break
                    val scaled = Bitmap.createScaledBitmap(working, nextWidth, nextHeight, true)
                    if (scaled !== working) working.recycle()
                    working = scaled
                }
                val encoded = encodeWithinBudget(working) ?: continue
                return PreparedImage(
                    fileName = fileName,
                    format = "jpeg",
                    base64 = Base64.encodeToString(encoded, Base64.NO_WRAP),
                    byteCount = encoded.size,
                    pixelWidth = working.width,
                    pixelHeight = working.height,
                )
            }
        } finally {
            working.recycle()
        }
        invalid()
    }

    /** Caches one downloaded preview and returns its file. */
    fun cache(bytes: ByteArray, referenceId: String): File {
        if (bytes.size > MAX_PAYLOAD_BYTES || !isJpeg(bytes)) invalid()
        val directory = File(context.cacheDir, "images")
        if (!directory.isDirectory && !directory.mkdirs() && !directory.isDirectory) invalid()
        val target = File(directory, cacheName(referenceId))
        val temporary = File(directory, target.name + ".tmp")
        try {
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(target)) {
                temporary.delete()
                target.writeBytes(bytes)
            }
        } catch (error: IOException) {
            temporary.delete()
            invalid()
        }
        return target
    }

    /** Decodes bounds first, samples while decoding, then scales to the pixel limits. */
    private fun decodeBounded(source: File): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        val width = bounds.outWidth
        val height = bounds.outHeight
        val mime = bounds.outMimeType
        if (width <= 0 || height <= 0 || mime == null || !mime.startsWith("image/")) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(width, height)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val sampled = BitmapFactory.decodeFile(source.absolutePath, options) ?: return null
        val target = targetSize(sampled.width, sampled.height)
        if (target.width == sampled.width && target.height == sampled.height) return sampled
        val scaled = Bitmap.createScaledBitmap(sampled, target.width, target.height, true)
        if (scaled !== sampled) sampled.recycle()
        return scaled
    }

    /** Largest power-of-two sample that keeps the decoded bitmap inside both pixel limits. */
    private fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        while (true) {
            val sampledWidth = width / sample
            val sampledHeight = height / sample
            if (sampledWidth <= MAX_SIDE && sampledHeight <= MAX_SIDE &&
                sampledWidth.toLong() * sampledHeight.toLong() <= MAX_PIXELS
            ) break
            if (sampledWidth <= 1 || sampledHeight <= 1) break
            sample *= 2
        }
        return sample
    }

    /** Aspect-preserving size within the per-side and megapixel bounds. */
    private fun targetSize(width: Int, height: Int): Size {
        var factor = 1.0
        if (width > MAX_SIDE) factor = min(factor, MAX_SIDE.toDouble() / width)
        if (height > MAX_SIDE) factor = min(factor, MAX_SIDE.toDouble() / height)
        val pixels = width.toLong() * height.toLong()
        if (pixels > MAX_PIXELS) factor = min(factor, sqrt(MAX_PIXELS.toDouble() / pixels.toDouble()))
        if (factor >= 1.0) return Size(width, height)
        var targetWidth = maxOf(1, (width * factor).roundToInt())
        var targetHeight = maxOf(1, (height * factor).roundToInt())
        while (targetWidth > MAX_SIDE || targetHeight > MAX_SIDE ||
            targetWidth.toLong() * targetHeight.toLong() > MAX_PIXELS
        ) {
            if (targetWidth >= targetHeight) targetWidth -= 1 else targetHeight -= 1
        }
        return Size(targetWidth, targetHeight)
    }

    /** Re-encodes at descending quality; null means even the lowest quality is too large. */
    private fun encodeWithinBudget(bitmap: Bitmap): ByteArray? {
        for (quality in QUALITIES) {
            val output = ByteArrayOutputStream()
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)) continue
            val bytes = output.toByteArray()
            if (bytes.size <= MAX_PAYLOAD_BYTES) return bytes
        }
        return null
    }

    private fun imageFileName(name: String): String {
        val stem = name.substringBeforeLast('.', name)
            .filter { it != '\n' && it != '\r' && it != '\u0000' && it != '/' && it != '\\' }
        val bounded = StringBuilder()
        var bytes = 0
        for (character in stem) {
            val size = character.toString().toByteArray(Charsets.UTF_8).size
            if (bytes + size > 230) break
            bounded.append(character)
            bytes += size
        }
        val trimmed = bounded.toString().trim()
        return (if (trimmed.isEmpty()) "Image" else trimmed) + ".jpg"
    }

    /** A digest keeps an opaque reference from becoming a path. */
    private fun cacheName(referenceId: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(referenceId.toByteArray(Charsets.UTF_8))
        val name = StringBuilder(digest.size * 2 + 4)
        for (byte in digest) {
            val value = byte.toInt() and 0xff
            name.append(HEX[value ushr 4]).append(HEX[value and 0x0f])
        }
        return name.append(".jpg").toString()
    }

    private fun isJpeg(bytes: ByteArray): Boolean =
        bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()

    private fun invalid(): Nothing =
        throw ProtocolException("invalid_image", "Select a valid image within the upload limits.")

    private data class Size(val width: Int, val height: Int)

    private companion object {
        const val MAX_SOURCE_BYTES = 30L * 1024 * 1024
        const val MAX_PAYLOAD_BYTES = 512 * 1024
        // The Bridge accepts 4096px, but the iPhone sends 1600px so a reply is not
        // dominated by photos; Android uses the same bound.
        const val MAX_SIDE = 1600
        const val MAX_PIXELS = 8_388_608L
        const val MAX_ATTEMPTS = 8
        const val HEX = "0123456789abcdef"
        val QUALITIES = intArrayOf(85, 75, 65, 55, 45, 35, 25)
    }
}

data class PreparedImage(
    val fileName: String,
    val format: String,      // "jpeg"
    val base64: String,      // payload for `attachments[].data_b64`
    val byteCount: Int,
    val pixelWidth: Int,
    val pixelHeight: Int,
)
