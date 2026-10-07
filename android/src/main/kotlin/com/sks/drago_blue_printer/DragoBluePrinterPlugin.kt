package com.sks.drago_blue_printer

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.*
import java.util.*
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class DragoBluePrinterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        private const val TAG = "BThermalPrinterPlugin"
        private const val NAMESPACE = "drago_blue_printer"
        private val MY_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        // Shared across engines; always read/written under [threadLock].
        private val threadLock = Any()
        private var THREAD: ConnectedThread? = null

        private fun currentThread(): ConnectedThread? = synchronized(threadLock) { THREAD }

        /// Clears THREAD if it still points at [t] (or any when t == null) and closes it.
        private fun dropThread(t: ConnectedThread?) {
            val old = synchronized(threadLock) {
                val cur = THREAD
                if (cur != null && (t == null || cur === t)) {
                    THREAD = null
                    cur
                } else null
            }
            if (old != null) {
                old.cancel()
                lastClosedAt = System.currentTimeMillis()
            }
        }

        /// When a link was last closed, so connect() can let it tear down.
        @Volatile
        private var lastClosedAt = 0L
    }

    private var mBluetoothAdapter: BluetoothAdapter? = null
    private var readSink: EventSink? = null
    private var statusSink: EventSink? = null
    private var scanSink: EventSink? = null

    private var context: Context? = null
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var stateChannel: EventChannel? = null
    private var readChannel: EventChannel? = null
    private var scanChannel: EventChannel? = null

    private var stateReceiverRegistered = false
    private var scanReceiverRegistered = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val exceptionHandler = CoroutineExceptionHandler { _, e -> Log.e(TAG, "Unhandled coroutine error", e) }
    private var scope = newScope()

    private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.IO + exceptionHandler)

    // ---------------------------------------------------------------- lifecycle

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        context = binding.applicationContext
        scope = newScope()
        channel = MethodChannel(messenger, "$NAMESPACE/methods").also { it.setMethodCallHandler(this) }
        stateChannel = EventChannel(messenger, "$NAMESPACE/state").also { it.setStreamHandler(stateStreamHandler) }
        readChannel = EventChannel(messenger, "$NAMESPACE/read").also { it.setStreamHandler(readResultsHandler) }
        scanChannel = EventChannel(messenger, "$NAMESPACE/scan").also { it.setStreamHandler(scanStreamHandler) }
        val manager = context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        mBluetoothAdapter = manager?.adapter
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopScan()
        unregisterStateReceiver()
        channel?.setMethodCallHandler(null)
        stateChannel?.setStreamHandler(null)
        readChannel?.setStreamHandler(null)
        scanChannel?.setStreamHandler(null)
        channel = null; stateChannel = null; readChannel = null; scanChannel = null
        readSink = null; statusSink = null; scanSink = null
        try { scope.cancel() } catch (e: Exception) { Log.e(TAG, "Error cancelling coroutines", e) }
        mBluetoothAdapter = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    // ---------------------------------------------------------------- results

    /// Replies on the main thread, at most once.
    private class MethodResultWrapper(private val methodResult: Result) : Result {
        private val handler = Handler(Looper.getMainLooper())
        private val replied = AtomicBoolean(false)

        private fun post(block: () -> Unit) {
            if (!replied.compareAndSet(false, true)) return
            if (Looper.myLooper() == Looper.getMainLooper()) runSafe(block) else handler.post { runSafe(block) }
        }

        private fun runSafe(block: () -> Unit) {
            try { block() } catch (e: Exception) { Log.e(TAG, "Failed to send result", e) }
        }

        override fun success(result: Any?) = post { methodResult.success(result) }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
            post { methodResult.error(errorCode, errorMessage, errorDetails) }
        override fun notImplemented() = post { methodResult.notImplemented() }
    }

    private fun postEvent(block: () -> Unit) {
        mainHandler.post { try { block() } catch (e: Exception) { Log.e(TAG, "event sink error", e) } }
    }

    // ---------------------------------------------------------------- permissions

    private fun granted(permission: String): Boolean {
        val ctx = context ?: return false
        return ContextCompat.checkSelfPermission(ctx, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || granted(Manifest.permission.BLUETOOTH_CONNECT)

    private fun hasScanPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) granted(Manifest.permission.BLUETOOTH_SCAN)
        else granted(Manifest.permission.ACCESS_FINE_LOCATION) || granted(Manifest.permission.ACCESS_COARSE_LOCATION)

    // ---------------------------------------------------------------- dispatch

    override fun onMethodCall(call: MethodCall, rawResult: Result) {
        val result = MethodResultWrapper(rawResult)
        try {
            handle(call, result)
        } catch (ex: Exception) {
            // Bad argument types etc. must not crash the platform thread.
            Log.e(TAG, "${call.method} failed", ex)
            result.error("error", ex.message, exceptionToString(ex))
        }
    }

    private fun handle(call: MethodCall, result: Result) {
        val adapter = mBluetoothAdapter
        if (call.method == "isAvailable") {
            result.success(adapter != null)
            return
        }
        if (adapter == null) {
            result.error("bluetooth_unavailable", "the device does not have bluetooth", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val arguments = call.arguments as? Map<String, Any?>
        fun str(key: String): String? = arguments?.get(key) as? String
        fun int(key: String, def: Int = 0): Int = (arguments?.get(key) as? Number)?.toInt() ?: def

        when (call.method) {
            "state" -> result.success(try { adapter.state } catch (e: Exception) { 0 })
            "isOn" -> result.success(try { adapter.isEnabled } catch (e: Exception) { false })
            "isConnected" -> result.success(currentThread()?.isAlive == true)
            "queryStatus" -> {
                val query = arguments?.get("query") as? ByteArray
                if (query == null) result.error("invalid_argument", "argument 'query' not found", null)
                else queryStatus(result, query, int("timeout", 1500))
            }
            "isDeviceConnected" -> {
                val address = str("address")
                if (address == null) result.error("invalid_argument", "argument 'address' not found", null)
                else result.success(currentThread()?.let { it.isAlive && it.address.equals(address, true) } == true)
            }
            "openSettings" -> {
                val ctx = activity ?: context
                if (ctx == null) { result.success(false); return }
                val intent = Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS)
                if (ctx !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctx.startActivity(intent)
                result.success(true)
            }
            "getBondedDevices" -> getBondedDevices(adapter, result)
            "connect" -> {
                val address = str("address")
                if (address == null) result.error("invalid_argument", "argument 'address' not found", null)
                else connect(adapter, result, address)
            }
            "disconnect" -> disconnect(result)
            "write" -> {
                val message = str("message")
                if (message == null) result.error("invalid_argument", "argument 'message' not found", null)
                else send(result) { message.toByteArray() }
            }
            "writeBytes" -> {
                val message = arguments?.get("message") as? ByteArray
                if (message == null) result.error("invalid_argument", "argument 'message' not found", null)
                else send(result) { message }
            }
            "printCustom" -> {
                val message = str("message")
                if (message == null) result.error("invalid_argument", "argument 'message' not found", null)
                else send(result) { customBytes(message, int("size"), int("align"), str("charset")) }
            }
            "printNewLine" -> send(result) { PrinterCommands.FEED_LINE }
            "paperCut" -> send(result) { PrinterCommands.FEED_PAPER_AND_CUT }
            "printImage" -> {
                val path = str("pathImage")
                if (path == null) result.error("invalid_argument", "argument 'pathImage' not found", null)
                else send(result) { imageBytes(BitmapFactory.decodeFile(path)) }
            }
            "printImageBytes" -> {
                val bytes = arguments?.get("bytes") as? ByteArray
                if (bytes == null) result.error("invalid_argument", "argument 'bytes' not found", null)
                else send(result) { imageBytes(BitmapFactory.decodeByteArray(bytes, 0, bytes.size)) }
            }
            "printLeftRight" -> {
                val s1 = str("string1"); val s2 = str("string2")
                if (s1 == null || s2 == null) result.error("invalid_argument", "argument 'string1'/'string2' not found", null)
                else send(result) { columnBytes(int("size"), str("charset"), str("format") ?: "%-15s %15s %n", s1, s2) }
            }
            "print3Column" -> {
                val s1 = str("string1"); val s2 = str("string2"); val s3 = str("string3")
                if (s1 == null || s2 == null || s3 == null) result.error("invalid_argument", "argument 'string1..3' not found", null)
                else send(result) { columnBytes(int("size"), str("charset"), str("format") ?: "%-10s %10s %10s %n", s1, s2, s3) }
            }
            "print4Column" -> {
                val s1 = str("string1"); val s2 = str("string2"); val s3 = str("string3"); val s4 = str("string4")
                if (s1 == null || s2 == null || s3 == null || s4 == null) result.error("invalid_argument", "argument 'string1..4' not found", null)
                else send(result) { columnBytes(int("size"), str("charset"), str("format") ?: "%-8s %7s %7s %7s %n", s1, s2, s3, s4) }
            }
            "pairDevice" -> {
                val address = str("address")
                if (address == null) result.error("invalid_argument", "argument 'address' not found", null)
                else pairDevice(adapter, result, address)
            }
            "printBatch" -> {
                @Suppress("UNCHECKED_CAST")
                val commands = arguments?.get("commands") as? List<Map<String, Any?>>
                if (commands == null) result.error("invalid_argument", "argument 'commands' not found", null)
                else send(result) { batchBytes(commands) }
            }
            else -> result.notImplemented()
        }
    }

    private fun exceptionToString(ex: Throwable): String {
        val sw = StringWriter()
        ex.printStackTrace(PrintWriter(sw))
        return sw.toString()
    }

    // ---------------------------------------------------------------- devices

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(adapter: BluetoothAdapter, result: Result) {
        if (!hasConnectPermission()) {
            result.error("no_permissions", "BLUETOOTH_CONNECT permission missing", null)
            return
        }
        val list: MutableList<Map<String, Any>> = ArrayList()
        for (device in adapter.bondedDevices ?: emptySet()) {
            try {
                if (!isPrinter(device)) continue
                val ret: MutableMap<String, Any> = HashMap()
                ret["address"] = device.address
                ret["name"] = device.name ?: device.address
                ret["type"] = device.type
                ret["connected"] = linkConnected(device)
                val battery = batteryLevel(device)
                if (battery >= 0) ret["battery"] = battery
                list.add(ret)
            } catch (e: Exception) {
                Log.w(TAG, "skipping bonded device: ${e.message}")
            }
        }
        result.success(list)
    }

    /// Battery % the phone knows for [device] (hidden API, Android 8.1+); -1 otherwise.
    private fun batteryLevel(device: BluetoothDevice): Int = try {
        (device.javaClass.getMethod("getBatteryLevel").invoke(device) as? Int) ?: -1
    } catch (e: Exception) { -1 }

    /// Whether the phone currently holds a link to [device] (hidden API).
    private fun linkConnected(device: BluetoothDevice): Boolean = try {
        device.javaClass.getMethod("isConnected").invoke(device) as? Boolean ?: false
    } catch (e: Exception) { false }

    @SuppressLint("MissingPermission")
    private fun isPrinter(device: BluetoothDevice): Boolean {
        val cls = try { device.bluetoothClass } catch (e: Exception) { null } ?: return false
        val major = cls.majorDeviceClass
        return major == BluetoothClass.Device.Major.IMAGING || major == BluetoothClass.Device.Major.UNCATEGORIZED
    }

    @SuppressLint("MissingPermission")
    private fun pairDevice(adapter: BluetoothAdapter, result: Result, address: String) {
        if (!hasConnectPermission()) {
            result.error("no_permissions", "BLUETOOTH_CONNECT permission missing", null)
            return
        }
        try {
            val device = adapter.getRemoteDevice(address)
            if (device.bondState == BluetoothDevice.BOND_BONDED) result.success(true)
            else result.success(device.createBond())
        } catch (ex: Exception) {
            result.error("error", ex.message, null)
        }
    }

    // ---------------------------------------------------------------- connection

    @SuppressLint("MissingPermission")
    private fun connect(adapter: BluetoothAdapter, result: Result, address: String) {
        if (!hasConnectPermission()) {
            result.error("no_permissions", "BLUETOOTH_CONNECT permission missing", null)
            return
        }
        val existing = currentThread()
        if (existing != null && existing.isAlive && existing.address.equals(address, true)) {
            result.success(true) // already connected to this printer
            return
        }
        scope.launch {
            try {
                // Close any previous (other / dead) link first.
                dropThread(null)
                // Reopening RFCOMM right after a close (disconnect -> tap the
                // printer again) fails or hangs on many printers until the
                // old channel has torn down.
                val since = System.currentTimeMillis() - lastClosedAt
                if (since in 0 until 800) kotlinx.coroutines.delay(800 - since)
                val device = adapter.getRemoteDevice(address)
                try { if (hasScanPermission()) adapter.cancelDiscovery() } catch (ignored: Exception) {}

                var socket: BluetoothSocket? = null
                val attempts: List<() -> BluetoothSocket> = listOf(
                    { device.createRfcommSocketToServiceRecord(MY_UUID) },
                    { device.createInsecureRfcommSocketToServiceRecord(MY_UUID) },
                    {
                        device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                            .invoke(device, 1) as BluetoothSocket
                    },
                )
                var lastError: Exception? = null
                for (create in attempts) {
                    var s: BluetoothSocket? = null
                    try {
                        s = create()
                        s.connect()
                        socket = s
                        break
                    } catch (e: Exception) {
                        lastError = e
                        Log.w(TAG, "connect attempt failed: ${e.message}")
                        try { s?.close() } catch (ignored: Exception) {}
                    }
                }

                if (socket == null) {
                    result.error("connect_error", "Could not connect to device: ${lastError?.message}", null)
                    return@launch
                }
                val thread = try {
                    ConnectedThread(socket, address)
                } catch (e: Exception) {
                    try { socket.close() } catch (ignored: Exception) {}
                    throw e
                }
                val old = synchronized(threadLock) { val o = THREAD; THREAD = thread; o }
                old?.cancel()
                thread.start()
                result.success(true)
            } catch (ex: Exception) {
                Log.e(TAG, ex.message, ex)
                result.error("connect_error", ex.message, exceptionToString(ex))
            }
        }
    }

    private fun disconnect(result: Result) {
        val thread = currentThread()
        if (thread == null) {
            result.error("disconnection_error", "not connected", null)
            return
        }
        scope.launch {
            dropThread(thread)
            result.success(true)
        }
    }

    // ---------------------------------------------------------------- writing

    /// Builds bytes and writes them on the IO scope; replies true, or
    /// write_error when not connected / the socket failed (link then dropped).
    private fun send(result: Result, build: () -> ByteArray?) {
        val thread = currentThread()
        if (thread == null) {
            result.error("write_error", "not connected", null)
            return
        }
        scope.launch {
            try {
                val bytes = build()
                if (bytes != null && bytes.isNotEmpty()) thread.writeAll(bytes)
                result.success(true)
            } catch (ex: IOException) {
                Log.e(TAG, "write failed, dropping connection", ex)
                dropThread(thread)
                result.error("write_error", ex.message ?: "write failed", exceptionToString(ex))
            } catch (ex: Exception) {
                Log.e(TAG, ex.message, ex)
                result.error("write_error", ex.message, exceptionToString(ex))
            }
        }
    }

    private fun queryStatus(result: Result, query: ByteArray, timeoutMs: Int) {
        val thread = currentThread()
        if (thread == null) {
            result.success(null)
            return
        }
        scope.launch {
            val reply = try {
                thread.request(query, timeoutMs.toLong())
            } catch (e: IOException) {
                dropThread(thread)
                null
            } catch (e: Exception) {
                null
            }
            result.success(reply)
        }
    }

    private fun sizeCmd(size: Int): ByteArray = when (size) {
        1 -> byteArrayOf(0x1B, 0x21, 0x08)
        2 -> byteArrayOf(0x1B, 0x21, 0x20)
        3 -> byteArrayOf(0x1B, 0x21, 0x10)
        4 -> byteArrayOf(0x1B, 0x21, 0x30)
        else -> byteArrayOf(0x1B, 0x21, 0x03)
    }

    private fun alignCmd(align: Int): ByteArray = when (align) {
        1 -> PrinterCommands.ESC_ALIGN_CENTER
        2 -> PrinterCommands.ESC_ALIGN_RIGHT
        else -> PrinterCommands.ESC_ALIGN_LEFT
    }

    private fun encode(message: String, charset: String?): ByteArray =
        if (charset != null) message.toByteArray(java.nio.charset.Charset.forName(charset)) else message.toByteArray()

    private fun customBytes(message: String, size: Int, align: Int, charset: String?): ByteArray =
        sizeCmd(size) + alignCmd(align) + encode(message, charset) + PrinterCommands.FEED_LINE

    private fun columnBytes(size: Int, charset: String?, format: String, vararg cols: String): ByteArray =
        sizeCmd(size) + PrinterCommands.ESC_ALIGN_CENTER + encode(String.format(format, *cols), charset)

    private fun imageBytes(bmp: android.graphics.Bitmap?): ByteArray? {
        if (bmp == null) {
            Log.e(TAG, "printImage: could not decode image")
            return null
        }
        val command = Utils.decodeBitmap(bmp) ?: return null
        return PrinterCommands.ESC_ALIGN_CENTER + command
    }

    /**
     * Batch print: one buffer for all commands.
     * Supported types: "custom", "leftRight", "3column", "4column", "newLine", "paperCut", "rawBytes"
     */
    private fun batchBytes(commands: List<Map<String, Any?>>): ByteArray {
        val buffer = ByteArrayOutputStream(4096)
        for (cmd in commands) {
            val type = cmd["type"] as? String ?: continue
            val size = (cmd["size"] as? Number)?.toInt() ?: 0
            val charset = cmd["charset"] as? String
            val format = cmd["format"] as? String
            fun s(k: String) = cmd[k] as? String
            when (type) {
                "custom" -> {
                    val m = s("message") ?: continue
                    buffer.write(customBytes(m, size, (cmd["align"] as? Number)?.toInt() ?: 0, charset))
                }
                "leftRight" -> {
                    val a = s("string1") ?: continue; val b = s("string2") ?: continue
                    buffer.write(columnBytes(size, charset, format ?: "%-15s %15s %n", a, b))
                }
                "3column" -> {
                    val a = s("string1") ?: continue; val b = s("string2") ?: continue; val c = s("string3") ?: continue
                    buffer.write(columnBytes(size, charset, format ?: "%-10s %10s %10s %n", a, b, c))
                }
                "4column" -> {
                    val a = s("string1") ?: continue; val b = s("string2") ?: continue
                    val c = s("string3") ?: continue; val d = s("string4") ?: continue
                    buffer.write(columnBytes(size, charset, format ?: "%-8s %7s %7s %7s %n", a, b, c, d))
                }
                "newLine" -> buffer.write(PrinterCommands.FEED_LINE)
                "paperCut" -> buffer.write(PrinterCommands.FEED_PAPER_AND_CUT)
                "rawBytes" -> (cmd["bytes"] as? ByteArray)?.let { buffer.write(it) }
            }
        }
        return buffer.toByteArray()
    }

    // ---------------------------------------------------------------- connected thread

    private inner class ConnectedThread(private val mmSocket: BluetoothSocket, val address: String) : Thread() {
        private val inputStream: InputStream = mmSocket.inputStream
        private val outputStream: OutputStream = mmSocket.outputStream
        private val writeLock = Any()
        @Volatile private var closed = false

        // Bluetooth SPP adapters have a ~4KB buffer; chunked writes avoid overflow.
        private val CHUNK_SIZE = 2048

        /// Raw reads from [run], for [request] to wait on.
        private val replies = LinkedBlockingQueue<ByteArray>()

        init { isDaemon = true; name = "drago-bt-reader" }

        override fun run() {
            val buffer = ByteArray(1024)
            while (!closed) {
                try {
                    val bytes = inputStream.read(buffer)
                    // -1 = the printer closed the link (TSPL printers do this after a job).
                    if (bytes < 0) break
                    if (bytes == 0) continue
                    replies.offer(buffer.copyOf(bytes))
                    val message = String(buffer, 0, bytes)
                    postEvent { readSink?.success(message) }
                } catch (e: Exception) {
                    // Uncaught throws here would kill the app -- end the reader instead.
                    break
                }
            }
            // Link is gone: mark disconnected so isConnected/writes see it.
            if (!closed) dropThread(this)
        }

        /// Writes [query] and returns the first reply within [timeoutMs].
        @Throws(IOException::class)
        fun request(query: ByteArray, timeoutMs: Long): ByteArray? {
            replies.clear()
            writeAll(query)
            return replies.poll(timeoutMs, TimeUnit.MILLISECONDS)
        }

        /// Writes all [bytes] (chunked when large) and flushes. Throws IOException on failure.
        @Throws(IOException::class)
        fun writeAll(bytes: ByteArray) {
            if (closed) throw IOException("connection closed")
            synchronized(writeLock) {
                var offset = 0
                while (offset < bytes.size) {
                    val length = minOf(CHUNK_SIZE, bytes.size - offset)
                    outputStream.write(bytes, offset, length)
                    outputStream.flush()
                    offset += length
                    if (offset < bytes.size) {
                        try { sleep(5) } catch (e: InterruptedException) {
                            Thread.currentThread().interrupt()
                            throw IOException("write interrupted")
                        }
                    }
                }
            }
        }

        fun cancel() {
            closed = true
            try { outputStream.flush() } catch (ignored: Exception) {}
            try { outputStream.close() } catch (ignored: Exception) {}
            try { inputStream.close() } catch (ignored: Exception) {}
            try { mmSocket.close() } catch (ignored: Exception) {}
        }
    }

    // ---------------------------------------------------------------- receivers

    private fun register(receiver: BroadcastReceiver, filter: IntentFilter): Boolean {
        val ctx = context ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= 33) ctx.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            else ctx.registerReceiver(receiver, filter)
            true
        } catch (e: Exception) {
            Log.e(TAG, "registerReceiver failed", e)
            false
        }
    }

    private fun unregister(receiver: BroadcastReceiver) {
        try { context?.unregisterReceiver(receiver) } catch (e: Exception) { Log.w(TAG, "unregisterReceiver: ${e.message}") }
    }

    private fun deviceAddress(intent: Intent): String? = try {
        @Suppress("DEPRECATION")
        intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)?.address
    } catch (e: Exception) { null }

    /// True when the ACL event is for our printer (or we can't tell).
    private fun isOurDevice(intent: Intent): Boolean {
        val ours = currentThread()?.address ?: return false
        val addr = deviceAddress(intent) ?: return true
        return ours.equals(addr, true)
    }

    private val stateReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                when (intent.action) {
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        val st = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                        if (st == BluetoothAdapter.STATE_TURNING_OFF || st == BluetoothAdapter.STATE_OFF) dropThread(null)
                        statusSink?.success(st)
                    }
                    BluetoothDevice.ACTION_ACL_CONNECTED -> statusSink?.success(1)
                    BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED -> {
                        if (isOurDevice(intent)) dropThread(null)
                        statusSink?.success(2)
                    }
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                        if (isOurDevice(intent)) dropThread(null)
                        statusSink?.success(0)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "state receiver error", e)
            }
        }
    }

    private fun unregisterStateReceiver() {
        if (stateReceiverRegistered) {
            stateReceiverRegistered = false
            unregister(stateReceiver)
        }
    }

    private val stateStreamHandler: StreamHandler = object : StreamHandler {
        override fun onListen(o: Any?, eventSink: EventSink) {
            statusSink = eventSink
            if (stateReceiverRegistered) return
            val filter = IntentFilter().apply {
                addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
                addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
                addAction(BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED)
                addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            }
            stateReceiverRegistered = register(stateReceiver, filter)
        }

        override fun onCancel(o: Any?) {
            statusSink = null
            unregisterStateReceiver()
        }
    }

    private val readResultsHandler: StreamHandler = object : StreamHandler {
        override fun onListen(o: Any?, eventSink: EventSink) { readSink = eventSink }
        override fun onCancel(o: Any?) { readSink = null }
    }

    private val scanReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context, intent: Intent) {
            try {
                if (BluetoothDevice.ACTION_FOUND != intent.action) return
                @Suppress("DEPRECATION")
                val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
                if (!isPrinter(device)) return
                val ret: MutableMap<String, Any> = HashMap()
                ret["address"] = device.address
                ret["name"] = (if (hasConnectPermission()) device.name else null) ?: "Unknown"
                ret["type"] = device.type
                scanSink?.success(ret)
            } catch (e: Exception) {
                Log.e(TAG, "scan receiver error", e)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        if (scanReceiverRegistered) {
            scanReceiverRegistered = false
            unregister(scanReceiver)
        }
        try { if (hasScanPermission()) mBluetoothAdapter?.cancelDiscovery() } catch (e: Exception) { Log.w(TAG, "cancelDiscovery: ${e.message}") }
    }

    private val scanStreamHandler: StreamHandler = object : StreamHandler {
        @SuppressLint("MissingPermission")
        override fun onListen(o: Any?, eventSink: EventSink) {
            val adapter = mBluetoothAdapter
            if (adapter == null) {
                eventSink.error("bluetooth_unavailable", "the device does not have bluetooth", null)
                return
            }
            if (!hasScanPermission()) {
                eventSink.error("no_permissions", "BLUETOOTH_SCAN / location permission missing", null)
                return
            }
            scanSink = eventSink
            if (!scanReceiverRegistered) {
                scanReceiverRegistered = register(scanReceiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
            }
            try {
                if (adapter.isDiscovering) adapter.cancelDiscovery()
                adapter.startDiscovery()
            } catch (e: Exception) {
                Log.e(TAG, "startDiscovery failed", e)
                eventSink.error("scan_error", e.message, null)
            }
        }

        override fun onCancel(o: Any?) {
            scanSink = null
            stopScan()
        }
    }
}
