package com.sks.drago_blue_printer

object PrinterCommands {
    const val HT: Byte = 0x9
    const val LF: Byte = 0x0A
    const val CR: Byte = 0x0D
    const val ESC: Byte = 0x1B
    const val DLE: Byte = 0x10
    const val GS: Byte = 0x1D
    const val FS: Byte = 0x1C
    const val STX: Byte = 0x02
    const val US: Byte = 0x1F
    const val CAN: Byte = 0x18
    const val CLR: Byte = 0x0C
    const val EOT: Byte = 0x04

    val INIT = byteArrayOf(27, 64)
    val FEED_LINE = byteArrayOf(10)

    val SELECT_FONT_A = byteArrayOf(20, 33, 0)

    val SET_BAR_CODE_HEIGHT = byteArrayOf(29, 104, 100)
    val PRINT_BAR_CODE_1 = byteArrayOf(29, 107, 2)
    val SEND_NULL_BYTE = byteArrayOf(0x00)

    val SELECT_PRINT_SHEET = byteArrayOf(0x1B, 0x63, 0x30, 0x02)
    val FEED_PAPER_AND_CUT = byteArrayOf(0x1D, 0x56, 66, 0x00)

    val SELECT_CYRILLIC_CHARACTER_CODE_TABLE = byteArrayOf(0x1B, 0x74, 0x11)

    val SELECT_BIT_IMAGE_MODE = byteArrayOf(0x1B, 0x2A, 33, -128, 0)
    val SET_LINE_SPACING_24 = byteArrayOf(0x1B, 0x33, 24)
    val SET_LINE_SPACING_30 = byteArrayOf(0x1B, 0x33, 30)

    val TRANSMIT_DLE_PRINTER_STATUS = byteArrayOf(0x10, 0x04, 0x01)
    val TRANSMIT_DLE_OFFLINE_PRINTER_STATUS = byteArrayOf(0x10, 0x04, 0x02)
    val TRANSMIT_DLE_ERROR_STATUS = byteArrayOf(0x10, 0x04, 0x03)
    val TRANSMIT_DLE_ROLL_PAPER_SENSOR_STATUS = byteArrayOf(0x10, 0x04, 0x04)

    val ESC_FONT_COLOR_DEFAULT = byteArrayOf(0x1B, 'r'.code.toByte(), 0x00)
    val FS_FONT_ALIGN = byteArrayOf(0x1C, 0x21, 1, 0x1B, 0x21, 1) // Note: original java had 1, 0x1B... assuming 1 is byte
    val ESC_ALIGN_LEFT = byteArrayOf(0x1b, 'a'.code.toByte(), 0x00)
    val ESC_ALIGN_RIGHT = byteArrayOf(0x1b, 'a'.code.toByte(), 0x02)
    val ESC_ALIGN_CENTER = byteArrayOf(0x1b, 'a'.code.toByte(), 0x01)
    val ESC_CANCEL_BOLD = byteArrayOf(0x1B, 0x45, 0)

    /*********************************************/
    val ESC_HORIZONTAL_CENTERS = byteArrayOf(0x1B, 0x44, 20, 28, 0)
    val ESC_CANCLE_HORIZONTAL_CENTERS = byteArrayOf(0x1B, 0x44, 0)
    /*********************************************/

    val ESC_ENTER = byteArrayOf(0x1B, 0x4A, 0x40)
    val PRINTE_TEST = byteArrayOf(0x1D, 0x28, 0x41)
}
