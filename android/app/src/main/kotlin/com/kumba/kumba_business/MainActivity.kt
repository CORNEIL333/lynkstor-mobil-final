package com.kumba.kumba_business

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.ContentUris
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.kumba.kumba_business/bluetooth_printer"
    private val analyticsChannelName = "com.kumba.kumba_business/analytics_folder"
    private val permissionRequestCode = 4207
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            analyticsChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "folderPath" -> {
                    try {
                        val dir = ensurePublicAnalyticsDir()
                        result.success(
                            mapOf(
                                "path" to dir.absolutePath,
                                "writable" to (dir.exists() && dir.canWrite())
                            )
                        )
                    } catch (error: Exception) {
                        result.error(
                            "FOLDER_FAILED",
                            error.message ?: "Dossier analytics indisponible",
                            null
                        )
                    }
                }
                "writeFile" -> {
                    val name = call.argument<String>("name")
                    val path = call.argument<String>("path")
                    val contents = call.argument<String>("contents")
                    if (name.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENTS", "Nom de fichier manquant", null)
                    } else {
                        try {
                            val written = writePublicAnalyticsFile(name, path, contents)
                            result.success(mapOf("path" to written))
                        } catch (error: Exception) {
                            result.error(
                                "WRITE_FAILED",
                                error.message ?: "Écriture analytics impossible",
                                null
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestBluetoothPermission(result)
                "pairedDevices" -> pairedDevices(result)
                "printBytes" -> {
                    val address = call.argument<String>("address")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (address.isNullOrBlank() || bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGUMENTS", "Adresse ou ticket invalide", null)
                    } else {
                        printBytes(address, bytes, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasBluetoothPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBluetoothPermission(result: MethodChannel.Result) {
        if (hasBluetoothPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_IN_PROGRESS", "Demande déjà en cours", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            permissionRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun pairedDevices(result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("PERMISSION_REQUIRED", "Permission Bluetooth requise", null)
            return
        }
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null) {
            result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth indisponible", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Activez le Bluetooth", null)
            return
        }
        val devices = adapter.bondedDevices
            .sortedBy { it.name ?: it.address }
            .map {
                mapOf(
                    "name" to (it.name ?: "Imprimante Bluetooth"),
                    "address" to it.address
                )
            }
        result.success(devices)
    }

    private fun printBytes(address: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error("PERMISSION_REQUIRED", "Permission Bluetooth requise", null)
            return
        }
        Thread {
            var socket: android.bluetooth.BluetoothSocket? = null
            try {
                val adapter = BluetoothAdapter.getDefaultAdapter()
                    ?: throw IllegalStateException("Bluetooth indisponible")
                val device = adapter.bondedDevices.firstOrNull {
                    it.address.equals(address, ignoreCase = true)
                } ?: throw IllegalArgumentException("Imprimante non appairée")
                adapter.cancelDiscovery()
                socket = device.createRfcommSocketToServiceRecord(
                    UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
                )
                socket.connect()
                socket.outputStream.use { output ->
                    output.write(bytes)
                    output.flush()
                }
                runOnUiThread { result.success(true) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "PRINT_FAILED",
                        error.message ?: "Échec de l'impression Bluetooth",
                        null
                    )
                }
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            }
        }.start()
    }

    private fun ensurePublicAnalyticsDir(): File {
        val parents = listOf(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        )
        for (parent in parents) {
            if (parent == null) continue
            val dir = File(parent, "Lynkstor")
            if (dir.exists() || dir.mkdirs()) {
                return dir
            }
        }
        val fallback = File(getExternalFilesDir(null), "Lynkstor")
        fallback.mkdirs()
        return fallback
    }

    private fun writePublicAnalyticsFile(
        name: String,
        sourcePath: String?,
        contents: String?
    ): String {
        val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val bytes = when {
            !sourcePath.isNullOrBlank() -> File(sourcePath).readBytes()
            contents != null -> contents.toByteArray(Charsets.UTF_8)
            else -> throw IllegalArgumentException("Aucun contenu analytics")
        }

        val dir = ensurePublicAnalyticsDir()
        val file = File(dir, safeName)
        try {
            file.writeBytes(bytes)
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(file.absolutePath),
                arrayOf(mimeOf(safeName)),
                null
            )
            if (file.exists() && file.length() > 0L) {
                return file.absolutePath
            }
        } catch (_: Exception) {
        }

        return writeViaMediaStore(safeName, bytes)
    }

    private fun mimeOf(name: String): String {
        return when {
            name.endsWith(".json") -> "application/json"
            name.endsWith(".csv") -> "text/csv"
            else -> "text/plain"
        }
    }

    private fun writeViaMediaStore(name: String, bytes: ByteArray): String {
        val mime = mimeOf(name)
        val relativePaths = listOf("Documents/Lynkstor/", "Download/Lynkstor/")
        val collection = MediaStore.Files.getContentUri("external")

        for (relative in relativePaths) {
            try {
                val uri = upsertMediaStoreUri(collection, name, mime, relative)
                    ?: continue
                contentResolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(bytes)
                    stream.flush()
                } ?: continue
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val done = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    contentResolver.update(uri, done, null, null)
                }
                return uri.toString()
            } catch (_: Exception) {
            }
        }
        throw IllegalStateException("Impossible d'écrire le dossier analytics public")
    }

    private fun upsertMediaStoreUri(
        collection: Uri,
        name: String,
        mime: String,
        relative: String
    ): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.query(
                collection,
                arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH}=?",
                arrayOf(name, relative),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(0)
                    return ContentUris.withAppendedId(collection, id)
                }
            }
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        return contentResolver.insert(collection, values)
    }
}
