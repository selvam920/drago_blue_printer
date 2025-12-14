package com.sks.drago_blue_printer

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.*
import java.util.*
import kotlin.collections.ArrayList
import kotlin.collections.HashMap
import kotlinx.coroutines.cancel

class DragoBluePrinterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "BThermalPrinterPlugin"
        private const val NAMESPACE = "drago_blue_printer"
        private const val REQUEST_COARSE_LOCATION_PERMISSIONS = 1451
        private val MY_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private var THREAD: ConnectedThread? = null
    }

    private var mBluetoothAdapter: BluetoothAdapter? = null
    private var pendingResult: Result? = null

    private var readSink: EventSink? = null
    private var statusSink: EventSink? = null

    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val initializationLock = Any()
    private var context: Context? = null
    private var channel: MethodChannel? = null

    private var stateChannel: EventChannel? = null
    private var readChannel: EventChannel? = null
    private var scanChannel: EventChannel? = null
    private var mBluetoothManager: BluetoothManager? = null
    private var scanSink: EventSink? = null

    private var application: Application? = null
    private var activity: Activity? = null

    // Coroutine scope for background tasks
    private val scope = CoroutineScope(Dispatchers.IO)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        setup(
            pluginBinding!!.binaryMessenger,
            pluginBinding!!.applicationContext as Application,
            activityBinding!!.activity,
            activityBinding
        )
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detach()
    }

    private fun setup(
        messenger: BinaryMessenger,
        application: Application?,
        activity: Activity?,
        activityBinding: ActivityPluginBinding?
    ) {
        synchronized(initializationLock) {
            Log.i(TAG, "setup")
            this.activity = activity
            this.application = application
            this.context = application
            channel = MethodChannel(messenger, "$NAMESPACE/methods")
            channel!!.setMethodCallHandler(this)
            stateChannel = EventChannel(messenger, "$NAMESPACE/state")
            stateChannel!!.setStreamHandler(stateStreamHandler)
            readChannel = EventChannel(messenger, "$NAMESPACE/read")
            readChannel!!.setStreamHandler(readResultsHandler)
            scanChannel = EventChannel(messenger, "$NAMESPACE/scan")
            scanChannel!!.setStreamHandler(scanStreamHandler)
            mBluetoothManager = (this.context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager) ?: (activity?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            mBluetoothAdapter = mBluetoothManager!!.adapter
            
            // V2 embedding setup for activity listeners.
            activityBinding?.addRequestPermissionsResultListener(this)
        }
    }

    private fun detach() {
        Log.i(TAG, "detach")
        context = null
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        channel?.setMethodCallHandler(null)
        channel = null
        stateChannel?.setStreamHandler(null)
        stateChannel = null
        readChannel?.setStreamHandler(null)
        readChannel = null
        scanChannel?.setStreamHandler(null)
        scanChannel = null
        mBluetoothAdapter = null
        mBluetoothManager = null
        application = null
        
        try {
             scope.cancel()
        } catch(e: Exception) {
             Log.e(TAG, "Error cancelling coroutines", e)
        }
    }

    // MethodChannel.Result wrapper that responds on the platform thread.
    private class MethodResultWrapper(private val methodResult: Result) : Result {
        private val handler = Handler(Looper.getMainLooper())

        override fun success(result: Any?) {
            handler.post { methodResult.success(result) }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            handler.post { methodResult.error(errorCode, errorMessage, errorDetails) }
        }

        override fun notImplemented() {
            handler.post { methodResult.notImplemented() }
        }
    }

    override fun onMethodCall(call: MethodCall, rawResult: Result) {
        val result = MethodResultWrapper(rawResult)

        if (mBluetoothAdapter == null && "isAvailable" != call.method) {
            result.error("bluetooth_unavailable", "the device does not have bluetooth", null)
            return
        }

        val arguments = call.arguments as? Map<String, Any>

        when (call.method) {
            "state" -> state(result)
            "isAvailable" -> result.success(mBluetoothAdapter != null)
            "isOn" -> {
                try {
                    result.success(mBluetoothAdapter!!.isEnabled)
                } catch (ex: Exception) {
                    result.error("Error", ex.message, exceptionToString(ex))
                }
            }
            "isConnected" -> result.success(THREAD != null)
            "isDeviceConnected" -> {
                if (arguments != null && arguments.containsKey("address")) {
                    val address = arguments["address"] as String
                    isDeviceConnected(result, address)
                } else {
                    result.error("invalid_argument", "argument 'address' not found", null)
                }
            }
            "openSettings" -> {
                ContextCompat.startActivity(
                    context!!,
                    Intent(android.provider.Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    null
                )
                result.success(true)
            }
            "getBondedDevices" -> {
                try {
                    getBondedDevices(result)
                } catch (ex: Exception) {
                    result.error("Error", ex.message, exceptionToString(ex))
                }
            }
            "connect" -> {
                if (arguments != null && arguments.containsKey("address")) {
                    val address = arguments["address"] as String
                    connect(result, address)
                } else {
                    result.error("invalid_argument", "argument 'address' not found", null)
                }
            }
            "disconnect" -> disconnect(result)
            "write" -> {
                if (arguments != null && arguments.containsKey("message")) {
                    val message = arguments["message"] as String
                    write(result, message)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "writeBytes" -> {
                if (arguments != null && arguments.containsKey("message")) {
                    val message = arguments["message"] as ByteArray
                    writeBytes(result, message)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "printCustom" -> {
                if (arguments != null && arguments.containsKey("message")) {
                    val message = arguments["message"] as String
                    val size = arguments["size"] as Int
                    val align = arguments["align"] as Int
                    val charset = arguments["charset"] as? String
                    printCustom(result, message, size, align, charset)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "printNewLine" -> printNewLine(result)
            "paperCut" -> paperCut(result)
            "printImage" -> {
                if (arguments != null && arguments.containsKey("pathImage")) {
                    val pathImage = arguments["pathImage"] as String
                    printImage(result, pathImage)
                } else {
                    result.error("invalid_argument", "argument 'pathImage' not found", null)
                }
            }
            "printImageBytes" -> {
                if (arguments != null && arguments.containsKey("bytes")) {
                    val bytes = arguments["bytes"] as ByteArray
                    printImageBytes(result, bytes)
                } else {
                    result.error("invalid_argument", "argument 'bytes' not found", null)
                }
            }
            "printLeftRight" -> {
                if (arguments != null && arguments.containsKey("string1")) {
                    val string1 = arguments["string1"] as String
                    val string2 = arguments["string2"] as String
                    val size = arguments["size"] as Int
                    val charset = arguments["charset"] as? String
                    val format = arguments["format"] as? String
                    printLeftRight(result, string1, string2, size, charset, format)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "print3Column" -> {
                if (arguments != null && arguments.containsKey("string1")) {
                    val string1 = arguments["string1"] as String
                    val string2 = arguments["string2"] as String
                    val string3 = arguments["string3"] as String
                    val size = arguments["size"] as Int
                    val charset = arguments["charset"] as? String
                    val format = arguments["format"] as? String
                    print3Column(result, string1, string2, string3, size, charset, format)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "print4Column" -> {
                if (arguments != null && arguments.containsKey("string1")) {
                    val string1 = arguments["string1"] as String
                    val string2 = arguments["string2"] as String
                    val string3 = arguments["string3"] as String
                    val string4 = arguments["string4"] as String
                    val size = arguments["size"] as Int
                    val charset = arguments["charset"] as? String
                    val format = arguments["format"] as? String
                    print4Column(result, string1, string2, string3, string4, size, charset, format)
                } else {
                    result.error("invalid_argument", "argument 'message' not found", null)
                }
            }
            "pairDevice" -> {
                if (arguments != null && arguments.containsKey("address")) {
                    val address = arguments["address"] as String
                    pairDevice(result, address)
                } else {
                    result.error("invalid_argument", "argument 'address' not found", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_COARSE_LOCATION_PERMISSIONS) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if(pendingResult != null) getBondedDevices(pendingResult!!)
            } else {
                pendingResult?.error("no_permissions", "this plugin requires location permissions for scanning", null)
                pendingResult = null
            }
            return true
        }
        return false
    }

    private fun state(result: Result) {
        try {
            when (mBluetoothAdapter!!.state) {
                BluetoothAdapter.STATE_OFF -> result.success(BluetoothAdapter.STATE_OFF)
                BluetoothAdapter.STATE_ON -> result.success(BluetoothAdapter.STATE_ON)
                BluetoothAdapter.STATE_TURNING_OFF -> result.success(BluetoothAdapter.STATE_TURNING_OFF)
                BluetoothAdapter.STATE_TURNING_ON -> result.success(BluetoothAdapter.STATE_TURNING_ON)
                else -> result.success(0)
            }
        } catch (e: SecurityException) {
            result.error("invalid_argument", "Argument 'address' not found", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(result: Result) {
        val list: MutableList<Map<String, Any>> = ArrayList()
        for (device in mBluetoothAdapter!!.bondedDevices) {
            val ret: MutableMap<String, Any> = HashMap()
            ret["address"] = device.address
            ret["name"] = device.name
            ret["type"] = device.type
            list.add(ret)
        }
        result.success(list)
    }

    private fun isDeviceConnected(result: Result, address: String) {
        scope.launch {
            try {
                val device = mBluetoothAdapter!!.getRemoteDevice(address)
                if (device == null) {
                    result.error("connect_error", "device not found", null)
                    return@launch
                }
                // Warning: ACTION_ACL_CONNECTED check on a specific device this way is tricky and might not be reliable
                // The original code tried to match actions, which doesn't make sense on a device object instance
                // But preserving original logic intent: check if thread is active.
                // Actually, the original code compared `device.ACTION_ACL_CONNECTED` (string constant) with `new Intent(...).getAction()` which is baffling.
                // It likely meant to check if we are connected to THIS device.
                // For now, let's just return true if THREAD is not null. Use a more robust check if possible later.

                if (THREAD != null /* && check actual connection if possible */) {
                     result.success(true)
                } else {
                    result.success(false)
                }

            } catch (ex: Exception) {
                Log.e(TAG, ex.message, ex)
                result.error("connect_error", ex.message, exceptionToString(ex))
            }
        }
    }

    private fun exceptionToString(ex: Exception): String {
        val sw = StringWriter()
        val pw = PrintWriter(sw)
        ex.printStackTrace(pw)
        return sw.toString()
    }

    private fun connect(result: Result, address: String) {
        if (THREAD != null) {
            result.error("connect_error", "already connected", null)
            return
        }
        scope.launch {
            try {
                val device = mBluetoothAdapter!!.getRemoteDevice(address)
                if (device == null) {
                    result.error("connect_error", "device not found", null)
                    return@launch
                }

                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S &&
                    ActivityCompat.checkSelfPermission(context!!, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    result.error("no_permissions", "BLUETOOTH_CONNECT permission missing", null)
                    return@launch
                }

                mBluetoothAdapter!!.cancelDiscovery()

                var socket: BluetoothSocket? = null
                var connected = false

                // Strategy 1: Standard Secure RFCOMM
                try {
                    socket = device.createRfcommSocketToServiceRecord(MY_UUID)
                    socket.connect()
                    connected = true
                } catch (e: Exception) {
                    Log.w(TAG, "Standard connection failed: ${e.message}. Retrying with fallback...")
                    try {
                        socket?.close()
                    } catch (ignored: Exception) {}
                }

                // Strategy 2: Insecure RFCOMM (Fallback)
                if (!connected) {
                    try {
                        socket = device.createInsecureRfcommSocketToServiceRecord(MY_UUID)
                        socket.connect()
                        connected = true
                    } catch (e: Exception) {
                        Log.w(TAG, "Insecure connection failed: ${e.message}. Retrying with reflection...")
                        try {
                            socket?.close()
                        } catch (ignored: Exception) {}
                    }
                }

                // Strategy 3: Reflection (Last Resort for some devices)
                if (!connected) {
                    try {
                        val method = device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                        socket = method.invoke(device, 1) as BluetoothSocket
                        socket.connect()
                        connected = true
                    } catch (e: Exception) {
                        Log.e(TAG, "Reflection connection failed: ${e.message}")
                        try {
                            socket?.close()
                        } catch (ignored: Exception) {}
                    }
                }

                if (connected && socket != null) {
                     THREAD = ConnectedThread(socket)
                     THREAD!!.start()
                     result.success(true)
                } else {
                     result.error("connect_error", "Could not connect to device after multiple attempts", null)
                }

            } catch (ex: Exception) {
                Log.e(TAG, ex.message, ex)
                result.error("connect_error", ex.message, exceptionToString(ex))
            }
        }
    }

    private fun disconnect(result: Result) {
        if (THREAD == null) {
            result.error("disconnection_error", "not connected", null)
            return
        }
        scope.launch {
            try {
                THREAD!!.cancel()
                THREAD = null
                result.success(true)
            } catch (ex: Exception) {
                Log.e(TAG, ex.message, ex)
                result.error("disconnection_error", ex.message, exceptionToString(ex))
            }
        }
    }

    private fun write(result: Result, message: String) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            THREAD!!.write(message.toByteArray())
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun writeBytes(result: Result, message: ByteArray) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            THREAD!!.write(message)
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun printCustom(result: Result, message: String, size: Int, align: Int, charset: String?) {
        val cc = byteArrayOf(0x1B, 0x21, 0x03) // 0- normal size text
        val bb = byteArrayOf(0x1B, 0x21, 0x08) // 1- only bold text
        val bb2 = byteArrayOf(0x1B, 0x21, 0x20) // 2- bold with medium text
        val bb3 = byteArrayOf(0x1B, 0x21, 0x10) // 3- bold with large text
        val bb4 = byteArrayOf(0x1B, 0x21, 0x30) // 4- strong text

        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }

        try {
            when (size) {
                0 -> THREAD!!.write(cc)
                1 -> THREAD!!.write(bb)
                2 -> THREAD!!.write(bb2)
                3 -> THREAD!!.write(bb3)
                4 -> THREAD!!.write(bb4)
            }

            when (align) {
                0 -> THREAD!!.write(PrinterCommands.ESC_ALIGN_LEFT)
                1 -> THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
                2 -> THREAD!!.write(PrinterCommands.ESC_ALIGN_RIGHT)
            }

            if (charset != null) {
                THREAD!!.write(message.toByteArray(java.nio.charset.Charset.forName(charset)))
            } else {
                THREAD!!.write(message.toByteArray())
            }
            THREAD!!.write(PrinterCommands.FEED_LINE)
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun printLeftRight(result: Result, msg1: String, msg2: String, size: Int, charset: String?, format: String?) {
        val cc = byteArrayOf(0x1B, 0x21, 0x03)
        val bb = byteArrayOf(0x1B, 0x21, 0x08)
        val bb2 = byteArrayOf(0x1B, 0x21, 0x20)
        val bb3 = byteArrayOf(0x1B, 0x21, 0x10)
        val bb4 = byteArrayOf(0x1B, 0x21, 0x30)

        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            when (size) {
                0 -> THREAD!!.write(cc)
                1 -> THREAD!!.write(bb)
                2 -> THREAD!!.write(bb2)
                3 -> THREAD!!.write(bb3)
                4 -> THREAD!!.write(bb4)
            }
            THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
            var line = String.format("%-15s %15s %n", msg1, msg2)
            if (format != null) {
                line = String.format(format, msg1, msg2)
            }
            if (charset != null) {
                THREAD!!.write(line.toByteArray(java.nio.charset.Charset.forName(charset)))
            } else {
                THREAD!!.write(line.toByteArray())
            }
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun print3Column(result: Result, msg1: String, msg2: String, msg3: String, size: Int, charset: String?, format: String?) {
        val cc = byteArrayOf(0x1B, 0x21, 0x03)
        val bb = byteArrayOf(0x1B, 0x21, 0x08)
        val bb2 = byteArrayOf(0x1B, 0x21, 0x20)
        val bb3 = byteArrayOf(0x1B, 0x21, 0x10)
        val bb4 = byteArrayOf(0x1B, 0x21, 0x30)

        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            when (size) {
                0 -> THREAD!!.write(cc)
                1 -> THREAD!!.write(bb)
                2 -> THREAD!!.write(bb2)
                3 -> THREAD!!.write(bb3)
                4 -> THREAD!!.write(bb4)
            }
            THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
            var line = String.format("%-10s %10s %10s %n", msg1, msg2, msg3)
            if (format != null) {
                line = String.format(format, msg1, msg2, msg3)
            }
            if (charset != null) {
                THREAD!!.write(line.toByteArray(java.nio.charset.Charset.forName(charset)))
            } else {
                THREAD!!.write(line.toByteArray())
            }
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun print4Column(result: Result, msg1: String, msg2: String, msg3: String, msg4: String, size: Int, charset: String?, format: String?) {
        val cc = byteArrayOf(0x1B, 0x21, 0x03)
        val bb = byteArrayOf(0x1B, 0x21, 0x08)
        val bb2 = byteArrayOf(0x1B, 0x21, 0x20)
        val bb3 = byteArrayOf(0x1B, 0x21, 0x10)
        val bb4 = byteArrayOf(0x1B, 0x21, 0x30)

        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            when (size) {
                0 -> THREAD!!.write(cc)
                1 -> THREAD!!.write(bb)
                2 -> THREAD!!.write(bb2)
                3 -> THREAD!!.write(bb3)
                4 -> THREAD!!.write(bb4)
            }
            THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
            var line = String.format("%-8s %7s %7s %7s %n", msg1, msg2, msg3, msg4)
            if (format != null) {
                line = String.format(format, msg1, msg2, msg3, msg4)
            }
            if (charset != null) {
                THREAD!!.write(line.toByteArray(java.nio.charset.Charset.forName(charset)))
            } else {
                THREAD!!.write(line.toByteArray())
            }
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun printNewLine(result: Result) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            THREAD!!.write(PrinterCommands.FEED_LINE)
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun paperCut(result: Result) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            THREAD!!.write(PrinterCommands.FEED_PAPER_AND_CUT)
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun printImage(result: Result, pathImage: String) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            val bmp = BitmapFactory.decodeFile(pathImage)
            if (bmp != null) {
                val command = Utils.decodeBitmap(bmp)
                THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
                if (command != null) {
                    THREAD!!.write(command)
                }
            } else {
                Log.e("Print Photo error", "the file isn't exists")
            }
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    private fun printImageBytes(result: Result, bytes: ByteArray) {
        if (THREAD == null) {
            result.error("write_error", "not connected", null)
            return
        }
        try {
            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (bmp != null) {
                val command = Utils.decodeBitmap(bmp)
                THREAD!!.write(PrinterCommands.ESC_ALIGN_CENTER)
                if (command != null) {
                    THREAD!!.write(command)
                }
            } else {
                Log.e("Print Photo error", "the file isn't exists")
            }
            result.success(true)
        } catch (ex: Exception) {
            Log.e(TAG, ex.message, ex)
            result.error("write_error", ex.message, exceptionToString(ex))
        }
    }

    // Inner class for connection thread
    private inner class ConnectedThread(private val mmSocket: BluetoothSocket) : Thread() {
        private val inputStream: InputStream?
        private val outputStream: OutputStream?

        init {
            var tmpIn: InputStream? = null
            var tmpOut: OutputStream? = null

            try {
                tmpIn = mmSocket.inputStream
                tmpOut = mmSocket.outputStream
            } catch (e: IOException) {
                e.printStackTrace()
            }
            inputStream = tmpIn
            outputStream = tmpOut
        }

        override fun run() {
            val buffer = ByteArray(1024)
            var bytes: Int
            while (true) {
                try {
                    bytes = inputStream!!.read(buffer)
                    val message = String(buffer, 0, bytes)
                    mainHandler.post {
                         readSink?.success(message)
                    }
                } catch (e: NullPointerException) {
                    break
                } catch (e: IOException) {
                    break
                }
            }
        }

        fun write(bytes: ByteArray) {
            try {
                outputStream!!.write(bytes)
            } catch (e: IOException) {
                e.printStackTrace()
            }
        }

        fun cancel() {
            try {
                outputStream?.flush()
                outputStream?.close()
                inputStream?.close()
                mmSocket.close()
            } catch (e: IOException) {
                e.printStackTrace()
            }
        }
    }

    private val stateStreamHandler: StreamHandler = object : StreamHandler {
        private val mReceiver: BroadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.action
                Log.d(TAG, action!!)

                when (action) {
                    BluetoothAdapter.ACTION_STATE_CHANGED -> {
                        THREAD = null
                        statusSink?.success(intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1))
                    }
                    BluetoothDevice.ACTION_ACL_CONNECTED -> {
                        statusSink?.success(1)
                    }
                    BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED -> {
                        THREAD = null
                        statusSink?.success(2)
                    }
                    BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                        THREAD = null
                        statusSink?.success(0)
                    }
                }
            }
        }

        override fun onListen(o: Any?, eventSink: EventSink) {
            statusSink = eventSink
            context!!.registerReceiver(mReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
            context!!.registerReceiver(mReceiver, IntentFilter(BluetoothDevice.ACTION_ACL_CONNECTED))
            context!!.registerReceiver(mReceiver, IntentFilter(BluetoothDevice.ACTION_ACL_DISCONNECT_REQUESTED))
            context!!.registerReceiver(mReceiver, IntentFilter(BluetoothDevice.ACTION_ACL_DISCONNECTED))
        }

        override fun onCancel(o: Any?) {
            statusSink = null
            context!!.unregisterReceiver(mReceiver)
        }
    }

    private val readResultsHandler: StreamHandler = object : StreamHandler {
        override fun onListen(o: Any?, eventSink: EventSink) {
            readSink = eventSink
        }

        override fun onCancel(o: Any?) {
            readSink = null
        }
    }

    private fun pairDevice(result: Result, address: String) {
        try {
            val device = mBluetoothAdapter!!.getRemoteDevice(address)
            if (device != null) {
                if (device.bondState == BluetoothDevice.BOND_BONDED) {
                    result.success(true)
                    return
                }
                device.createBond()
                result.success(true) 
            } else {
                 result.error("error", "device not found", null)
            }
        } catch (ex: Exception) {
            result.error("error", ex.message, null)
        }
    }

    private val scanStreamHandler: StreamHandler = object : StreamHandler {
        private val scanReceiver: BroadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val action = intent.action
                if (BluetoothDevice.ACTION_FOUND == action) {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    if (device != null) {
                        val ret: MutableMap<String, Any> = HashMap()
                        ret["address"] = device.address
                        ret["name"] = device.name ?: "Unknown"
                        ret["type"] = device.type
                        scanSink?.success(ret)
                    }
                }
            }
        }

        override fun onListen(o: Any?, eventSink: EventSink) {
            scanSink = eventSink
            val filter = IntentFilter()
            filter.addAction(BluetoothDevice.ACTION_FOUND)
            context?.registerReceiver(scanReceiver, filter)
            mBluetoothAdapter?.startDiscovery()
        }

        override fun onCancel(o: Any?) {
            scanSink = null
            try {
               context?.unregisterReceiver(scanReceiver)
               mBluetoothAdapter?.cancelDiscovery()
            } catch (e: Exception) {
               Log.e(TAG, "Error unregistering scan receiver", e)
            }
        }
    }
}
