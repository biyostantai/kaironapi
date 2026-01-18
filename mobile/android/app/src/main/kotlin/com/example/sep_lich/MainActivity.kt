package com.example.sep_lich

import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.sep_lich/alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "createAlarm") {
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val message = call.argument<String>("message") ?: ""
                    val weekday = call.argument<Int>("weekday")

                    val days = weekday?.let {
                        val calendarDay = when (it) {
                            1 -> Calendar.MONDAY
                            2 -> Calendar.TUESDAY
                            3 -> Calendar.WEDNESDAY
                            4 -> Calendar.THURSDAY
                            5 -> Calendar.FRIDAY
                            6 -> Calendar.SATURDAY
                            7 -> Calendar.SUNDAY
                            else -> null
                        }
                        if (calendarDay != null) arrayListOf(calendarDay) else null
                    }

                    val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                        putExtra(AlarmClock.EXTRA_HOUR, hour)
                        putExtra(AlarmClock.EXTRA_MINUTES, minute)
                        putExtra(AlarmClock.EXTRA_MESSAGE, message)
                        putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                        if (days != null && days.isNotEmpty()) {
                            putExtra(AlarmClock.EXTRA_DAYS, days)
                        }
                    }

                    val pm = packageManager
                    if (intent.resolveActivity(pm) != null) {
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.error(
                            "NO_CLOCK_APP",
                            "Không tìm thấy ứng dụng Đồng hồ trên thiết bị.",
                            null
                        )
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}

