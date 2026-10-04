package com.joryx.carepulse

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val permissionChannel = "carepulse/ble_permissions"
    private val permissionRequestCode = 30102
    private val enableRequestCode = 30103
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingEnableResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "enable") {
                    if (pendingEnableResult != null) {
                        result.error("busy", "Bluetooth enable prompt already open", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                        ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                    ) {
                        result.error("permission", "Bluetooth permission is required", null)
                        return@setMethodCallHandler
                    }
                    val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                    if (adapter == null) {
                        result.success(false)
                    } else if (adapter.isEnabled) {
                        result.success(true)
                    } else {
                        pendingEnableResult = result
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), enableRequestCode)
                        } catch (error: Exception) {
                            pendingEnableResult = null
                            result.error("unavailable", "Could not open Bluetooth prompt", error.message)
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "request") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingPermissionResult != null) {
                    result.error("busy", "Bluetooth permission request already open", null)
                    return@setMethodCallHandler
                }
                val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
                } else {
                    emptyArray()
                }
                val missing = permissions.filter {
                    ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
                }
                if (missing.isEmpty()) {
                    result.success(true)
                } else {
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(this, missing.toTypedArray(), permissionRequestCode)
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            pendingPermissionResult?.success(
                grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            )
            pendingPermissionResult = null
        }
    }

    @Deprecated("Uses the system Bluetooth enable activity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == enableRequestCode) {
            pendingEnableResult?.success(resultCode == Activity.RESULT_OK)
            pendingEnableResult = null
        }
    }
}
