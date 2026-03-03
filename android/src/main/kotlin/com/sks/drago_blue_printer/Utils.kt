package com.sks.drago_blue_printer

import android.graphics.Bitmap
import android.util.Log
import java.io.ByteArrayOutputStream

object Utils {
    // UNICODE 0x23 = #
    val UNICODE_TEXT = byteArrayOf(
        0x23, 0x23, 0x23,
        0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23,
        0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23, 0x23,
        0x23, 0x23, 0x23
    )

    /**
     * Decode a Bitmap into ESC/POS raster bit-image command bytes (GS v 0).
     *
     * Optimized: uses direct byte manipulation instead of String-based
     * binary→hex conversion. This is ~10-20x faster on typical receipt images.
     *
     * Reads all pixels in bulk via [Bitmap.getPixels] instead of per-pixel
     * [Bitmap.getPixel] calls, avoiding JNI overhead per pixel.
     */
    fun decodeBitmap(bmp: Bitmap): ByteArray? {
        val bmpWidth = bmp.width
        val bmpHeight = bmp.height

        // Width in bytes (each byte = 8 pixels, padded to full byte)
        val widthBytes = (bmpWidth + 7) / 8

        if (widthBytes > 255 || bmpHeight > 65535) {
            Log.e("decodeBitmap error", "Image dimensions too large: ${bmpWidth}x${bmpHeight}")
            return null
        }

        // Read all pixels at once — ~5x faster than per-pixel getPixel() calls
        val pixels = IntArray(bmpWidth * bmpHeight)
        bmp.getPixels(pixels, 0, bmpWidth, 0, 0, bmpWidth, bmpHeight)

        // Pre-allocate output: 8-byte header + (widthBytes * bmpHeight) image data
        val imageDataSize = widthBytes * bmpHeight
        val output = ByteArrayOutputStream(8 + imageDataSize)

        // GS v 0 command header: 1D 76 30 00 xL xH yL yH
        output.write(0x1D)
        output.write(0x76)
        output.write(0x30)
        output.write(0x00)
        output.write(widthBytes and 0xFF)        // xL
        output.write((widthBytes shr 8) and 0xFF) // xH
        output.write(bmpHeight and 0xFF)          // yL
        output.write((bmpHeight shr 8) and 0xFF)  // yH

        // Convert pixels to 1-bit raster data directly (no string intermediaries)
        // Process one row at a time, packing 8 pixels into each byte
        val rowBuffer = ByteArray(widthBytes)
        for (y in 0 until bmpHeight) {
            val rowOffset = y * bmpWidth
            // Clear row buffer
            for (i in rowBuffer.indices) rowBuffer[i] = 0

            for (x in 0 until bmpWidth) {
                val color = pixels[rowOffset + x]
                val r = (color shr 16) and 0xFF
                val g = (color shr 8) and 0xFF
                val b = color and 0xFF

                // If pixel is dark (not close to white), set bit to 1
                if (r <= 160 || g <= 160 || b <= 160) {
                    val byteIndex = x / 8
                    val bitIndex = 7 - (x % 8) // MSB first
                    rowBuffer[byteIndex] = (rowBuffer[byteIndex].toInt() or (1 shl bitIndex)).toByte()
                }
            }
            output.write(rowBuffer)
        }

        return output.toByteArray()
    }
}
