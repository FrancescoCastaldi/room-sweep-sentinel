package com.francescocastaldi.roomsentinel

import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity(), SensorEventListener {
    private val INSTALLER_CHANNEL = "com.francescocastaldi.roomsentinel/installer"
    private val COMPASS_CHANNEL = "com.francescocastaldi.roomsentinel/compass"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sensorManager: SensorManager? = null
    private var rotationSensor: Sensor? = null
    private var accelSensor: Sensor? = null
    private var magSensor: Sensor? = null

    private var eventSink: EventChannel.EventSink? = null

    // Scratch buffers for sensor fusion
    private val rotationMatrix = FloatArray(9)
    private val remappedMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)
    private val gravityValues = FloatArray(3)
    private val geoMagValues = FloatArray(3)
    private var hasGravity = false
    private var hasGeoMag = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. In-App Package Installer Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadDirectory" -> {
                    val dir = context.cacheDir
                    result.success(dir.absolutePath)
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(context.packageManager.canRequestPackageInstalls())
                    } else {
                        result.success(true)
                    }
                }
                "openInstallPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "filePath is null", null)
                        return@setMethodCallHandler
                    }
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "File does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val contentUri = FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. Hardware Compass & Orientation EventChannel
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        setupSensors()

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, COMPASS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startCompassListening()
                }

                override fun onCancel(arguments: Any?) {
                    stopCompassListening()
                    eventSink = null
                }
            }
        )
    }

    private fun setupSensors() {
        val sm = sensorManager ?: return
        // Primary: Kalman-fused Gyro + Accel + Magnetometer rotation vector
        rotationSensor = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (rotationSensor == null) {
            // Fallback 1: Geomagnetic rotation vector (accel + mag fusion)
            rotationSensor = sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
        }
        if (rotationSensor == null) {
            // Fallback 2: Discrete accelerometer + magnetometer
            accelSensor = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            magSensor = sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        }
    }

    private fun startCompassListening() {
        val sm = sensorManager ?: return
        if (rotationSensor != null) {
            sm.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_UI)
        } else {
            accelSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            magSensor?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
        }
    }

    private fun stopCompassListening() {
        sensorManager?.unregisterListener(this)
        hasGravity = false
        hasGeoMag = false
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        var azimuthDeg: Double? = null

        if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR ||
            event.sensor.type == Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) {
            SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
            // Remap coordinate system for handheld portrait orientation
            SensorManager.remapCoordinateSystem(
                rotationMatrix,
                SensorManager.AXIS_X,
                SensorManager.AXIS_Z,
                remappedMatrix
            )
            SensorManager.getOrientation(remappedMatrix, orientationAngles)
            azimuthDeg = ((Math.toDegrees(orientationAngles[0].toDouble()) + 360.0) % 360.0)
        } else if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            System.arraycopy(event.values, 0, gravityValues, 0, 3)
            hasGravity = true
        } else if (event.sensor.type == Sensor.TYPE_MAGNETIC_FIELD) {
            System.arraycopy(event.values, 0, geoMagValues, 0, 3)
            hasGeoMag = true
        }

        if (azimuthDeg == null && hasGravity && hasGeoMag) {
            val success = SensorManager.getRotationMatrix(rotationMatrix, null, gravityValues, geoMagValues)
            if (success) {
                SensorManager.remapCoordinateSystem(
                    rotationMatrix,
                    SensorManager.AXIS_X,
                    SensorManager.AXIS_Z,
                    remappedMatrix
                )
                SensorManager.getOrientation(remappedMatrix, orientationAngles)
                azimuthDeg = ((Math.toDegrees(orientationAngles[0].toDouble()) + 360.0) % 360.0)
            }
        }

        azimuthDeg?.let { deg ->
            mainHandler.post {
                eventSink?.success(deg)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // No-op
    }

    override fun onPause() {
        super.onPause()
        stopCompassListening()
    }

    override fun onResume() {
        super.onResume()
        if (eventSink != null) {
            startCompassListening()
        }
    }

    override fun onDestroy() {
        stopCompassListening()
        super.onDestroy()
    }
}
