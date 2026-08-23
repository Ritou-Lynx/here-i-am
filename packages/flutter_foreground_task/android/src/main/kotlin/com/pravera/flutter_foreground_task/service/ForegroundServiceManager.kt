package com.pravera.flutter_foreground_task.service

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.pravera.flutter_foreground_task.errors.ServiceAlreadyStartedException
import com.pravera.flutter_foreground_task.errors.ServiceNotStartedException
import com.pravera.flutter_foreground_task.models.ForegroundServiceAction
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus
import com.pravera.flutter_foreground_task.models.ForegroundTaskData
import com.pravera.flutter_foreground_task.models.ForegroundTaskOptions
import com.pravera.flutter_foreground_task.models.NotificationContent
import com.pravera.flutter_foreground_task.models.NotificationOptions

/**
 * A class that provides foreground service control and management functions.
 *
 * @author Dev-hwang
 * @version 1.0
 */
class ForegroundServiceManager {
	companion object {
		private val TAG = ForegroundServiceManager::class.java.simpleName
	}

	/** Start the foreground service. */
	fun start(context: Context, arguments: Any?) {
		if (isRunningService()) {
			throw ServiceAlreadyStartedException()
		}

		val nIntent = Intent(context, ForegroundService::class.java)
		val argsMap = arguments as? Map<*, *>
		ForegroundServiceStatus.setData(context, ForegroundServiceAction.API_START)
		NotificationOptions.setData(context, argsMap)
		ForegroundTaskOptions.setData(context, argsMap)
		ForegroundTaskData.setData(context, argsMap)
		NotificationContent.setData(context, argsMap)
		ContextCompat.startForegroundService(context, nIntent)
	}

	/** Restart the foreground service. */
	fun restart(context: Context) {
		if (!isRunningService()) {
			throw ServiceNotStartedException()
		}

		val nIntent = Intent(context, ForegroundService::class.java)
		ForegroundServiceStatus.setData(context, ForegroundServiceAction.API_RESTART)
		ContextCompat.startForegroundService(context, nIntent)
	}

	/** Update the foreground service. */
	fun update(context: Context, arguments: Any?) {
		if (!isRunningService()) {
			throw ServiceNotStartedException()
		}

		val nIntent = Intent(context, ForegroundService::class.java)
		val argsMap = arguments as? Map<*, *>
		ForegroundServiceStatus.setData(context, ForegroundServiceAction.API_UPDATE)
		ForegroundTaskOptions.updateData(context, argsMap)
		ForegroundTaskData.updateData(context, argsMap)
		NotificationContent.updateData(context, argsMap)
		ContextCompat.startForegroundService(context, nIntent)
	}

	/** Stop the foreground service. */
	fun stop(context: Context) {
		if (!isRunningService()) {
			throw ServiceNotStartedException()
		}

		val nIntent = Intent(context, ForegroundService::class.java)
		ForegroundServiceStatus.setData(context, ForegroundServiceAction.API_STOP)
		NotificationOptions.clearData(context)
		ForegroundTaskOptions.clearData(context)
		ForegroundTaskData.clearData(context)
		NotificationContent.clearData(context)
		try {
			ContextCompat.startForegroundService(context, nIntent)
		} catch (e: Exception) {
			// Here I am fork: Android 12+ may deny startForegroundService from a background
			// context (e.g. the drain-service finally block when the user has already
			// backgrounded the app). The intent carries API_STOP, so the goal is just to
			// deliver it to the running service. Fall back to a plain stopService — for a
			// service that is currently running, stopService() works from background without
			// the FGS-start exemption, and the service will stop itself cleanly.
			Log.w(TAG, "stop: startForegroundService denied, falling back to stopService.", e)
			try {
				context.stopService(nIntent)
			} catch (inner: Exception) {
				Log.w(TAG, "stop: stopService fallback also failed", inner)
			}
		}
	}

	/** Send data to TaskHandler. */
	fun sendData(data: Any?) {
		if (data != null) {
			ForegroundService.sendData(data)
		}
	}

	/** Returns whether the foreground service is running. */
	fun isRunningService(): Boolean = ForegroundService.isRunningServiceState.value
}
