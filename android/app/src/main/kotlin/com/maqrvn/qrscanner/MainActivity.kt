package com.maqrvn.qrscanner

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CAMERA_PERMISSION_CODE = 1001
    private val LOCATION_PERMISSION_CODE = 1002
    private lateinit var result: MethodChannel.Result

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "native_permissions").setMethodCallHandler { call, result ->
            this.result = result
            when (call.method) {
                "getCameraPermissionStatus" -> {
                    getCameraPermissionStatus()
                }
                "requestCameraPermission" -> {
                    requestCameraPermission()
                }
                "getLocationPermissionStatus" -> {
                    getLocationPermissionStatus()
                }
                "requestLocationPermission" -> {
                    requestLocationPermission()
                }
                "openAppSettings" -> {
                    openAppSettings()
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getCameraPermissionStatus() {
        val status = when {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> "authorized"
            ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.CAMERA) -> "denied"
            else -> "notDetermined"
        }
        result.success(status)
    }

    private fun requestCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
        } else {
            result.success(true)
        }
    }

    private fun getLocationPermissionStatus() {
        val fineLocationGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarseLocationGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        
        val status = when {
            fineLocationGranted || coarseLocationGranted -> "authorized"
            ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.ACCESS_FINE_LOCATION) ||
            ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.ACCESS_COARSE_LOCATION) -> "denied"
            else -> "notDetermined"
        }
        result.success(status)
    }

    private fun requestLocationPermission() {
        val permissions = arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        
        if (permissions.any { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }) {
            ActivityCompat.requestPermissions(this, permissions, LOCATION_PERMISSION_CODE)
        } else {
            result.success(true)
        }
    }

    private fun openAppSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            CAMERA_PERMISSION_CODE -> {
                val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
                if (::result.isInitialized) {
                    result.success(granted)
                }
            }
            LOCATION_PERMISSION_CODE -> {
                val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
                if (::result.isInitialized) {
                    result.success(granted)
                }
            }
        }
    }
}
